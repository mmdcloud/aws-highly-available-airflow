"""
test_dags.py
------------
Production test suite for HA Airflow DAGs.
Run with: pytest tests/test_dags.py -v

Tests cover:
- DAG import integrity (no syntax errors, no import-time side effects)
- DAG structure validation (required tags, no cycles, task timeouts set)
- Task configuration (retries, callbacks, queues)
- Health check DAG logic (mocked infra)
- ETL pipeline logic (mocked S3, mocked DB)
- Idempotency of extract/load
"""

from __future__ import annotations

import os
import json
import importlib
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import MagicMock, patch, call
import pytest

# ── Fixtures ──────────────────────────────────────────────────────────────────

DAGS_FOLDER = Path(__file__).parent.parent / "dags"

@pytest.fixture(scope="session")
def dag_bag():
    """Load all DAGs once per test session."""
    os.environ.setdefault("AIRFLOW__CORE__DAGS_FOLDER", str(DAGS_FOLDER))
    os.environ.setdefault("AIRFLOW__DATABASE__SQL_ALCHEMY_CONN", "sqlite:///:memory:")
    os.environ.setdefault("AIRFLOW__CORE__EXECUTOR", "SequentialExecutor")

    from airflow.models import DagBag
    bag = DagBag(dag_folder=str(DAGS_FOLDER), include_examples=False)
    return bag


@pytest.fixture
def mock_boto3_sns():
    with patch("boto3.client") as mock:
        sns_client = MagicMock()
        mock.return_value = sns_client
        yield sns_client


@pytest.fixture
def mock_boto3_s3():
    with patch("boto3.client") as mock:
        s3_client = MagicMock()
        s3_client.get_object.return_value = {
            "Body": MagicMock(read=lambda: json.dumps([
                {"id": 1, "value": "RECORD_1", "partition": "2024/01/01/00", "transformed_at": "2024-01-01T00:00:00"}
            ]).encode())
        }
        mock.return_value = s3_client
        yield s3_client


@pytest.fixture
def mock_task_instance():
    ti = MagicMock()
    ti.xcom_pull.side_effect = lambda task_ids, key: {
        ("extract", "record_count"): 100,
        ("extract", "partition"): "2024/01/01/00",
    }.get((task_ids, key))
    ti.log_url = "http://airflow/log"
    return ti


@pytest.fixture
def base_context(mock_task_instance):
    dag_mock = MagicMock()
    dag_mock.dag_id = "etl_pipeline"
    return {
        "task_instance": mock_task_instance,
        "execution_date": datetime(2024, 1, 1, 0, 0, 0),
        "dag": dag_mock,
        "exception": "Test exception",
    }


# ── DAG integrity tests ────────────────────────────────────────────────────────

class TestDagImportIntegrity:
    def test_no_import_errors(self, dag_bag):
        """All DAGs must import cleanly with no errors."""
        assert dag_bag.import_errors == {}, (
            f"DAG import errors:\n" +
            "\n".join(f"  {k}: {v}" for k, v in dag_bag.import_errors.items())
        )

    def test_expected_dags_present(self, dag_bag):
        """Required DAGs must be present in the bag."""
        expected = {"platform_health_check", "etl_pipeline"}
        missing = expected - set(dag_bag.dag_ids)
        assert not missing, f"Missing DAGs: {missing}"

    def test_no_example_dags(self, dag_bag):
        """Example DAGs must not be loaded in production."""
        example_dags = [d for d in dag_bag.dag_ids if d.startswith("example_")]
        assert not example_dags, f"Example DAGs found: {example_dags}"


