"""
dag_etl_pipeline.py
-------------------
Production ETL pipeline DAG demonstrating best practices for this ECS/Fargate setup:
- Idempotent tasks using execution_date partitioning
- Dead letter handling via on_failure_callback → SNS
- S3-partitioned output compatible with remote logging config
- Celery worker task distribution
- Data quality gate before promotion
"""

from __future__ import annotations

import os
import json
import logging
from datetime import datetime, timedelta
from typing import Any

import boto3
from airflow import DAG
from airflow.operators.python import PythonOperator, ShortCircuitOperator
from airflow.operators.empty import EmptyOperator
from airflow.utils.dates import days_ago
from airflow.exceptions import AirflowException
from airflow.models import Variable

log = logging.getLogger(__name__)

AWS_REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
SNS_TOPIC_ARN = os.environ.get("ALERT_SNS_TOPIC_ARN", "")
RESULTS_BUCKET = os.environ.get("RESULTS_BUCKET", "")

# ── Callbacks ──────────────────────────────────────────────────────────────────

def on_failure_callback(context: dict) -> None:
    """Send SNS alert on task failure. Attached to all tasks via default_args."""
    dag_id = context["dag"].dag_id
    task_id = context["task_instance"].task_id
    execution_date = context["execution_date"]
    exception = context.get("exception", "Unknown error")
    log_url = context["task_instance"].log_url

    message = (
        f"DAG: {dag_id}\n"
        f"Task: {task_id}\n"
        f"Execution Date: {execution_date}\n"
        f"Error: {exception}\n"
        f"Logs: {log_url}"
    )
    if SNS_TOPIC_ARN:
        try:
            boto3.client("sns", region_name=AWS_REGION).publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject=f"[AIRFLOW FAILURE] {dag_id}.{task_id}",
                Message=message,
            )
        except Exception as e:
            log.error("Failed to send failure alert: %s", e)


default_args = {
    "owner": "data-engineering",
    "depends_on_past": False,
    "retries": 3,
    "retry_delay": timedelta(minutes=5),
    "retry_exponential_backoff": True,
    "max_retry_delay": timedelta(minutes=30),
    "execution_timeout": timedelta(hours=2),
    "email_on_failure": False,
    "email_on_retry": False,
    "on_failure_callback": on_failure_callback,
}

# ── Task functions ─────────────────────────────────────────────────────────────

def extract(**context) -> dict:
    """
    Extract source data.
    Partitioned by execution_date for idempotency.
    Pushes extracted record count to XCom for downstream quality gate.
    """
    execution_date = context["execution_date"]
    partition = execution_date.strftime("%Y/%m/%d/%H")
    log.info("Extracting data for partition: %s", partition)

    # --- Replace with actual extraction logic ---
    records = [
        {"id": i, "value": f"record_{i}", "partition": partition}
        for i in range(100)
    ]

    # Write raw extract to S3
    if RESULTS_BUCKET:
        s3 = boto3.client("s3", region_name=AWS_REGION)
        key = f"raw/{partition}/extract.json"
        s3.put_object(
            Bucket=RESULTS_BUCKET,
            Key=key,
            Body=json.dumps(records),
            ContentType="application/json",
        )
        log.info("Raw extract written to s3://%s/%s", RESULTS_BUCKET, key)

    context["task_instance"].xcom_push(key="record_count", value=len(records))
    context["task_instance"].xcom_push(key="partition", value=partition)
    return {"record_count": len(records), "partition": partition}


def validate_extract(**context) -> bool:
    """
    Data quality gate — short-circuits pipeline if extract is empty.
    Returns False to skip downstream tasks rather than failing.
    """
    ti = context["task_instance"]
    record_count = ti.xcom_pull(task_ids="extract", key="record_count")
    if record_count is None or record_count == 0:
        log.warning("Extract returned 0 records — short-circuiting pipeline")
        return False
    log.info("Validation passed: %d records extracted", record_count)
    return True


