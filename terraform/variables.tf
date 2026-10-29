# ==============================================================================
# General Project & Environment Settings
# ==============================================================================
variable "project_name" {
  description = "Name of the project used for resource naming and tagging"
  type        = string
  default     = "ha-airflow"
}

variable "environment" {
  description = "Deployment environment (e.g. prod, staging, dev)"
  type        = string
  default     = "prod"
}

variable "region" {
  description = "AWS Region to deploy resources into"
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ==============================================================================
# Network Configuration
# ==============================================================================
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "List of Availability Zones to deploy subnets into"
  type        = list(string)
}

variable "public_subnets" {
  description = "List of CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnets" {
  description = "List of CIDR blocks for private subnets (used by ECS and EFS)"
  type        = list(string)
}

variable "database_subnets" {
  description = "List of CIDR blocks for database subnets (used by RDS)"
  type        = list(string)
}

variable "elasticache_subnets" {
  description = "List of CIDR blocks for ElastiCache subnets (used by Redis)"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Whether to use a single NAT Gateway (cost saving for dev/test) or multi-AZ NAT Gateways (HA for prod)"
  type        = bool
  default     = false
}

# ==============================================================================
# Domain & Load Balancer Configuration
# ==============================================================================
variable "domain_name" {
  description = "Domain name for the Airflow webserver"
  type        = string
}

variable "certificate_arn" {
  description = "ACM Certificate ARN for HTTPS listener on ALB (optional, if omitted HTTP only is used)"
  type        = string
  default     = null
}

variable "alb_deletion_protection" {
  description = "Enable deletion protection on Application Load Balancer"
  type        = bool
  default     = false
}

# ==============================================================================
# Airflow Application Configuration
# ==============================================================================
variable "airflow_image" {
  description = "Docker image for Apache Airflow"
  type        = string
  default     = "apache/airflow:2.10.4"
}

variable "airflow_admin_email" {
  description = "Email address for the Airflow admin user"
  type        = string
  default     = "admin@example.com"
}

variable "dag_sync_image" {
  description = "Docker image for the S3 DAG sync sidecar container"
  type        = string
  default     = "public.ecr.aws/aws-cli/aws-cli:2.22.0"
}

variable "dag_sync_interval" {
  description = "Interval in seconds between S3 DAG sync runs"
  type        = number
  default     = 30
}

# ==============================================================================
# Vault Secrets Paths
# ==============================================================================
variable "vault_secret_path_rds" {
  description = "Vault path for RDS metadata database credentials"
  type        = string
  default     = "secret/rds"
}

variable "vault_secret_path_airflow" {
  description = "Vault path for Airflow secrets (Fernet key, admin password)"
  type        = string
  default     = "secret/airflow"
}

variable "vault_secret_path_redis" {
  description = "Vault path for Redis authentication token"
  type        = string
  default     = "secret/redis"
}

# ==============================================================================
# Database Configuration (RDS PostgreSQL)
# ==============================================================================
variable "db_name" {
  description = "Database name for the Airflow metadata database"
  type        = string
  default     = "airflow"
}

variable "db_instance_class" {
  description = "RDS instance class for Airflow metadata database"
  type        = string
  default     = "db.r6g.large"
}

variable "db_allocated_storage" {
  description = "Initial allocated storage in GiB for RDS PostgreSQL"
  type        = number
  default     = 100
}

variable "db_max_allocated_storage" {
  description = "Maximum storage limit in GiB for RDS autoscaling"
  type        = number
  default     = 200
}

variable "db_storage_type" {
  description = "Storage type for RDS PostgreSQL"
  type        = string
  default     = "gp3"
}

variable "db_engine_version" {
  description = "PostgreSQL engine version for RDS"
  type        = string
  default     = "17"
}

variable "db_parameter_group_family" {
  description = "Parameter group family for RDS PostgreSQL"
  type        = string
  default     = "postgres17"
}

variable "db_multi_az" {
  description = "Specifies if the RDS database instance is multi-AZ"
  type        = bool
  default     = true
}

variable "db_backup_retention_period" {
  description = "Backup retention period in days for RDS"
  type        = number
  default     = 30
}

variable "db_backup_window" {
  description = "Daily time range during which automated backups are created"
  type        = string
  default     = "04:00-06:00"
}

variable "db_maintenance_window" {
  description = "Weekly time range during which system maintenance can occur"
  type        = string
  default     = "Mon:00:00-Mon:03:00"
}

variable "db_deletion_protection" {
  description = "Enable deletion protection on RDS instance"
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Skip final snapshot before deleting RDS instance"
  type        = bool
  default     = true
}

# ==============================================================================
# ElastiCache Configuration (Redis Celery Broker)
# ==============================================================================
variable "redis_node_type" {
  description = "ElastiCache node type for Redis Celery broker"
  type        = string
  default     = "cache.t4g.micro"
}

variable "redis_num_cache_clusters" {
  description = "Number of cache clusters (nodes) for the Redis replication group"
  type        = number
  default     = 2
}

variable "redis_engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.0"
}

variable "redis_parameter_group_name" {
  description = "Parameter group name for Redis"
  type        = string
  default     = "default.redis7"
}