class TestDagStructure:
    @pytest.mark.parametrize("dag_id", ["platform_health_check", "etl_pipeline"])
    def test_dag_has_tags(self, dag_bag, dag_id):
        """All DAGs must have at least one tag for organisation."""
        dag = dag_bag.get_dag(dag_id)
        assert dag.tags, f"{dag_id} has no tags"

    @pytest.mark.parametrize("dag_id", ["platform_health_check", "etl_pipeline"])
    def test_dag_has_description(self, dag_bag, dag_id):
        """All DAGs must have a description."""
        dag = dag_bag.get_dag(dag_id)
        assert dag.description, f"{dag_id} has no description"

    @pytest.mark.parametrize("dag_id", ["platform_health_check", "etl_pipeline"])
    def test_no_catchup(self, dag_bag, dag_id):
        """Catchup must be disabled to prevent backfill on deploy."""
        dag = dag_bag.get_dag(dag_id)
        assert not dag.catchup, f"{dag_id} has catchup=True"

    @pytest.mark.parametrize("dag_id", ["platform_health_check", "etl_pipeline"])
    def test_no_cycles(self, dag_bag, dag_id):
        """DAG must be acyclic."""
        dag = dag_bag.get_dag(dag_id)
        assert dag.test_cycle() is False, f"{dag_id} contains a cycle"

    @pytest.mark.parametrize("dag_id", ["platform_health_check", "etl_pipeline"])
    def test_all_tasks_have_execution_timeout(self, dag_bag, dag_id):
        """All tasks must have an execution_timeout to prevent runaway tasks."""
        dag = dag_bag.get_dag(dag_id)
        for task in dag.tasks:
            assert task.execution_timeout is not None, (
                f"{dag_id}.{task.task_id} has no execution_timeout"
            )

    def test_health_check_schedule(self, dag_bag):
        """Health check must run at least every 5 minutes."""
        dag = dag_bag.get_dag("platform_health_check")
        assert dag.schedule_interval == "*/5 * * * *"

    def test_etl_max_active_runs(self, dag_bag):
        """ETL pipeline must limit concurrent runs to prevent resource exhaustion."""
        dag = dag_bag.get_dag("etl_pipeline")
        assert dag.max_active_runs <= 5, "max_active_runs is too high"

    def test_etl_tasks_have_retries(self, dag_bag):
        """All ETL tasks must retry on failure."""
        dag = dag_bag.get_dag("etl_pipeline")
        for task in dag.tasks:
            if task.task_id not in ("start", "end"):
                assert task.retries >= 1, (
                    f"etl_pipeline.{task.task_id} has retries=0"
                )

    def test_etl_tasks_have_failure_callback(self, dag_bag):
        """All ETL tasks must have on_failure_callback for alerting."""
        dag = dag_bag.get_dag("etl_pipeline")
        for task in dag.tasks:
            if task.task_id not in ("start", "end", "validate_extract"):
                assert task.on_failure_callback is not None, (
                    f"etl_pipeline.{task.task_id} missing on_failure_callback"
                )


# ── Health check DAG tests ─────────────────────────────────────────────────────

