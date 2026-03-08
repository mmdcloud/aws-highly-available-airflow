"""
dag_health_check.py
-------------------
Production health check DAG.
Runs every 5 minutes to verify Airflow infrastructure is healthy:
- Metadata DB connectivity
- Redis/Celery broker connectivity
- EFS DAGs folder accessibility
- S3 log bucket write access

Alerts via SNS if any check fails.
"""

from __future__ import annotations

import os
import logging
from datetime import datetime, timedelta

import boto3
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.utils.dates import days_ago
from airflow.exceptions import AirflowException

log = logging.getLogger(__name__)

AWS_REGION = os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
SNS_TOPIC_ARN = os.environ.get("ALERT_SNS_TOPIC_ARN", "")

default_args = {
    "owner": "platform",
    "depends_on_past": False,
    "retries": 0,
    "retry_delay": timedelta(minutes=1),
    "execution_timeout": timedelta(minutes=2),
    "email_on_failure": False,
    "email_on_retry": False,
}


def _send_alert(subject: str, message: str) -> None:
    if not SNS_TOPIC_ARN:
        log.warning("ALERT_SNS_TOPIC_ARN not set — skipping SNS alert")
        return
    try:
        sns = boto3.client("sns", region_name=AWS_REGION)
        sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject, Message=message)
        log.info("Alert sent: %s", subject)
    except Exception as e:
        log.error("Failed to send SNS alert: %s", e)


def check_metadata_db(**context) -> None:
    """Verify metadata DB is reachable and responsive."""
    from airflow.settings import Session
    try:
        session = Session()
        session.execute("SELECT 1")
        session.close()
        log.info("Metadata DB health check passed")
    except Exception as e:
        _send_alert(
            subject="[AIRFLOW ALERT] Metadata DB unreachable",
            message=f"Health check failed at {datetime.utcnow().isoformat()}\nError: {e}",
        )
        raise AirflowException(f"Metadata DB check failed: {e}") from e


def check_celery_broker(**context) -> None:
    """Verify Redis/Celery broker is reachable."""
    import redis
    broker_url = os.environ.get("AIRFLOW__CELERY__BROKER_URL", "")
    if not broker_url:
        raise AirflowException("AIRFLOW__CELERY__BROKER_URL not set")
    try:
        # rediss:// = TLS-enabled Redis
        r = redis.Redis.from_url(broker_url, socket_connect_timeout=5)
        r.ping()
        log.info("Celery broker health check passed")
    except Exception as e:
        _send_alert(
            subject="[AIRFLOW ALERT] Celery broker unreachable",
            message=f"Health check failed at {datetime.utcnow().isoformat()}\nError: {e}",
        )
        raise AirflowException(f"Celery broker check failed: {e}") from e


def check_efs_dags_folder(**context) -> None:
    """Verify EFS DAGs folder is mounted and writable."""
    dags_folder = os.environ.get("AIRFLOW__CORE__DAGS_FOLDER", "/opt/airflow/dags")
    probe_file = os.path.join(dags_folder, ".healthcheck")
    try:
        with open(probe_file, "w") as f:
            f.write(datetime.utcnow().isoformat())
        os.remove(probe_file)
        log.info("EFS DAGs folder health check passed: %s", dags_folder)
    except Exception as e:
        _send_alert(
            subject="[AIRFLOW ALERT] EFS DAGs folder not writable",
            message=f"Health check failed at {datetime.utcnow().isoformat()}\nPath: {dags_folder}\nError: {e}",
        )
        raise AirflowException(f"EFS DAGs folder check failed: {e}") from e


def check_s3_log_bucket(**context) -> None:
    """Verify S3 log bucket is accessible for writes."""
    log_folder = os.environ.get("AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER", "")
    if not log_folder or not log_folder.startswith("s3://"):
        log.warning("Remote logging not configured — skipping S3 check")
        return
    bucket = log_folder.replace("s3://", "").split("/")[0]
    try:
        s3 = boto3.client("s3", region_name=AWS_REGION)
        probe_key = "healthcheck/probe.txt"
        s3.put_object(Bucket=bucket, Key=probe_key, Body=datetime.utcnow().isoformat())
        s3.delete_object(Bucket=bucket, Key=probe_key)
        log.info("S3 log bucket health check passed: %s", bucket)
    except Exception as e:
        _send_alert(
            subject="[AIRFLOW ALERT] S3 log bucket not accessible",
            message=f"Health check failed at {datetime.utcnow().isoformat()}\nBucket: {bucket}\nError: {e}",
        )
        raise AirflowException(f"S3 log bucket check failed: {e}") from e


with DAG(
    dag_id="platform_health_check",
    default_args=default_args,
    description="Infrastructure health checks for HA Airflow on ECS",
    schedule_interval="*/5 * * * *",
    start_date=days_ago(1),
    catchup=False,
    max_active_runs=1,
    tags=["platform", "health", "monitoring"],
    doc_md=__doc__,
) as dag:

    t_db = PythonOperator(
        task_id="check_metadata_db",
        python_callable=check_metadata_db,
    )

    t_broker = PythonOperator(
        task_id="check_celery_broker",
        python_callable=check_celery_broker,
    )

    t_efs = PythonOperator(
        task_id="check_efs_dags_folder",
        python_callable=check_efs_dags_folder,
    )

    t_s3 = PythonOperator(
        task_id="check_s3_log_bucket",
        python_callable=check_s3_log_bucket,
    )

    # All checks run in parallel
    [t_db, t_broker, t_efs, t_s3]