variable "redis_multi_az_enabled" {
  description = "Enable Multi-AZ failover for Redis replication group"
  type        = bool
  default     = true
}

variable "redis_automatic_failover_enabled" {
  description = "Enable automatic failover for Redis replication group"
  type        = bool
  default     = true
}

variable "redis_snapshot_retention_limit" {
  description = "Number of days for which ElastiCache retains automatic snapshots"
  type        = number
  default     = 7
}

# ==============================================================================
# EFS File System Configuration (DAGs & Plugins Storage)
# ==============================================================================
variable "efs_performance_mode" {
  description = "The performance mode of the EFS file system (generalPurpose or maxIO)"
  type        = string
  default     = "generalPurpose"
}

variable "efs_throughput_mode" {
  description = "Throughput mode for the EFS file system (elastic, bursting, or provisioned)"
  type        = string
  default     = "elastic"
}

variable "efs_backup_retention_days" {
  description = "Number of days to retain daily EFS backups"
  type        = number
  default     = 120
}

variable "efs_enable_weekly_backup" {
  description = "Enable weekly EFS backup rule with longer retention"
  type        = bool
  default     = true
}

variable "efs_weekly_backup_retention_days" {
  description = "Number of days to retain weekly EFS backups"
  type        = number
  default     = 90
}

# ==============================================================================
# S3 Storage Configuration
# ==============================================================================
variable "s3_force_destroy" {
  description = "Allow deletion of S3 bucket even if it contains objects"
  type        = bool
  default     = true
}

# ==============================================================================
# ECS Compute & Sizing Configuration
# ==============================================================================
variable "webserver_cpu" {
  description = "CPU units for the Airflow webserver task (1024 = 1 vCPU)"
  type        = number
  default     = 1024
}

variable "webserver_memory" {
  description = "Memory in MiB for the Airflow webserver task"
  type        = number
  default     = 2048
}

variable "webserver_desired_count" {
  description = "Desired number of Airflow webserver tasks"
  type        = number
  default     = 2
}

variable "webserver_min_capacity" {
  description = "Minimum capacity for webserver autoscaling"
  type        = number
  default     = 2
}

variable "webserver_max_capacity" {
  description = "Maximum capacity for webserver autoscaling"
  type        = number
  default     = 10
}

variable "scheduler_cpu" {
  description = "Total CPU units for the Airflow scheduler task (1024 = 1 vCPU)"
  type        = number
  default     = 1024
}

variable "scheduler_memory" {
  description = "Total memory in MiB for the Airflow scheduler task"
  type        = number
  default     = 2048
}

variable "scheduler_container_cpu" {
  description = "CPU units allocated specifically to the scheduler container"
  type        = number
  default     = 768
}

variable "scheduler_container_memory" {
  description = "Memory in MiB allocated specifically to the scheduler container"
  type        = number
  default     = 1536
}

variable "dag_sync_cpu" {
  description = "CPU units allocated to the S3 DAG sync sidecar container"
  type        = number
  default     = 256
}

variable "dag_sync_memory" {
  description = "Memory in MiB allocated to the S3 DAG sync sidecar container"
  type        = number
  default     = 512
}

variable "scheduler_desired_count" {
  description = "Desired number of Airflow scheduler tasks (typically 1 for CeleryExecutor)"
  type        = number
  default     = 1
}

variable "worker_cpu" {
  description = "CPU units for each Airflow worker task (1024 = 1 vCPU)"
  type        = number
  default     = 1024
}

variable "worker_memory" {
  description = "Memory in MiB for each Airflow worker task"
  type        = number
  default     = 2048
}

variable "worker_desired_count" {
  description = "Desired number of Airflow worker tasks"
  type        = number
  default     = 2
}

variable "worker_min_capacity" {
  description = "Minimum capacity for worker autoscaling"
  type        = number
  default     = 2
}

variable "worker_max_capacity" {
  description = "Maximum capacity for worker autoscaling"
  type        = number
  default     = 10
}

variable "worker_concurrency" {
  description = "Celery worker concurrency (number of tasks a worker process can run concurrently)"
  type        = number
  default     = 16
}

# ==============================================================================
# Monitoring & Logging Configuration
# ==============================================================================
variable "alarm_email" {
  description = "Email address for SNS CloudWatch alarm notifications"
  type        = string
  default     = "madmaxcloudonline@gmail.com"
}

variable "log_retention_in_days" {
  description = "Retention period in days for CloudWatch log groups"
  type        = number
  default     = 7
}

variable "rds_cpu_threshold" {
  description = "CPU utilization threshold percentage for RDS alarm"
  type        = string
  default     = "80"
}

variable "rds_connections_threshold" {
  description = "Connection count threshold for RDS alarm"
  type        = string
  default     = "400"
}

variable "redis_cpu_threshold" {
  description = "CPU utilization threshold percentage for Redis alarm"
  type        = string
  default     = "75"
}

variable "scheduler_cpu_threshold" {
  description = "CPU utilization threshold percentage for Scheduler alarm"
  type        = string
  default     = "80"
}
