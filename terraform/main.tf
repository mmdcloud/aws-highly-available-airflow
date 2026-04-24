data "aws_caller_identity" "current" {}

resource "random_password" "airflow_secret_key" {
  length  = 32
  special = true
}

module "airflow_webserver_secret_key" {
  source                  = "./modules/secrets-manager"
  name                    = "airflow-webserver-secret-key-${random_id.id.hex}"
  description             = "Secret key for Airflow webserver session management"
  recovery_window_in_days = 7
  secret_string = jsonencode({
    secret_key = random_password.airflow_secret_key.result
  })
}

locals {
  rds_username       = nonsensitive(tostring(data.vault_generic_secret.rds.data["username"]))
  rds_password       = nonsensitive(tostring(data.vault_generic_secret.rds.data["password"]))
  redis_auth_token   = nonsensitive(tostring(data.vault_generic_secret.redis.data["auth_token"]))
  fernet_key         = nonsensitive(tostring(data.vault_generic_secret.airflow.data["fernet_key"]))
  airflow_secret_key = nonsensitive(random_password.airflow_secret_key.result)
  redis_endpoint     = module.airflow_redis_cache.primary_endpoint_address

  database_conn         = "postgresql+psycopg2://${local.rds_username}:${local.rds_password}@${module.airflow_metadata_db.endpoint}/airflow"
  celery_broker_url     = "rediss://:${local.redis_auth_token}@${local.redis_endpoint}:6379/0"
  celery_result_backend = "db+postgresql://${local.rds_username}:${local.rds_password}@${module.airflow_metadata_db.endpoint}/airflow"

  # Shared env vars every container needs — define once, reuse everywhere
  common_env = [
    { name = "AIRFLOW__CORE__EXECUTOR", value = "CeleryExecutor" },
    { name = "AIRFLOW__CORE__FERNET_KEY", value = local.fernet_key },
    { name = "AIRFLOW__CORE__LOAD_EXAMPLES", value = "False" },
    { name = "AIRFLOW__CORE__DAGS_FOLDER", value = "/opt/airflow/dags" },
    { name = "AIRFLOW__CORE__DONOT_MODIFY_HANDLERS", value = "True" },
    { name = "AIRFLOW_HOME", value = "/opt/airflow" },
    { name = "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN", value = local.database_conn },
    { name = "AIRFLOW__CELERY__BROKER_URL", value = local.celery_broker_url },
    { name = "AIRFLOW__CELERY__RESULT_BACKEND", value = local.celery_result_backend },
    { name = "AIRFLOW__LOGGING__REMOTE_LOGGING", value = "True" },
    { name = "AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER", value = "s3://${module.airflow_logs_bucket.bucket}" },
    { name = "AIRFLOW__LOGGING__BASE_LOG_FOLDER", value = "/opt/airflow/logs" },
    { name = "AIRFLOW__LOGGING__LOGGING_LEVEL", value = "INFO" },
    { name = "AIRFLOW__WEBSERVER__SECRET_KEY", value = local.airflow_secret_key },
  ]
}

# -----------------------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------------------
data "vault_generic_secret" "rds" {
  path = "secret/rds"
}

data "vault_generic_secret" "airflow" {
  path = "secret/airflow"
}

data "aws_elb_service_account" "main" {}

data "vault_generic_secret" "redis" {
  path = "secret/redis"
}

resource "random_id" "id" {
  byte_length = 8
}

