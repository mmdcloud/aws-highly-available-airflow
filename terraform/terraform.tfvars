# ==============================================================================
# Project & Environment
# ==============================================================================
project_name = "ha-airflow"
environment  = "prod"
region       = "us-east-1"

# ==============================================================================
# Networking
# ==============================================================================
vpc_cidr            = "10.0.0.0/16"
azs                 = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnets     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
database_subnets    = ["10.0.7.0/24", "10.0.8.0/24", "10.0.9.0/24"]
elasticache_subnets = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
single_nat_gateway  = false

# ==============================================================================
# Domain & Airflow Application
# ==============================================================================
domain_name         = "mohitcloud.xyz"
airflow_admin_email = "admin@example.com"
airflow_image       = "apache/airflow:2.10.4"
alarm_email         = "madmaxcloudonline@gmail.com"

# ==============================================================================
# ECS Sizing & Capacity (Fits within 8 vCPU standard account quota)
# ==============================================================================
webserver_cpu           = 1024
webserver_memory        = 2048
webserver_desired_count = 2

scheduler_cpu              = 1024
scheduler_memory           = 2048
scheduler_container_cpu    = 768
scheduler_container_memory = 1536
dag_sync_cpu               = 256
dag_sync_memory            = 512
scheduler_desired_count     = 1

worker_cpu           = 1024
worker_memory        = 2048
worker_desired_count = 2

# ==============================================================================
# Database & Cache
# ==============================================================================
db_instance_class          = "db.r6g.large"
db_allocated_storage       = 100
db_max_allocated_storage   = 200
redis_node_type            = "cache.t4g.micro"
redis_num_cache_clusters   = 2
