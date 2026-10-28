# -----------------------------------------------------------------------------------------
# Cloudwatch Alarm Configuration
# -----------------------------------------------------------------------------------------
module "rds_cpu" {
  source              = "./modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "airflow-rds-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "RDS CPU utilization is too high"
  alarm_actions       = [module.alarm_notifications.arn]
  dimensions = {
    DBInstanceIdentifier = module.airflow_metadata_db.id
  }
}

module "rds_connections" {
  source              = "./modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "airflow-rds-high-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "400"
  alarm_description   = "RDS connection count is too high"
  alarm_actions       = [module.alarm_notifications.arn]
  dimensions = {
    DBInstanceIdentifier = module.airflow_metadata_db.id
  }
}

module "redis_cpu" {
  source              = "./modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "airflow-redis-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = "75"
  alarm_description   = "Redis CPU utilization is too high"
  alarm_actions       = [module.alarm_notifications.arn]
  dimensions = {
    CacheClusterId = module.airflow_redis_cache.id
  }
}

module "scheduler_cpu" {
  source              = "./modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "airflow-scheduler-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Scheduler CPU utilization is too high"
  alarm_actions       = [module.alarm_notifications.arn]
  dimensions = {
    ClusterName = module.ha_airflow_ecs_cluster.cluster_name
    ServiceName = module.ha_airflow_ecs_cluster.services["scheduler"].name
  }
}

module "alb_unhealthy_targets" {
  source              = "./modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "airflow-alb-unhealthy-targets"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = "60"
  statistic           = "Average"
  threshold           = "0"
  alarm_description   = "Unhealthy targets detected in ALB"
  alarm_actions       = [module.alarm_notifications.arn]
  dimensions = {
    TargetGroup  = module.webserver_lb.target_groups["webserver_lb_target_group"].arn_suffix
    LoadBalancer = module.webserver_lb.arn_suffix
  }
}