# -----------------------------------------------------------------------------------------
# VPC Configuration
# -----------------------------------------------------------------------------------------
module "vpc" {
  source                  = "./modules/vpc"
  vpc_name                = "vpc"
  vpc_cidr                = "10.0.0.0/16"
  azs                     = var.azs
  public_subnets          = var.public_subnets
  private_subnets         = var.private_subnets
  database_subnets        = var.database_subnets
  elasticache_subnets     = var.elasticache_subnets
  enable_dns_hostnames    = true
  enable_dns_support      = true
  create_igw              = true
  map_public_ip_on_launch = true
  enable_nat_gateway      = true
  single_nat_gateway      = false
  one_nat_gateway_per_az  = true
  tags = {
    Name      = "vpc"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

# Security Group
module "airflow_scheduler_sg" {
  source = "./modules/security-groups"
  name   = "airflow-scheduler-sg"
  vpc_id = module.vpc.vpc_id
  egress_rules = [
    {
      description     = "Allow all outbound traffic"
      from_port       = 0
      to_port         = 0
      protocol        = "-1"
      security_groups = []
      cidr_blocks     = ["0.0.0.0/0"]
    }
  ]
  tags = {
    Name      = "airflow-scheduler-sg"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

module "airflow_worker_sg" {
  source = "./modules/security-groups"
  name   = "airflow-worker-sg"
  vpc_id = module.vpc.vpc_id
  egress_rules = [
    {
      description     = "Allow all outbound traffic"
      from_port       = 0
      to_port         = 0
      protocol        = "-1"
      security_groups = []
      cidr_blocks     = ["0.0.0.0/0"]
    }
  ]
  tags = {
    Name      = "airflow-worker-sg"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

module "airflow_webserver_lb_sg" {
  source = "./modules/security-groups"
  name   = "airflow-webserver-lb-sg"
  vpc_id = module.vpc.vpc_id
  ingress_rules = [
    {
      description     = "HTTP Traffic"
      from_port       = 80
      to_port         = 80
      protocol        = "tcp"
      security_groups = []
      cidr_blocks     = ["0.0.0.0/0"]
    },
    {
      description     = "HTTPS Traffic"
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      security_groups = []
      cidr_blocks     = ["0.0.0.0/0"]
    }
  ]
  egress_rules = [
    {
      description = "Allow all outbound traffic"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
  tags = {
    Name      = "airflow-webserver-lb-sg"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

module "airflow_webserver_sg" {
  source = "./modules/security-groups"
  name   = "airflow-webserver-sg"
  vpc_id = module.vpc.vpc_id
  ingress_rules = [
    {
      description     = "HTTP Traffic"
      from_port       = 8080
      to_port         = 8080
      protocol        = "tcp"
      security_groups = [module.airflow_webserver_lb_sg.id]
      cidr_blocks     = []
    }
  ]
  egress_rules = [
    {
      description = "Allow all outbound traffic"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
  tags = {
    Name      = "airflow-webserver-sg"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

module "airflow_rds_sg" {
  source = "./modules/security-groups"
  name   = "airflow-rds-sg"
  vpc_id = module.vpc.vpc_id
  ingress_rules = [
    {
      description = "PostgreSQL from Airflow components"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      security_groups = [
        module.airflow_webserver_sg.id,
        module.airflow_scheduler_sg.id,
        module.airflow_worker_sg.id
      ]
      cidr_blocks = []
    }
  ]
  egress_rules = []
  tags = {
    Name      = "airflow-rds-sg"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

module "airflow_redis_sg" {
  source = "./modules/security-groups"
  name   = "airflow-redis-sg"
  vpc_id = module.vpc.vpc_id
  ingress_rules = [
    {
      description = "Redis from Airflow components"
      from_port   = 6379
      to_port     = 6379
      protocol    = "tcp"
      security_groups = [
        module.airflow_webserver_sg.id,
        module.airflow_scheduler_sg.id,
        module.airflow_worker_sg.id
      ]
      cidr_blocks = []
    }
  ]
  egress_rules = []
  tags = {
    Name      = "airflow-redis-sg"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

module "efs_sg" {
  source = "./modules/security-groups"
  name   = "airflow-efs-sg"
  vpc_id = module.vpc.vpc_id
  ingress_rules = [
    {
      description = "NFS from Airflow components"
      from_port   = 2049
      to_port     = 2049
      protocol    = "tcp"
      security_groups = [
        module.airflow_webserver_sg.id,
        module.airflow_scheduler_sg.id,
        module.airflow_worker_sg.id
      ]
      cidr_blocks = []
    }
  ]
  egress_rules = [
    {
      description     = "Allow all outbound traffic"
      from_port       = 0
      to_port         = 0
      protocol        = "-1"
      security_groups = []
      cidr_blocks     = ["0.0.0.0/0"]
    }
  ]
  tags = {
    Name      = "airflow-efs-sg"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

# -----------------------------------------------------------------------------------------
# Secrets manager configuration
# -----------------------------------------------------------------------------------------
module "metadata_db_credentials" {
  source                  = "./modules/secrets-manager"
  name                    = "metadata-db-rds-secrets-${random_id.id.hex}"
  description             = "Secret for storing Metadata DB credentials"
  recovery_window_in_days = 7
  secret_string = jsonencode({
    username = tostring(data.vault_generic_secret.rds.data["username"])
    password = tostring(data.vault_generic_secret.rds.data["password"])
  })
  tags = {
    Name      = "metadata-db-rds-secrets-${random_id.id.hex}"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

# -----------------------------------------------------------------------------------------
# S3 Configuration
# -----------------------------------------------------------------------------------------
module "airflow_logs_bucket" {
  source             = "./modules/s3"
  bucket_name        = "airflow-logs-bucket-${random_id.id.hex}"
  objects            = []
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  bucket_policy = ""
  force_destroy = true
  bucket_notification = {
    queue           = []
    lambda_function = []
  }
  tags = {
    Name      = "airflow-logs-bucket-${random_id.id.hex}"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

module "airflow_dags_bucket" {
  source             = "./modules/s3"
  bucket_name        = "airflow-dags-bucket-${random_id.id.hex}"
  objects            = []
  versioning_enabled = "Enabled"
  cors               = []
  bucket_policy      = ""
  force_destroy      = true
  bucket_notification = {
    queue           = []
    lambda_function = []
  }
  tags = {
    Name      = "airflow-dags-bucket-${random_id.id.hex}"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

module "airflow_webserver_lb_logs" {
  source             = "./modules/s3"
  bucket_name        = "airflow-webserver-lb-logs-${random_id.id.hex}"
  objects            = []
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::airflow-webserver-lb-logs-${random_id.id.hex}/*"
      },
      {
        Sid    = "AWSLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = "arn:aws:s3:::airflow-webserver-lb-logs-${random_id.id.hex}"
      },
      {
        Sid    = "AWSELBAccountWrite"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_elb_service_account.main.id}:root"
        }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::airflow-webserver-lb-logs-${random_id.id.hex}/*"
      }
    ]
  })
  force_destroy = true
  bucket_notification = {
    queue           = []
    lambda_function = []
  }
  tags = {
    Name      = "airflow-webserver-lb-logs-${random_id.id.hex}"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

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

# -----------------------------------------------------------------------------------------
# EFS File System for DAGs
# -----------------------------------------------------------------------------------------
module "efs_backup_role" {
  source             = "./modules/iam"
  role_name          = "efs-backup-role"
  role_description   = "IAM role for EFS Backup"
  policy_name        = "efs_backup_role-policy"
  policy_description = "IAM policy for EFS Backup"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "backup.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
    EOF
  policy             = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": [
                  "elasticfilesystem:Backup",
                  "elasticfilesystem:DescribeTags"
                ],
                "Resource": "*",
                "Effect": "Allow"
            },
            {
              "Effect": "Allow",
              "Action": [
                "kms:Decrypt",
                "kms:DescribeKey",
                "kms:GenerateDataKey"
              ],
              "Resource": "*"
            },
            {
              "Effect": "Allow",
              "Action": [
                "tag:GetResources"
              ],
              "Resource": "*"
            }
        ]
    }
    EOF
  tags = {
    Name      = "efs-backup-role"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "efs_backup_policy" {
  role       = module.efs_backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# Attach AWS managed policy for restore operations
resource "aws_iam_role_policy_attachment" "efs_restore_policy" {
  role       = module.efs_backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

module "airflow_dags_efs" {
  source = "./modules/efs"

  name           = "airflow-dags-efs"
  creation_token = "airflow-dags-${random_id.id.hex}"

  # Network Configuration
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [module.efs_sg.id]
  backup_iam_role_arn = module.efs_backup_role.arn
  # Encryption (Production Best Practice)
  encrypted      = true
  create_kms_key = true

  # Performance Configuration
  # generalPurpose is suitable for most Airflow workloads
  # Use maxIO only if you have hundreds of concurrent connections
  performance_mode = "generalPurpose"

  # Elastic throughput automatically scales with workload
  # Recommended for variable workloads like Airflow
  throughput_mode = "elastic"

  # Lifecycle Management for Cost Optimization
  # Move infrequently accessed files to IA storage after 30 days
  lifecycle_policies = [
    # {
    #   transition_to_ia = "AFTER_30_DAYS"
    # }
  ]

  # Access Points for Different Airflow Components
  access_points = {
    dags = {
      root_directory_path = "/dags"
      creation_info = {
        owner_gid   = 50000 # airflow group
        owner_uid   = 50000 # airflow user
        permissions = "755"
      }
      posix_user = {
        gid = 50000
        uid = 50000
      }
      tags = {
        Component = "dags"
      }
    }
    plugins = {
      root_directory_path = "/plugins"
      creation_info = {
        owner_gid   = 50000
        owner_uid   = 50000
        permissions = "755"
      }
      posix_user = {
        gid = 50000
        uid = 50000
      }
      tags = {
        Component = "plugins"
      }
    }
    logs = {
      root_directory_path = "/logs"
      creation_info = {
        owner_gid   = 50000
        owner_uid   = 50000
        permissions = "750"
      }
      posix_user = {
        gid = 50000
        uid = 50000
      }
    }
  }

  # File System Policy - Enforce TLS and IAM 
  # file_system_policy = jsonencode({
  #   Version = "2012-10-17"
  #   Statement = [
  #     {
  #       Sid    = "EnforceTLS"
  #       Effect = "Deny"
  #       Principal = {
  #         AWS = "*"
  #       }
  #       Action   = "*"
  #       Resource = "*"
  #       Condition = {
  #         Bool = {
  #           "aws:SecureTransport" = "false"
  #         }
  #       }
  #     },
  #     {
  #       Sid    = "AllowRootAccessForTasks"
  #       Effect = "Allow"
  #       Principal = {
  #         AWS = [
  #           module.airflow_webserver_task_execution_role.arn,
  #           module.airflow_scheduler_task_execution_role.arn,
  #           module.airflow_worker_task_execution_role.arn
  #         ]
  #       }
  #       Action = [
  #         "elasticfilesystem:ClientMount",
  #         "elasticfilesystem:ClientWrite",
  #         "elasticfilesystem:ClientRootAccess"
  #       ]
  #       Resource = "*"
  #     }
  #   ]
  # })

  # Backup Configuration
  enable_backup_policy      = true
  create_custom_backup_plan = true
  backup_vault_name         = "Default"
  backup_schedule           = "cron(0 2 * * ? *)" # Daily at 2 AM UTC
  backup_retention_days     = 120
  backup_cold_storage_after = null

  # Weekly backups with longer retention
  enable_weekly_backup             = true
  weekly_backup_schedule           = "cron(0 3 ? * SUN *)"
  weekly_backup_retention_days     = 90
  weekly_backup_cold_storage_after = null

  # CloudWatch Alarms
  enable_cloudwatch_alarms       = true
  alarm_actions                  = [module.alarm_notifications.arn]
  burst_credit_balance_threshold = 1000000000000 # 1 TB
  percent_io_limit_threshold     = 80

  # Disaster Recovery (Optional - for production)
  # Uncomment if you need cross-region replication
  # enable_replication              = true
  # replication_destination_region  = "us-west-2"

  tags = {
    Name      = "airflow-dags-efs"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

# -----------------------------------------------------------------------------------------
# RDS Configuration ( Database for storing Metadata of Airflow )
# -----------------------------------------------------------------------------------------
resource "aws_iam_role" "rds_monitoring_role" {
  name = "airflow-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

module "airflow_metadata_db" {
  source                          = "./modules/rds"
  db_name                         = "airflow"
  allocated_storage               = 100
  max_allocated_storage           = 200
  storage_type                    = "gp3"
  engine                          = "postgres"
  engine_version                  = "17"
  instance_class                  = "db.r6g.large"
  multi_az                        = true
  storage_encrypted               = true
  username                        = tostring(data.vault_generic_secret.rds.data["username"])
  password                        = tostring(data.vault_generic_secret.rds.data["password"])
  subnet_group_name               = "airflow-metadata-db-subnet-group"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  backup_retention_period         = 30
  backup_window                   = "04:00-06:00"
  maintenance_window              = "Mon:00:00-Mon:03:00"
  subnet_group_ids = [
    module.vpc.database_subnets[0],
    module.vpc.database_subnets[1],
    module.vpc.database_subnets[2]
  ]
  vpc_security_group_ids                = [module.airflow_rds_sg.id]
  publicly_accessible                   = false
  deletion_protection                   = false
  skip_final_snapshot                   = true
  performance_insights_enabled          = true
  performance_insights_retention_period = 7
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.rds_monitoring_role.arn
  parameter_group_name                  = "airflow-metadata-db-pg"
  parameter_group_family                = "postgres17"
  parameters = [
    # {
    #   name  = "max_connections"
    #   value = "500"
    # },
    # {
    #   name  = "shared_buffers"
    #   value = "{DBInstanceClassMemory/10240}"
    # },
    # {
    #   name  = "effective_cache_size"
    #   value = "{DBInstanceClassMemory/5120}"
    # },
    # {
    #   name  = "log_min_duration_statement"
    #   value = "1000"
    # }
  ]
  tags = {
    Name      = "airflow"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

# -----------------------------------------------------------------------------------------
# Elasticache Configuration (Redis) - Celery Broker
# -----------------------------------------------------------------------------------------
module "redis_slow_log_group" {
  source            = "./modules/cloudwatch/cloudwatch-log-group"
  log_group_name    = "/aws/elasticache/airflow-redis/slow-log"
  retention_in_days = 7
}

module "airflow_redis_cache" {
  source                     = "./modules/elasticache"
  engine                     = "redis"
  engine_version             = "7.0"
  node_type                  = "cache.t4g.micro"
  num_cache_clusters         = 2
  parameter_group_name       = "default.redis7"
  subnet_group_name          = "airflow-redis-cache-subnet-group"
  multi_az_enabled           = true
  snapshot_retention_limit   = 7
  snapshot_window            = "03:00-05:00"
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token_enabled         = true
  auth_token                 = tostring(data.vault_generic_secret.redis.data["auth_token"])
  log_delivery_configuration = [
    {
      destination      = module.redis_slow_log_group.name
      destination_type = "cloudwatch-logs"
      log_format       = "json"
      log_type         = "slow-log"
    }
  ]
  subnet_group_ids = [
    module.vpc.elasticache_subnets[0],
    module.vpc.elasticache_subnets[1],
    module.vpc.elasticache_subnets[2]
  ]
  description                = "Airflow Redis Cache Cluster"
  replication_group_id       = "airflow-redis"
  vpc_security_group_ids     = [module.airflow_redis_sg.id]
  maintenance_window         = "sun:05:00-sun:09:00"
  port                       = 6379
  automatic_failover_enabled = true
  tags = {
    Name      = "airflow-redis"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

# -----------------------------------------------------------------------------------------
# Load Balancer Configuration
# -----------------------------------------------------------------------------------------
module "webserver_lb" {
  source                     = "terraform-aws-modules/alb/aws"
  name                       = "airflow-webserver-lb"
  load_balancer_type         = "application"
  vpc_id                     = module.vpc.vpc_id
  subnets                    = module.vpc.public_subnets
  enable_deletion_protection = false
  drop_invalid_header_fields = true
  ip_address_type            = "ipv4"
  internal                   = false
  security_groups = [
    module.airflow_webserver_lb_sg.id
  ]
  access_logs = {
    bucket = "${module.airflow_webserver_lb_logs.bucket}"
  }
  listeners = {
    webserver_lb_http_listener = {
      port     = 80
      protocol = "HTTP"
      forward = {
        target_group_key = "webserver_lb_target_group"
      }
    }
  }
  target_groups = {
    webserver_lb_target_group = {
      backend_protocol = "HTTP"
      backend_port     = 8080
      target_type      = "ip"
      vpc_id           = module.vpc.vpc_id
      stickiness = {
        enabled         = true
        type            = "lb_cookie"
        cookie_duration = 86400
      }
      health_check = {
        enabled             = true
        healthy_threshold   = 3
        interval            = 30
        path                = "/health"
        port                = 8080
        protocol            = "HTTP"
        unhealthy_threshold = 3
      }
      deregistration_delay   = 30
      connection_termination = false
      create_attachment      = false
    }
  }
  tags = {
    Name      = "airflow-webserver-lb"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
  depends_on = [
    module.vpc,
    module.airflow_webserver_lb_sg,
    module.airflow_webserver_lb_logs
  ]
}

# -----------------------------------------------------------------------------------------
# ECS Configuration
# -----------------------------------------------------------------------------------------
module "airflow_webserver_task_execution_role" {
  source             = "./modules/iam"
  role_name          = "airflow-webserver-task-execution-role"
  role_description   = "IAM role for ECS task execution"
  policy_name        = "airflow-webserver-task-execution-policy"
  policy_description = "IAM policy for ECS task execution"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "ecs-tasks.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
    EOF
  policy             = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": [
                  "s3:PutObject",
                  "s3:GetObject",
                  "s3:ListBucket"
                ],
                "Resource": [
                  "${module.airflow_logs_bucket.arn}/*",
                  "${module.airflow_logs_bucket.arn}"
                ],
                "Effect": "Allow"
            },
            {
              "Effect": "Allow",
              "Action": [
                "s3:GetObject",
                "s3:ListBucket"
              ],
              "Resource": [
                "${module.airflow_dags_bucket.arn}",
                "${module.airflow_dags_bucket.arn}/*"
              ]
            },
            {
              "Effect": "Allow",
              "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
              ],
              "Resource": "${module.metadata_db_credentials.arn}"
            },
            {
              "Effect": "Allow",
              "Action": [
                "elasticfilesystem:ClientMount",
                "elasticfilesystem:ClientWrite"
              ],
              "Resource": [
                "${module.airflow_dags_efs.arn}",
                "${module.airflow_dags_efs.access_point_arns["dags"]}",
                "${module.airflow_dags_efs.access_point_arns["plugins"]}",
                "${module.airflow_dags_efs.access_point_arns["logs"]}"
              ]
            }
        ]
    }
    EOF
  tags = {
    Name      = "airflow-webserver-task-execution-role"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

module "airflow_scheduler_task_execution_role" {
  source             = "./modules/iam"
  role_name          = "airflow-scheduler-task-execution-role"
  role_description   = "IAM role for ECS task execution"
  policy_name        = "airflow-scheduler-task-execution-policy"
  policy_description = "IAM policy for ECS task execution"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "ecs-tasks.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
    EOF
  policy             = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": [
                  "s3:PutObject",
                  "s3:GetObject",
                  "s3:ListBucket"
                ],
                "Resource": [
                  "${module.airflow_logs_bucket.arn}/*",
                  "${module.airflow_logs_bucket.arn}"
                ],
                "Effect": "Allow"
            },
            {
              "Effect": "Allow",
              "Action": [
                "s3:GetObject",
                "s3:ListBucket"
              ],
              "Resource": [
                "${module.airflow_dags_bucket.arn}",
                "${module.airflow_dags_bucket.arn}/*"
              ]
            },
            {
              "Effect": "Allow",
              "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
              ],
              "Resource": "${module.metadata_db_credentials.arn}"
            },
            {
              "Effect": "Allow",
              "Action": [
                "ssmmessages:CreateControlChannel",
                "ssmmessages:CreateDataChannel",
                "ssmmessages:OpenControlChannel",
                "ssmmessages:OpenDataChannel"
              ],
              "Resource": "*"
            },
            {
              "Effect": "Allow",
              "Action": [
                "elasticfilesystem:ClientMount",
                "elasticfilesystem:ClientWrite"
              ],
              "Resource": [
                "${module.airflow_dags_efs.arn}",
                "${module.airflow_dags_efs.access_point_arns["dags"]}",
                "${module.airflow_dags_efs.access_point_arns["plugins"]}",
                "${module.airflow_dags_efs.access_point_arns["logs"]}"
              ]
            }
        ]
    }
    EOF
  tags = {
    Name      = "airflow-scheduler-task-execution-role"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

module "airflow_worker_task_execution_role" {
  source             = "./modules/iam"
  role_name          = "airflow-worker-task-execution-role"
  role_description   = "IAM role for ECS task execution"
  policy_name        = "airflow-worker-task-execution-policy"
  policy_description = "IAM policy for ECS task execution"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "ecs-tasks.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
    EOF
  policy             = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": [
                  "s3:PutObject",
                  "s3:GetObject",
                  "s3:ListBucket"
                ],
                "Resource": [
                  "${module.airflow_logs_bucket.arn}/*",
                  "${module.airflow_logs_bucket.arn}"
                ],
                "Effect": "Allow"
            },
            {
              "Effect": "Allow",
              "Action": [
                "s3:GetObject",
                "s3:ListBucket"
              ],
              "Resource": [
                "${module.airflow_dags_bucket.arn}",
                "${module.airflow_dags_bucket.arn}/*"
              ]
            },
            {
              "Effect": "Allow",
              "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
              ],
              "Resource": "${module.metadata_db_credentials.arn}"
            },
            {
              "Effect": "Allow",
              "Action": [
                "elasticfilesystem:ClientMount",
                "elasticfilesystem:ClientWrite"
              ],
              "Resource": [
                "${module.airflow_dags_efs.arn}",
                "${module.airflow_dags_efs.access_point_arns["dags"]}",
                "${module.airflow_dags_efs.access_point_arns["plugins"]}",
                "${module.airflow_dags_efs.access_point_arns["logs"]}"
              ]
            }
        ]
    }
    EOF
  tags = {
    Name      = "airflow-worker-task-execution-role"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

# ECR-ECS policy attachment 
resource "aws_iam_role_policy_attachment" "airflow_webserver_task_execution_role_policy_attachment" {
  role       = module.airflow_webserver_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "airflow_scheduler_task_execution_role_policy_attachment" {
  role       = module.airflow_scheduler_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "airflow_worker_task_execution_role_policy_attachment" {
  role       = module.airflow_worker_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Cloudwatch Log Groups for ECS tasks
module "webserver_log_group" {
  source            = "./modules/cloudwatch/cloudwatch-log-group"
  log_group_name    = "/aws/ecs/airflow/webserver"
  retention_in_days = 7
}

module "scheduler_log_group" {
  source            = "./modules/cloudwatch/cloudwatch-log-group"
  log_group_name    = "/aws/ecs/airflow/scheduler"
  retention_in_days = 7
}

module "worker_log_group" {
  source            = "./modules/cloudwatch/cloudwatch-log-group"
  log_group_name    = "/aws/ecs/airflow/worker"
  retention_in_days = 7
}

# Add after your ECS cluster module
resource "aws_ecs_task_definition" "airflow_db_init" {
  family                   = "airflow-db-init"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = module.airflow_scheduler_task_execution_role.arn
  task_role_arn            = module.airflow_scheduler_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "db-init"
      image     = "apache/airflow:2.10.4"
      essential = true
      command   = ["db", "migrate"]
      linuxParameters = { # ← ADD HERE
        tmpfs = [
          { containerPath = "/tmp", size = 512 },
          { containerPath = "/opt/airflow", size = 256 }
        ]
      }
      # environment = [
      #   { name = "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN", value = local.database_conn }
      # ]
      environment = concat(local.common_env, [
        { name = "AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION", value = "True" }
      ])

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = module.scheduler_log_group.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "db-init"
        }
      }
    }
  ])
  tags = {
    Name      = "airflow-db-init"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

resource "aws_ecs_task_definition" "airflow_create_user" {
  family                   = "airflow-create-user"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = module.airflow_scheduler_task_execution_role.arn
  task_role_arn            = module.airflow_scheduler_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "create-user"
      image     = "apache/airflow:2.10.4"
      essential = true
      linuxParameters = { # ← ADD HERE
        tmpfs = [
          { containerPath = "/tmp", size = 512 },
          { containerPath = "/opt/airflow", size = 256 }
        ]
      }
      command = [
        "users", "create",
        "--username", "admin",
        "--firstname", "Admin",
        "--lastname", "User",
        "--role", "Admin",
        "--email", "admin@example.com",
        "--password", "admin123"
      ]

      # environment = [
      #   { name = "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN", value = local.database_conn }
      # ]
      environment = local.common_env

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = module.scheduler_log_group.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "create-user"
        }
      }
    }
  ])
  tags = {
    Name      = "airflow-create-user"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

module "ha_airflow_ecs_cluster" {
  source       = "terraform-aws-modules/ecs/aws"
  cluster_name = "ha-airflow-ecs-cluster"
  services = {
    webserver = {
      cpu                    = 2048
      memory                 = 4096
      task_exec_iam_role_arn = module.airflow_webserver_task_execution_role.arn
      iam_role_arn           = module.airflow_webserver_task_execution_role.arn
      desired_count          = 2
      launch_type            = "FARGATE"
      assign_public_ip       = false
      deployment_controller = {
        type = "ECS"
      }
      network_mode = "awsvpc"
      runtime_platform = {
        cpu_architecture        = "X86_64"
        operating_system_family = "LINUX"
      }
      scheduling_strategy      = "REPLICA"
      requires_compatibilities = ["FARGATE"]

      volume = {
        dags = {
          efs_volume_configuration = {
            file_system_id     = module.airflow_dags_efs.id
            transit_encryption = "ENABLED"
            authorization_config = {
              access_point_id = module.airflow_dags_efs.access_point_ids["dags"]
              iam             = "ENABLED"
            }
          }
        }
        plugins = {
          efs_volume_configuration = {
            file_system_id     = module.airflow_dags_efs.id
            transit_encryption = "ENABLED"
            authorization_config = {
              access_point_id = module.airflow_dags_efs.access_point_ids["plugins"]
              iam             = "ENABLED"
            }
          }
        }
        logs = {
          efs_volume_configuration = {
            file_system_id     = module.airflow_dags_efs.id
            transit_encryption = "ENABLED"
            authorization_config = {
              access_point_id = module.airflow_dags_efs.access_point_ids["logs"]
              iam             = "ENABLED"
            }
          }
        }
      }

      container_definitions = {
        webserver = {
          cpu       = 1024
          memory    = 2048
          essential = true
          image     = "apache/airflow:2.10.4"
          command   = ["webserver"]
          linuxParameters = { # ← ADD HERE
            tmpfs = [
              { containerPath = "/tmp", size = 512 },
              { containerPath = "/opt/airflow", size = 256 }
            ]
          }
          ulimits = [
            {
              name      = "nofile"
              softLimit = 65536
              hardLimit = 65536
            }
          ]
          portMappings = [
            {
              name          = "webserver"
              containerPort = 8080
              hostPort      = 8080
              protocol      = "tcp"
            }
          ]
          mountPoints = [
            {
              sourceVolume  = "dags"
              containerPath = "/opt/airflow/dags"
              readOnly      = false
            },
            {
              sourceVolume  = "plugins"
              containerPath = "/opt/airflow/plugins"
              readOnly      = false
            },
            {
              sourceVolume  = "logs"
              containerPath = "/opt/airflow/logs"
              readOnly      = false
            }
          ]
          environment = concat(local.common_env, [
            # Proxy / cookie config for ALB
            { name = "AIRFLOW__WEBSERVER__ENABLE_PROXY_FIX", value = "True" },
            { name = "AIRFLOW__WEBSERVER__SESSION_COOKIE_SECURE", value = "False" }, # set True when HTTPS
            { name = "AIRFLOW__WEBSERVER__SESSION_COOKIE_HTTPONLY", value = "True" },
            { name = "AIRFLOW__WEBSERVER__SESSION_COOKIE_SAMESITE", value = "Lax" },
            { name = "AIRFLOW__WEBSERVER__COOKIE_SECURE", value = "False" }, # set True when HTTPS
            { name = "AIRFLOW__WEBSERVER__COOKIE_SAMESITE", value = "Lax" },
            { name = "AIRFLOW__WEBSERVER__SESSION_BACKEND", value = "database" },

            # Worker / timeout settings
            { name = "AIRFLOW__WEBSERVER__WEB_SERVER_WORKER_TIMEOUT", value = "120" },
            { name = "AIRFLOW__WEBSERVER__WORKER_REFRESH_INTERVAL", value = "30" },
            { name = "AIRFLOW__WEBSERVER__WORKER_CLASS", value = "sync" },

            # Auth
            { name = "AIRFLOW__WEBSERVER__AUTHENTICATE", value = "True" },
            { name = "AIRFLOW__WEBSERVER__AUTH_BACKEND", value = "airflow.api.auth.backend.basic_auth" },
          ])
          readOnlyRootFilesystem    = false
          enable_cloudwatch_logging = true
          logConfiguration = {
            logDriver = "awslogs"
            options = {
              awslogs-group         = module.webserver_log_group.name
              awslogs-region        = var.region
              awslogs-stream-prefix = "webserver"
            }
          }
          memoryReservation = 100
          restartPolicy = {
            enabled              = true
            ignoredExitCodes     = [1]
            restartAttemptPeriod = 60
          }
        }
      }
      load_balancer = {
        service = {
          target_group_arn = module.webserver_lb.target_groups["webserver_lb_target_group"].arn
          container_name   = "webserver"
          container_port   = 8080
        }
      }
      subnet_ids                    = module.vpc.private_subnets
      vpc_id                        = module.vpc.vpc_id
      security_group_ids            = [module.airflow_webserver_sg.id]
      availability_zone_rebalancing = "ENABLED"
    }

    scheduler = {
      cpu                    = 4096
      memory                 = 8192
      task_exec_iam_role_arn = module.airflow_scheduler_task_execution_role.arn
      iam_role_arn           = module.airflow_scheduler_task_execution_role.arn
      desired_count          = 1 # IMPORTANT: Only run 1 scheduler at a time
      launch_type            = "FARGATE"
      assign_public_ip       = false
      enable_execute_command = true
      deployment_controller = {
        type = "ECS"
      }
      network_mode = "awsvpc"
      runtime_platform = {
        cpu_architecture        = "X86_64"
        operating_system_family = "LINUX"
      }
      scheduling_strategy      = "REPLICA"
      requires_compatibilities = ["FARGATE"]

      volume = {
        dags = {
          efs_volume_configuration = {
            file_system_id     = module.airflow_dags_efs.id
            transit_encryption = "ENABLED"
            authorization_config = {
              access_point_id = module.airflow_dags_efs.access_point_ids["dags"]
              iam             = "ENABLED"
            }
          }
        }
        plugins = {
          efs_volume_configuration = {
            file_system_id     = module.airflow_dags_efs.id
            transit_encryption = "ENABLED"
            authorization_config = {
              access_point_id = module.airflow_dags_efs.access_point_ids["plugins"]
              iam             = "ENABLED"
            }
          }
        }
        logs = {
          efs_volume_configuration = {
            file_system_id     = module.airflow_dags_efs.id
            transit_encryption = "ENABLED"
            authorization_config = {
              access_point_id = module.airflow_dags_efs.access_point_ids["logs"]
              iam             = "ENABLED"
            }
          }
        }
      }

      container_definitions = {
        scheduler = {
          cpu       = 2048
          memory    = 4096
          essential = true
          image     = "apache/airflow:2.10.4"
          command   = ["scheduler"]
          linuxParameters = { # ← ADD HERE
            tmpfs = [
              { containerPath = "/tmp", size = 512 },
              { containerPath = "/opt/airflow", size = 256 }
            ]
          }
          # Increase file descriptor limits
          ulimits = [
            {
              name      = "nofile"
              softLimit = 65536
              hardLimit = 65536
            }
          ]

          mountPoints = [
            {
              sourceVolume  = "dags"
              containerPath = "/opt/airflow/dags"
              readOnly      = false
            },
            {
              sourceVolume  = "plugins"
              containerPath = "/opt/airflow/plugins"
              readOnly      = false
            },
            {
              sourceVolume  = "logs"
              containerPath = "/opt/airflow/logs"
              readOnly      = false
            }
          ]

          environment = concat(local.common_env, [
            # Parallelism
            { name = "AIRFLOW__CORE__PARALLELISM", value = "32" },
            { name = "AIRFLOW__CORE__MAX_ACTIVE_TASKS_PER_DAG", value = "16" },
            { name = "AIRFLOW__CORE__MAX_ACTIVE_RUNS_PER_DAG", value = "16" },
            { name = "AIRFLOW__CORE__DAG_CONCURRENCY", value = "16" },
            { name = "AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION", value = "True" },

            # DB connection pool
            { name = "AIRFLOW__DATABASE__SQL_ALCHEMY_POOL_SIZE", value = "10" },
            { name = "AIRFLOW__DATABASE__SQL_ALCHEMY_MAX_OVERFLOW", value = "20" },
            { name = "AIRFLOW__DATABASE__SQL_ALCHEMY_POOL_RECYCLE", value = "3600" },
            { name = "AIRFLOW__DATABASE__SQL_ALCHEMY_POOL_PRE_PING", value = "True" },

            # Celery
            { name = "AIRFLOW__CELERY__WORKER_CONCURRENCY", value = "16" },

            # Scheduler tuning
            { name = "AIRFLOW__SCHEDULER__SCHEDULER_HEARTBEAT_SEC", value = "5" },
            { name = "AIRFLOW__SCHEDULER__SCHEDULER_HEALTH_CHECK_THRESHOLD", value = "30" },
            { name = "AIRFLOW__SCHEDULER__MIN_FILE_PROCESS_INTERVAL", value = "30" },
            { name = "AIRFLOW__SCHEDULER__DAG_DIR_LIST_INTERVAL", value = "30" },
            { name = "AIRFLOW__SCHEDULER__PARSING_PROCESSES", value = "2" },
            { name = "AIRFLOW__SCHEDULER__SCHEDULER_IDLE_SLEEP_TIME", value = "1" },
            { name = "AIRFLOW__SCHEDULER__MAX_TIS_PER_QUERY", value = "512" },
            { name = "AIRFLOW__SCHEDULER__USE_JOB_SCHEDULE", value = "True" },
            { name = "AIRFLOW__SCHEDULER__ALLOW_TRIGGER_IN_FUTURE", value = "False" },
            { name = "AIRFLOW__SCHEDULER__CATCHUP_BY_DEFAULT", value = "False" },
            { name = "AIRFLOW__SCHEDULER__ORPHANED_TASKS_CHECK_INTERVAL", value = "300" },
            { name = "AIRFLOW__SCHEDULER__ENABLE_HEALTH_CHECK", value = "True" },
            { name = "AIRFLOW__SCHEDULER__HEALTH_CHECK_THRESHOLD", value = "30" },
          ])

          readOnlyRootFilesystem = false

          # Health check for the container
          # healthCheck = {
          #   command = [
          #     "CMD-SHELL",
          #     "airflow jobs check --job-type SchedulerJob --hostname \"$HOSTNAME\" || exit 1"
          #   ]
          #   interval    = 30
          #   timeout     = 10
          #   retries     = 3
          #   startPeriod = 60
          # }

          logConfiguration = {
            logDriver = "awslogs"
            options = {
              awslogs-group         = module.scheduler_log_group.name
              awslogs-region        = var.region
              awslogs-stream-prefix = "scheduler"
            }
          }

          memoryReservation = 100

          # Restart policy - Important for scheduler
          restartPolicy = {
            enabled              = true
            ignoredExitCodes     = []  # Don't ignore any exit codes
            restartAttemptPeriod = 300 # Wait 5 minutes before restarting
          }
        },
        s3_dag_sync = {
          cpu       = 256
          memory    = 512
          essential = false
          image     = "public.ecr.aws/aws-cli/aws-cli:2.22.0"
          entryPoint = ["/bin/bash", "-c"]
          command = [
            "while true; do aws s3 sync s3://${module.airflow_dags_bucket.bucket}/dags/ /opt/airflow/dags/ --delete; sleep 30; done"
          ]
          mountPoints = [
            {
              sourceVolume  = "dags"
              containerPath = "/opt/airflow/dags"
              readOnly      = false
            }
          ]
          environment = [
            { name = "AWS_DEFAULT_REGION", value = var.region }
          ]          
        }
      }

      subnet_ids                    = module.vpc.private_subnets
      vpc_id                        = module.vpc.vpc_id
      security_group_ids            = [module.airflow_scheduler_sg.id]
      availability_zone_rebalancing = "DISABLED" # Keep scheduler in same AZ
    }

    worker = {
      cpu                    = 2048
      memory                 = 4096
      task_exec_iam_role_arn = module.airflow_worker_task_execution_role.arn
      iam_role_arn           = module.airflow_worker_task_execution_role.arn
      desired_count          = 2
      launch_type            = "FARGATE"
      assign_public_ip       = false
      deployment_controller = {
        type = "ECS"
      }
      network_mode = "awsvpc"
      runtime_platform = {
        cpu_architecture        = "X86_64"
        operating_system_family = "LINUX"
      }
      scheduling_strategy      = "REPLICA"
      requires_compatibilities = ["FARGATE"]

      volume = {
        dags = {
          efs_volume_configuration = {
            file_system_id     = module.airflow_dags_efs.id
            transit_encryption = "ENABLED"
            authorization_config = {
              access_point_id = module.airflow_dags_efs.access_point_ids["dags"]
              iam             = "ENABLED"
            }
          }
        }
        plugins = {
          efs_volume_configuration = {
            file_system_id     = module.airflow_dags_efs.id
            transit_encryption = "ENABLED"
            authorization_config = {
              access_point_id = module.airflow_dags_efs.access_point_ids["plugins"]
              iam             = "ENABLED"
            }
          }
        }
        logs = {
          efs_volume_configuration = {
            file_system_id     = module.airflow_dags_efs.id
            transit_encryption = "ENABLED"
            authorization_config = {
              access_point_id = module.airflow_dags_efs.access_point_ids["logs"]
              iam             = "ENABLED"
            }
          }
        }
      }

      container_definitions = {
        worker = {
          cpu       = 1024
          memory    = 2048
          essential = true
          image     = "apache/airflow:2.10.4"
          command   = ["celery", "worker"]
          linuxParameters = {
            tmpfs = [
              { containerPath = "/tmp", size = 512 },
              { containerPath = "/opt/airflow", size = 256 }
            ]
          }
          ulimits = [
            {
              name      = "nofile"
              softLimit = 65536
              hardLimit = 65536
            }
          ]
          mountPoints = [
            {
              sourceVolume  = "dags"
              containerPath = "/opt/airflow/dags"
              readOnly      = false
            },
            {
              sourceVolume  = "plugins"
              containerPath = "/opt/airflow/plugins"
              readOnly      = false
            },
            {
              sourceVolume  = "logs"
              containerPath = "/opt/airflow/logs"
              readOnly      = false
            }
          ]
          environment = concat(local.common_env, [
            { name = "AIRFLOW__CELERY__WORKER_CONCURRENCY", value = "16" },
          ])
          readOnlyRootFilesystem = false
          logConfiguration = {
            logDriver = "awslogs"
            options = {
              awslogs-group         = module.worker_log_group.name
              awslogs-region        = var.region
              awslogs-stream-prefix = "worker"
            }
          }
          memoryReservation = 100
          restartPolicy = {
            enabled              = true
            ignoredExitCodes     = [1]
            restartAttemptPeriod = 60
          }
        }        
      }
      subnet_ids                    = module.vpc.private_subnets
      vpc_id                        = module.vpc.vpc_id
      security_group_ids            = [module.airflow_worker_sg.id]
      availability_zone_rebalancing = "ENABLED"
    }
  }
  tags = {
    Name      = "ha-airflow-ecs-cluster"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
  depends_on = [
    module.airflow_redis_cache,
    module.webserver_lb,
    module.airflow_metadata_db
  ]
}

resource "null_resource" "airflow_db_init" {
  depends_on = [
    module.airflow_metadata_db,
    module.ha_airflow_ecs_cluster,
    aws_ecs_task_definition.airflow_db_init
  ]

  provisioner "local-exec" {
    command = <<-EOT
    TASK_ARN=$(aws ecs run-task \
      --cluster ${module.ha_airflow_ecs_cluster.cluster_name} \
      --task-definition ${aws_ecs_task_definition.airflow_db_init.family} \
      --launch-type FARGATE \
      --region ${var.region} \
      --network-configuration "awsvpcConfiguration={subnets=[${join(",", module.vpc.private_subnets)}],securityGroups=[${module.airflow_scheduler_sg.id}],assignPublicIp=DISABLED}" \
      --query 'tasks[0].taskArn' \
      --output text)

    echo "Waiting for db init task $TASK_ARN to complete..."
    aws ecs wait tasks-stopped \
      --cluster ${module.ha_airflow_ecs_cluster.cluster_name} \
      --tasks $TASK_ARN \
      --region ${var.region}

    EXIT_CODE=$(aws ecs describe-tasks \
      --cluster ${module.ha_airflow_ecs_cluster.cluster_name} \
      --tasks $TASK_ARN \
      --region ${var.region} \
      --query 'tasks[0].containers[0].exitCode' \
      --output text)

    if [ "$EXIT_CODE" != "0" ]; then
      echo "ERROR: db init failed with exit code $EXIT_CODE. Check CloudWatch logs."
      exit 1
    fi

    echo "DB init completed successfully."
  EOT
  }

  triggers = {
    db_endpoint = module.airflow_metadata_db.endpoint
  }
}

resource "null_resource" "airflow_create_user" {
  depends_on = [
    null_resource.airflow_db_init,
    aws_ecs_task_definition.airflow_create_user
  ]

  provisioner "local-exec" {
    command = <<-EOT
      aws ecs run-task \
        --cluster ${module.ha_airflow_ecs_cluster.cluster_name} \
        --task-definition ${aws_ecs_task_definition.airflow_create_user.family} \
        --launch-type FARGATE \
        --region ${var.region} \
        --network-configuration "awsvpcConfiguration={subnets=[${join(",", module.vpc.private_subnets)}],securityGroups=[${module.airflow_scheduler_sg.id}],assignPublicIp=DISABLED}" \
        --query 'tasks[0].taskArn' \
        --output text
    EOT
  }
}

# -----------------------------------------------------------------------------------------
# Auto Scaling Configuration
# -----------------------------------------------------------------------------------------
module "airflow_webserver_autoscaling_policy" {
  source             = "./modules/autoscaling"
  min_capacity       = 2
  max_capacity       = 10
  resource_id        = "service/${module.ha_airflow_ecs_cluster.cluster_name}/${module.ha_airflow_ecs_cluster.services["webserver"].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  policies = [
    {
      name        = "worker-scale-up"
      policy_type = "StepScaling"
      step_scaling_policy_configuration = {
        adjustment_type         = "ChangeInCapacity"
        cooldown                = 60
        metric_aggregation_type = "Average"
        step_adjustment = [
          {
            metric_interval_lower_bound = 0
            metric_interval_upper_bound = 20
            scaling_adjustment          = 1
          },
          {
            metric_interval_lower_bound = 20
            scaling_adjustment          = 2
          }
        ]
      }
    }
  ]
}

module "airflow_scheduler_autoscaling_policy" {
  source             = "./modules/autoscaling"
  min_capacity       = 2
  max_capacity       = 10
  resource_id        = "service/${module.ha_airflow_ecs_cluster.cluster_name}/${module.ha_airflow_ecs_cluster.services["scheduler"].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  policies = [
    {
      name        = "worker-scale-up"
      policy_type = "StepScaling"
      step_scaling_policy_configuration = {
        adjustment_type         = "ChangeInCapacity"
        cooldown                = 60
        metric_aggregation_type = "Average"
        step_adjustment = [
          {
            metric_interval_lower_bound = 0
            metric_interval_upper_bound = 20
            scaling_adjustment          = 1
          },
          {
            metric_interval_lower_bound = 20
            scaling_adjustment          = 2
          }
        ]
      }
    }
  ]
}

module "airflow_worker_autoscaling_policy" {
  source             = "./modules/autoscaling"
  min_capacity       = 2
  max_capacity       = 10
  resource_id        = "service/${module.ha_airflow_ecs_cluster.cluster_name}/${module.ha_airflow_ecs_cluster.services["worker"].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  policies = [
    {
      name        = "worker-scale-up"
      policy_type = "StepScaling"
      step_scaling_policy_configuration = {
        adjustment_type         = "ChangeInCapacity"
        cooldown                = 60
        metric_aggregation_type = "Average"
        step_adjustment = [
          {
            metric_interval_lower_bound = 0
            metric_interval_upper_bound = 20
            scaling_adjustment          = 1
          },
          {
            metric_interval_lower_bound = 20
            scaling_adjustment          = 2
          }
        ]
      }
    }
  ]
}

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

# -----------------------------------------------------------------------------------------
# WAF Configuration
# -----------------------------------------------------------------------------------------
module "waf" {
  source = "./modules/waf"

  # Naming — matches your existing convention
  name = "airflow-lb-webserver-waf"

  # Attach WAF to the public-facing Frontend ALB
  # Replace with your actual frontend ALB ARN output
  frontend_alb_arn = module.webserver_lb.arn

  # Reuse your existing SNS alarm topic — no new infra needed
  alarm_topic_arn = module.alarm_notifications.arn

  # Account + region for log resource policy
  account_id = data.aws_caller_identity.current.account_id
  aws_region = var.region

  # ---------------------------------------------------
  # IP Management
  # ---------------------------------------------------

  # IPs to always block — add known attackers, threat intel here
  blocked_ip_list = [
    # "203.0.113.0/24",  # Example: known scanner range
  ]

  # IPs that bypass rate limiting — office, CI/CD, trusted partners
  allowed_ip_list = [
    # "YOUR_OFFICE_IP/32",
    # "YOUR_CICD_RUNNER_IP/32",
  ]

  # ---------------------------------------------------
  # Geo Blocking
  # ---------------------------------------------------

  # Block countries not in your target market
  # Remove or leave empty [] if you serve global traffic
  blocked_countries = [
    # "KP",  # North Korea
    # "IR",  # Iran
    # "CU",  # Cuba
    # "SY",  # Syria
  ]

  # ---------------------------------------------------
  # Rate Limiting
  # ---------------------------------------------------

  # General rate limit per IP per 5-minute window
  # 2000 = ~6-7 requests/second — comfortable for real users, blocks bots
  rate_limit_requests = 2000

  # Auth endpoints get a much tighter limit
  # 100 = ~1 login attempt every 3 seconds per IP
  auth_rate_limit_requests = 100

  # ---------------------------------------------------
  # Logging
  # ---------------------------------------------------

  # How long to keep WAF logs in CloudWatch
  log_retention_days = 90

  # ---------------------------------------------------
  # Alarm Thresholds — tune after observing normal traffic
  # ---------------------------------------------------

  alarm_blocked_requests_threshold = 500 # > 500 total blocks in 5 min = alert
  alarm_rate_limit_threshold       = 100 # > 100 rate-limit hits in 5 min = alert
  alarm_auth_rate_limit_threshold  = 20  # > 20 auth blocks in 5 min = alert

  tags = {
    Name      = "airflow-lb-webserver-waf"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}