class TestHealthCheckDag:

    def test_metadata_db_check_passes(self):
        """check_metadata_db should pass when DB responds to SELECT 1."""
        from dags.dag_health_check import check_metadata_db
        mock_session = MagicMock()
        with patch("airflow.settings.Session", return_value=mock_session):
            check_metadata_db()  # Should not raise
        mock_session.execute.assert_called_once_with("SELECT 1")
        mock_session.close.assert_called_once()

    def test_metadata_db_check_fails_and_alerts(self, mock_boto3_sns):
        """check_metadata_db should send SNS alert and raise on DB failure."""
        from dags.dag_health_check import check_metadata_db
        from airflow.exceptions import AirflowException
        mock_session = MagicMock()
        mock_session.execute.side_effect = Exception("Connection refused")

        with patch("airflow.settings.Session", return_value=mock_session):
            with patch.dict(os.environ, {"ALERT_SNS_TOPIC_ARN": "arn:aws:sns:us-east-1:123:test"}):
                with pytest.raises(AirflowException, match="Metadata DB check failed"):
                    check_metadata_db()

    def test_celery_broker_check_passes(self):
        """check_celery_broker should pass when Redis responds to PING."""
        from dags.dag_health_check import check_celery_broker
        mock_redis = MagicMock()
        mock_redis.ping.return_value = True
        with patch("redis.Redis.from_url", return_value=mock_redis):
            with patch.dict(os.environ, {"AIRFLOW__CELERY__BROKER_URL": "rediss://:token@host:6379/0"}):
                check_celery_broker()
        mock_redis.ping.assert_called_once()

    def test_celery_broker_check_fails_on_timeout(self):
        """check_celery_broker should raise when Redis times out."""
        from dags.dag_health_check import check_celery_broker
        from airflow.exceptions import AirflowException
        with patch("redis.Redis.from_url") as mock_redis_cls:
            mock_redis_cls.return_value.ping.side_effect = Exception("timeout")
            with patch.dict(os.environ, {"AIRFLOW__CELERY__BROKER_URL": "rediss://:token@host:6379/0"}):
                with pytest.raises(AirflowException, match="Celery broker check failed"):
                    check_celery_broker()

    def test_efs_check_passes(self, tmp_path):
        """check_efs_dags_folder should pass when folder is writable."""
        from dags.dag_health_check import check_efs_dags_folder
        with patch.dict(os.environ, {"AIRFLOW__CORE__DAGS_FOLDER": str(tmp_path)}):
            check_efs_dags_folder()
        # Probe file should be cleaned up
        assert not (tmp_path / ".healthcheck").exists()

    def test_efs_check_fails_on_permission_error(self, tmp_path):
        """check_efs_dags_folder should raise when folder is not writable."""
        from dags.dag_health_check import check_efs_dags_folder
        from airflow.exceptions import AirflowException
        with patch("builtins.open", side_effect=PermissionError("read-only")):
            with patch.dict(os.environ, {"AIRFLOW__CORE__DAGS_FOLDER": str(tmp_path)}):
                with pytest.raises(AirflowException, match="EFS DAGs folder check failed"):
                    check_efs_dags_folder()

    def test_s3_check_skipped_when_not_configured(self):
        """check_s3_log_bucket should skip gracefully if remote logging not set."""
        from dags.dag_health_check import check_s3_log_bucket
        with patch.dict(os.environ, {"AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER": ""}):
            with patch("boto3.client") as mock_boto:
                check_s3_log_bucket()
                mock_boto.assert_not_called()

    def test_s3_check_passes(self, mock_boto3_s3):
        """check_s3_log_bucket should put and delete probe object."""
        from dags.dag_health_check import check_s3_log_bucket
        with patch.dict(os.environ, {
            "AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER": "s3://test-bucket/logs",
            "ALERT_SNS_TOPIC_ARN": "",
        }):
            check_s3_log_bucket()
        mock_boto3_s3.put_object.assert_called_once()
        mock_boto3_s3.delete_object.assert_called_once()


# ── ETL pipeline tests ─────────────────────────────────────────────────────────

