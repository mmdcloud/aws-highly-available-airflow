# -----------------------------------------------------------------------------------------
# SNS Configuration
# -----------------------------------------------------------------------------------------
module "alarm_notifications" {
  source     = "./modules/sns"
  topic_name = "ha-airflow-cloudwatch-alarm-notification-topic"
  subscriptions = [
    {
      protocol = "email"
      endpoint = "madmaxcloudonline@gmail.com"
    }
  ]
  tags = {
    Name      = "ha-airflow-cloudwatch-alarm-notification-topic"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}