# ==============================================================================
# VPC & Network Outputs
# ==============================================================================
output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = var.vpc_cidr
}

output "public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "database_subnets" {
  description = "List of IDs of database subnets"
  value       = module.vpc.database_subnets
}

output "elasticache_subnets" {
  description = "List of IDs of ElastiCache subnets"
  value       = module.vpc.elasticache_subnets
}

# ==============================================================================
# Webserver & Load Balancer Outputs
# ==============================================================================
output "airflow_webserver_url" {
  description = "URL for accessing the Airflow webserver"
  value       = "http://${module.webserver_lb.dns_name}"
}

output "webserver_alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.webserver_lb.dns_name
}

output "webserver_alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.webserver_lb.arn
}

output "webserver_alb_zone_id" {
  description = "Canonical hosted zone ID of the load balancer (to be used in Route 53 alias record)"
  value       = module.webserver_lb.zone_id
}

# ==============================================================================
# Database & Cache Outputs
# ==============================================================================
output "rds_metadata_db_endpoint" {
  description = "Connection endpoint for the Airflow metadata PostgreSQL database"
  value       = module.airflow_metadata_db.endpoint
}

output "rds_metadata_db_id" {
  description = "ID of the RDS database instance"
  value       = module.airflow_metadata_db.id
}

output "redis_primary_endpoint" {
  description = "Address of the endpoint for the primary node in the Redis replication group"
  value       = module.airflow_redis_cache.primary_endpoint_address
}

output "redis_port" {
  description = "Port number on which the Redis cluster accepts connections"
  value       = 6379
}

# ==============================================================================
# Storage Outputs (EFS & S3)
# ==============================================================================
output "efs_dags_file_system_id" {
  description = "ID of the EFS file system used for DAGs, plugins, and logs"
  value       = module.airflow_dags_efs.id
}

output "efs_dags_file_system_arn" {
  description = "ARN of the EFS file system"
  value       = module.airflow_dags_efs.arn
}

output "s3_dags_bucket_name" {
  description = "Name of the S3 bucket used for DAG synchronization"
  value       = module.airflow_dags_bucket.bucket
}

output "s3_logs_bucket_name" {
  description = "Name of the S3 bucket used for remote Airflow task logs"
  value       = module.airflow_logs_bucket.bucket
}

# ==============================================================================
# ECS Cluster Outputs
# ==============================================================================
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ha_airflow_ecs_cluster.cluster_name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = module.ha_airflow_ecs_cluster.cluster_arn
}

# ==============================================================================
# Monitoring & Alerting Outputs
# ==============================================================================
output "alarm_sns_topic_arn" {
  description = "ARN of the SNS topic for CloudWatch alarms"
  value       = module.alarm_notifications.arn
}