class TestEtlPipeline:

    def test_extract_pushes_record_count(self, base_context, mock_boto3_s3):
        """extract() must push record_count to XCom."""
        from dags.dag_etl_pipeline import extract
        with patch.dict(os.environ, {"RESULTS_BUCKET": "test-bucket"}):
            extract(**base_context)
        base_context["task_instance"].xcom_push.assert_any_call(
            key="record_count", value=100
        )

    def test_extract_writes_to_s3(self, base_context, mock_boto3_s3):
        """extract() must write raw data to S3 with correct partition key."""
        from dags.dag_etl_pipeline import extract
        with patch.dict(os.environ, {"RESULTS_BUCKET": "test-bucket"}):
            extract(**base_context)
        put_calls = mock_boto3_s3.put_object.call_args_list
        assert any("raw/" in str(c) for c in put_calls), "No raw/ S3 write found"

    def test_validate_passes_with_records(self, base_context):
        """validate_extract() should return True when records > 0."""
        from dags.dag_etl_pipeline import validate_extract
        base_context["task_instance"].xcom_pull.side_effect = lambda task_ids, key: (
            100 if key == "record_count" else "2024/01/01/00"
        )
        result = validate_extract(**base_context)
        assert result is True

    def test_validate_short_circuits_on_empty(self, base_context):
        """validate_extract() should return False when no records extracted."""
        from dags.dag_etl_pipeline import validate_extract
        base_context["task_instance"].xcom_pull.side_effect = lambda task_ids, key: (
            0 if key == "record_count" else "2024/01/01/00"
        )
        result = validate_extract(**base_context)
        assert result is False

    def test_quality_check_passes_clean_data(self, base_context, mock_boto3_s3):
        """quality_check() should pass for well-formed records."""
        from dags.dag_etl_pipeline import quality_check
        with patch.dict(os.environ, {"RESULTS_BUCKET": "test-bucket"}):
            quality_check(**base_context)  # Should not raise

    def test_quality_check_fails_empty_value(self, base_context):
        """quality_check() should raise AirflowException for records with empty values."""
        from dags.dag_etl_pipeline import quality_check
        from airflow.exceptions import AirflowException
        bad_records = [{"id": 1, "value": "", "partition": "x", "transformed_at": "y"}]
        with patch("boto3.client") as mock_boto:
            mock_boto.return_value.get_object.return_value = {
                "Body": MagicMock(read=lambda: json.dumps(bad_records).encode())
            }
            with patch.dict(os.environ, {"RESULTS_BUCKET": "test-bucket"}):
                with pytest.raises(AirflowException, match="empty values"):
                    quality_check(**base_context)

    def test_quality_check_fails_missing_fields(self, base_context):
        """quality_check() should raise AirflowException for records missing required fields."""
        from dags.dag_etl_pipeline import quality_check
        from airflow.exceptions import AirflowException
        bad_records = [{"id": 1, "value": "ok"}]  # Missing partition, transformed_at
        with patch("boto3.client") as mock_boto:
            mock_boto.return_value.get_object.return_value = {
                "Body": MagicMock(read=lambda: json.dumps(bad_records).encode())
            }
            with patch.dict(os.environ, {"RESULTS_BUCKET": "test-bucket"}):
                with pytest.raises(AirflowException, match="missing required fields"):
                    quality_check(**base_context)

    def test_load_promotes_and_cleans_staged(self, base_context, mock_boto3_s3):
        """load() must copy staged → final and delete staged key."""
        from dags.dag_etl_pipeline import load
        with patch.dict(os.environ, {"RESULTS_BUCKET": "test-bucket"}):
            load(**base_context)
        mock_boto3_s3.copy_object.assert_called_once()
        mock_boto3_s3.delete_object.assert_called_once()
        # Verify final key path
        copy_args = mock_boto3_s3.copy_object.call_args
        assert "final/" in copy_args.kwargs.get("Key", copy_args[1].get("Key", ""))

    def test_on_failure_callback_sends_sns(self, mock_boto3_sns):
        """on_failure_callback must publish to SNS with correct subject."""
        from dags.dag_etl_pipeline import on_failure_callback
        context = {
            "dag": MagicMock(dag_id="etl_pipeline"),
            "task_instance": MagicMock(task_id="transform", log_url="http://airflow/log"),
            "execution_date": datetime(2024, 1, 1),
            "exception": "Something broke",
        }
        with patch.dict(os.environ, {"ALERT_SNS_TOPIC_ARN": "arn:aws:sns:us-east-1:123:test"}):
            on_failure_callback(context)
        mock_boto3_sns.publish.assert_called_once()
        call_kwargs = mock_boto3_sns.publish.call_args.kwargs
        assert "etl_pipeline" in call_kwargs["Subject"]
        assert "transform" in call_kwargs["Subject"]

    def test_on_failure_callback_silent_when_no_topic(self):
        """on_failure_callback should not raise if SNS topic not configured."""
        from dags.dag_etl_pipeline import on_failure_callback
        context = {
            "dag": MagicMock(dag_id="etl_pipeline"),
            "task_instance": MagicMock(task_id="transform", log_url="http://airflow/log"),
            "execution_date": datetime(2024, 1, 1),
            "exception": "Something broke",
        }
        with patch.dict(os.environ, {"ALERT_SNS_TOPIC_ARN": ""}):
            with patch("boto3.client") as mock_boto:
                on_failure_callback(context)
                mock_boto.assert_not_called()


# ── Idempotency tests ──────────────────────────────────────────────────────────

class TestIdempotency:

    def test_extract_partition_is_deterministic(self, base_context, mock_boto3_s3):
        """Running extract twice with same execution_date must produce same partition key."""
        from dags.dag_etl_pipeline import extract
        with patch.dict(os.environ, {"RESULTS_BUCKET": "test-bucket"}):
            extract(**base_context)
            extract(**base_context)

        put_calls = mock_boto3_s3.put_object.call_args_list
        keys = [c.kwargs.get("Key", "") for c in put_calls]
        assert keys[0] == keys[1], "Partition key is not deterministic"

    def test_load_is_idempotent(self, base_context, mock_boto3_s3):
        """Running load twice must not raise — S3 copy_object is idempotent."""
        from dags.dag_etl_pipeline import load
        with patch.dict(os.environ, {"RESULTS_BUCKET": "test-bucket"}):
            load(**base_context)
            load(**base_context)
        assert mock_boto3_s3.copy_object.call_count == 2