def transform(**context) -> None:
    """
    Transform raw records.
    Reads from S3 raw partition, applies transformations, writes to staged partition.
    """
    ti = context["task_instance"]
    partition = ti.xcom_pull(task_ids="extract", key="partition")

    log.info("Transforming data for partition: %s", partition)

    if RESULTS_BUCKET:
        s3 = boto3.client("s3", region_name=AWS_REGION)
        raw_key = f"raw/{partition}/extract.json"

        response = s3.get_object(Bucket=RESULTS_BUCKET, Key=raw_key)
        records = json.loads(response["Body"].read())

        # --- Replace with actual transformation logic ---
        transformed = [
            {**r, "value": r["value"].upper(), "transformed_at": datetime.utcnow().isoformat()}
            for r in records
        ]

        staged_key = f"staged/{partition}/transform.json"
        s3.put_object(
            Bucket=RESULTS_BUCKET,
            Key=staged_key,
            Body=json.dumps(transformed),
            ContentType="application/json",
        )
        log.info("Transformed data written to s3://%s/%s", RESULTS_BUCKET, staged_key)


def quality_check(**context) -> None:
    """
    Post-transform data quality checks.
    Raises AirflowException to trigger retry/alert if checks fail.
    """
    ti = context["task_instance"]
    partition = ti.xcom_pull(task_ids="extract", key="partition")

    if RESULTS_BUCKET:
        s3 = boto3.client("s3", region_name=AWS_REGION)
        staged_key = f"staged/{partition}/transform.json"
        response = s3.get_object(Bucket=RESULTS_BUCKET, Key=staged_key)
        records = json.loads(response["Body"].read())

        # Check 1: no empty values
        empty_values = [r for r in records if not r.get("value")]
        if empty_values:
            raise AirflowException(
                f"Quality check failed: {len(empty_values)} records have empty values"
            )

        # Check 2: all records have required fields
        required_fields = {"id", "value", "partition", "transformed_at"}
        missing = [r for r in records if not required_fields.issubset(r.keys())]
        if missing:
            raise AirflowException(
                f"Quality check failed: {len(missing)} records missing required fields"
            )

        log.info("Quality checks passed for %d records", len(records))


def load(**context) -> None:
    """
    Promote staged data to final partition after quality gate passes.
    Atomic: copy staged → final, then delete staged.
    """
    ti = context["task_instance"]
    partition = ti.xcom_pull(task_ids="extract", key="partition")

    if RESULTS_BUCKET:
        s3 = boto3.client("s3", region_name=AWS_REGION)
        staged_key = f"staged/{partition}/transform.json"
        final_key = f"final/{partition}/data.json"

        s3.copy_object(
            Bucket=RESULTS_BUCKET,
            CopySource={"Bucket": RESULTS_BUCKET, "Key": staged_key},
            Key=final_key,
        )
        s3.delete_object(Bucket=RESULTS_BUCKET, Key=staged_key)
        log.info("Data promoted to s3://%s/%s", RESULTS_BUCKET, final_key)


# ── DAG definition ─────────────────────────────────────────────────────────────

with DAG(
    dag_id="etl_pipeline",
    default_args=default_args,
    description="Production ETL pipeline with quality gates and failure alerting",
    schedule_interval="@hourly",
    start_date=days_ago(1),
    catchup=False,
    max_active_runs=3,
    tags=["etl", "production", "s3"],
    doc_md=__doc__,
) as dag:

    start = EmptyOperator(task_id="start")

    t_extract = PythonOperator(
        task_id="extract",
        python_callable=extract,
    )

    t_validate = ShortCircuitOperator(
        task_id="validate_extract",
        python_callable=validate_extract,
    )

    t_transform = PythonOperator(
        task_id="transform",
        python_callable=transform,
        queue="default",          # Explicit queue for Celery routing
        pool="default_pool",      # Rate-limit concurrent transforms
        pool_slots=1,
    )

    t_quality = PythonOperator(
        task_id="quality_check",
        python_callable=quality_check,
    )

    t_load = PythonOperator(
        task_id="load",
        python_callable=load,
    )

    end = EmptyOperator(
        task_id="end",
        trigger_rule="none_failed_min_one_success",  # Complete even if validate short-circuited
    )

    start >> t_extract >> t_validate >> t_transform >> t_quality >> t_load >> end