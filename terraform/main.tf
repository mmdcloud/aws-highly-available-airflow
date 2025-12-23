# -----------------------------------------------------------------------------------------
# Registering vault provider
# -----------------------------------------------------------------------------------------
data "vault_generic_secret" "rds" {
  path = "secret/rds"
}

data "vault_generic_secret" "redis" {
  path = "secret/redis"
}

data "aws_ssm_parameter" "fluentbit" {
  name = "/aws/service/aws-for-fluent-bit/stable"
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
  enable_dns_hostnames    = true
  enable_dns_support      = true
  create_igw              = true
  map_public_ip_on_launch = true
  enable_nat_gateway      = true
  single_nat_gateway      = true
  one_nat_gateway_per_az  = false
  tags = {
    Project = "ha-airflow"
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
    Name = "airflow-scheduler-sg"
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
    Name = "airflow-worker-sg"
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
    Name = "airflow-webserver-lb-sg"
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
    Name = "airflow-webserver-sg"
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
    Name = "airflow-rds-sg"
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
    Name = "airflow-redis-sg"
  }
}

module "airflow_efs_sg" {
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
      description = "Allow all outbound traffic"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
  tags = {
    Name = "airflow-efs-sg"
  }
}

# -----------------------------------------------------------------------------------------
# Secrets manager configuration
# -----------------------------------------------------------------------------------------
module "metadata_db_credentials" {
  source                  = "./modules/secrets-manager"
  name                    = "metadata-db-rds-secrets"
  description             = "Secret for storing Metadata DB credentials"
  recovery_window_in_days = 0
  secret_string = jsonencode({
    username = tostring(data.vault_generic_secret.rds.data["username"])
    password = tostring(data.vault_generic_secret.rds.data["password"])
  })
}

# -----------------------------------------------------------------------------------------
# S3 Configuration
# -----------------------------------------------------------------------------------------
module "airflow_dags_bucket" {
  source             = "./modules/s3"
  bucket_name        = "airflow-dags-bucket-${random_id.id.hex}"
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
}

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
  bucket_policy = ""
  force_destroy = true
  bucket_notification = {
    queue           = []
    lambda_function = []
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
  db_name                         = "airflow-metadata-db"
  allocated_storage               = 100
  max_allocated_storage           = 200
  storage_type                    = "gp3"
  engine                          = "postgres"
  engine_version                  = "15.4"
  instance_class                  = "db.r6g.large"
  multi_az                        = true
  storage_encrypted               = true
  username                        = tostring(data.vault_generic_secret.rds.data["username"])
  password                        = tostring(data.vault_generic_secret.rds.data["password"])
  subnet_group_name               = "airflow-metadata-db-subnet-group"
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  backup_retention_period         = 30
  backup_window                   = "03:00-06:00"
  maintenance_window              = "mon:04:00-mon:05:00"
  subnet_group_ids = [
    module.vpc.private_subnets[0],
    module.vpc.private_subnets[1],
    module.vpc.private_subnets[2]
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
  parameter_group_family                = "postgres15"
  parameters = [
    {
      name  = "max_connections"
      value = "500"
    },
    {
      name  = "shared_buffers"
      value = "{DBInstanceClassMemory/10240}"
    },
    {
      name  = "effective_cache_size"
      value = "{DBInstanceClassMemory/5120}"
    },
    {
      name  = "log_min_duration_statement"
      value = "1000"
    }
  ]
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
  num_cache_clusters         = 3
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
    module.vpc.private_subnets[0],
    module.vpc.private_subnets[1],
    module.vpc.private_subnets[2]
  ]
  description                = "Airflow Redis Cache Cluster"
  replication_group_id       = "airflow-redis"
  vpc_security_group_ids     = [module.airflow_redis_sg.id]
  maintenance_window         = "sun:05:00-sun:09:00"
  port                       = 6379
  automatic_failover_enabled = false
}

# -----------------------------------------------------------------------------------------
# EFS DAGs Configuration
# -----------------------------------------------------------------------------------------
module "airflow_efs" {
  source           = "./modules/efs"
  name             = "airflow-dags-efs"
  creation_token   = "airflow-dags-efs"
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  transition_to_ia = "AFTER_30_DAYS"
  subnet_ids = [
    module.vpc.private_subnets[0],
    module.vpc.private_subnets[1],
    module.vpc.private_subnets[2]
  ]
  security_group_ids   = [module.airflow_efs_sg.id]
  backup_policy_status = "ENABLED"
  access_point_name    = "airflow-efs-access-point"
  posix_uid            = 50000
  posix_gid            = 50000
  root_path            = "/airflow"
  root_permissions     = "755"
  tags = {
    Name        = "airflow-dags-efs"
    Environment = "prod"
    Project     = "airflow"
    ManagedBy   = "terraform"
  }
}

# resource "aws_efs_file_system" "airflow_dags" {
#   creation_token   = "airflow-dags-efs"
#   encrypted        = true
#   performance_mode = "generalPurpose"
#   throughput_mode  = "bursting"
#   lifecycle_policy {
#     transition_to_ia = "AFTER_30_DAYS"
#   }
#   tags = {
#     Name = "airflow-dags-efs"
#   }
# }

# EFS Mount Targets (one per AZ)
# resource "aws_efs_mount_target" "airflow_dags" {
#   count           = 3
#   file_system_id  = aws_efs_file_system.airflow_dags.id
#   subnet_id       = aws_subnet.private[count.index].id
#   security_groups = [aws_security_group.efs.id]
# }

# # EFS Backup Policy
# resource "aws_efs_backup_policy" "airflow_dags" {
#   file_system_id = aws_efs_file_system.airflow_dags.id
#   backup_policy {
#     status = "ENABLED"
#   }
# }

# # EFS Access Point for Airflow
# resource "aws_efs_access_point" "airflow" {
#   file_system_id = aws_efs_file_system.airflow_dags.id
#   posix_user {
#     gid = 50000
#     uid = 50000
#   }
#   root_directory {
#     path = "/airflow"
#     creation_info {
#       owner_gid   = 50000
#       owner_uid   = 50000
#       permissions = "755"
#     }
#   }
#   tags = {
#     Name = "airflow-efs-access-point"
#   }
# }

# -----------------------------------------------------------------------------------------
# Load Balancer Configuration
# -----------------------------------------------------------------------------------------
module "webserver_lb" {
  source             = "terraform-aws-modules/alb/aws"
  name               = "airflow-webserver-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups = [
    module.airflow_webserver_lb_sg.id
  ]
  subnets                          = module.vpc.public_subnets
  enable_deletion_protection       = false
  enable_http2                     = true
  enable_cross_zone_load_balancing = true
  drop_invalid_header_fields       = true
  ip_address_type                  = "ipv4"
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
      backend_port     = 3000
      target_type      = "ip"
      vpc_id           = module.vpc.vpc_id
      health_check = {
        enabled             = true
        healthy_threshold   = 3
        interval            = 30
        path                = "/"
        port                = 3000
        protocol            = "HTTP"
        unhealthy_threshold = 3
      }
      create_attachment = false
    }
  }
  tags = {
    Project = "ha-airflow"
  }
  depends_on = [module.vpc]
}

# -----------------------------------------------------------------------------------------
# ECS Configuration
# -----------------------------------------------------------------------------------------
module "ecs_task_execution_role" {
  source             = "../../../modules/iam"
  role_name          = "ecs-task-execution-role"
  role_description   = "IAM role for ECS task execution"
  policy_name        = "ecs-task-execution-policy"
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
                  "s3:PutObject"
                ],
                "Resource": "*",
                "Effect": "Allow"
            },
            {
              "Effect": "Allow",
              "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
              ],
              "Resource": "${module.metadata_db_credentials.arn}"
            }
        ]
    }
    EOF
}

# ECR-ECS policy attachment 
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy_attachment" {
  role       = module.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

module "ha_airflow_ecs_cluster" {
  source       = "terraform-aws-modules/ecs/aws"
  cluster_name = "ha-airflow-ecs-cluster"
  services = {
    webserver = {
      cpu                    = 2048
      memory                 = 4096
      task_exec_iam_role_arn = module.ecs_task_execution_role.arn
      iam_role_arn           = module.ecs_task_execution_role.arn
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
      container_definitions = {
        fluent-bit = {
          cpu       = 512
          memory    = 1024
          essential = true
          image     = nonsensitive(data.aws_ssm_parameter.fluentbit.value)
          user      = "0"
          firelensConfiguration = {
            type = "fluentbit"
          }
          memoryReservation                      = 50
          cloudwatch_log_group_retention_in_days = 30
        }
        webserver = {
          cpu       = 1024
          memory    = 2048
          essential = true
          image     = "apache/airflow:2.10.4"
          command   = ["webserver"]
          placementStrategy = [
            {
              type  = "spread",
              field = "attribute:ecs.availability-zone"
            }
          ]
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
          environment = [
            { name = "AIRFLOW__CORE__EXECUTOR", value = "CeleryExecutor" },
            { name = "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN", value = "postgresql+psycopg2://${tostring(data.vault_generic_secret.rds.data["username"])}:${tostring(data.vault_generic_secret.rds.data["password"])}@${module.airflow_metadata_db.endpoint}/airflow" },
            { name = "AIRFLOW__CELERY__BROKER_URL", value = "redis://:${tostring(data.vault_generic_secret.redis.data["auth_token"])}@${module.airflow_redis_cache.configuration_endpoint_address}:6379/0" },
            { name = "AIRFLOW__CELERY__RESULT_BACKEND", value = "db+postgresql://${tostring(data.vault_generic_secret.rds.data["username"])}:${tostring(data.vault_generic_secret.rds.data["password"])}@${module.airflow_metadata_db.endpoint}/airflow" },
            { name = "AIRFLOW__LOGGING__REMOTE_LOGGING", value = "True" },
            { name = "AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER", value = "s3://${module.airflow_logs_bucket.id}" },
            { name = "AIRFLOW__WEBSERVER__BASE_URL", value = "https://${var.domain_name}" },
            { name = "AIRFLOW__WEBSERVER__ENABLE_PROXY_FIX", value = "True" }
          ]
          readonlyRootFilesystem = false
          dependsOn = [{
            containerName = "fluent-bit"
            condition     = "START"
          }]
          # enable_cloudwatch_logging = false
          logConfiguration = {
            logDriver = "awsfirelens"
            options = {
              Name                    = "firehose"
              region                  = var.region
              delivery_stream         = "webserver-stream"
              log-driver-buffer-limit = "2097152"
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
          container_port   = 3000
        }
      }
      subnet_ids                    = module.vpc.private_subnets
      vpc_id                        = module.vpc.vpc_id
      security_group_ids            = [module.airflow_webserver_sg.id]
      availability_zone_rebalancing = "ENABLED"
    }

    scheduler = {
      cpu                    = 2048
      memory                 = 4096
      task_exec_iam_role_arn = module.ecs_task_execution_role.arn
      iam_role_arn           = module.ecs_task_execution_role.arn
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
      container_definitions = {
        fluent-bit = {
          cpu       = 512
          memory    = 1024
          essential = true
          image     = nonsensitive(data.aws_ssm_parameter.fluentbit.value)
          user      = "0"
          firelensConfiguration = {
            type = "fluentbit"
          }
          memoryReservation                      = 50
          cloudwatch_log_group_retention_in_days = 30
        }
        scheduler = {
          cpu       = 1024
          memory    = 2048
          essential = true
          image     = "apache/airflow:2.10.4"
          command   = ["scheduler"]
          placementStrategy = [
            {
              type  = "spread",
              field = "attribute:ecs.availability-zone"
            }
          ]
          healthCheck = {
            command = ["CMD-SHELL", "curl -f http://localhost:80 || exit 1"]
          }
          ulimits = [
            {
              name      = "nofile"
              softLimit = 65536
              hardLimit = 65536
            }
          ]
          environment = [
            { name = "AIRFLOW__CORE__EXECUTOR", value = "CeleryExecutor" },
            { name = "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN", value = "postgresql+psycopg2://${tostring(data.vault_generic_secret.rds.data["username"])}:${tostring(data.vault_generic_secret.rds.data["password"])}@${module.airflow_metadata_db.endpoint}/airflow" },
            { name = "AIRFLOW__CELERY__BROKER_URL", value = "redis://:${tostring(data.vault_generic_secret.redis.data["auth_token"])}@${module.airflow_redis_cache.configuration_endpoint_address}:6379/0" },
            { name = "AIRFLOW__CELERY__RESULT_BACKEND", value = "db+postgresql://${tostring(data.vault_generic_secret.rds.data["username"])}:${tostring(data.vault_generic_secret.rds.data["password"])}@${module.airflow_metadata_db.endpoint}/airflow" },
            { name = "AIRFLOW__LOGGING__REMOTE_LOGGING", value = "True" },
            { name = "AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER", value = "s3://${module.airflow_logs_bucket.id}" },
            { name = "AIRFLOW__SCHEDULER__SCHEDULER_HEALTH_CHECK_THRESHOLD", value = "30" }
          ]
          portMappings = [
            {
              name          = "scheduler"
              containerPort = 80
              hostPort      = 80
              protocol      = "tcp"
            }
          ]
          readOnlyRootFilesystem = false
          dependsOn = [{
            containerName = "fluent-bit"
            condition     = "START"
          }]
          logConfiguration = {
            logDriver = "awsfirelens"
            options = {
              Name                    = "firehose"
              region                  = var.region
              delivery_stream         = "scheduler-stream"
              log-driver-buffer-limit = "2097152"
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
      security_group_ids            = [module.airflow_scheduler_sg.id]
      availability_zone_rebalancing = "ENABLED"
    }

    worker = {
      cpu                    = 2048
      memory                 = 4096
      task_exec_iam_role_arn = module.ecs_task_execution_role.arn
      iam_role_arn           = module.ecs_task_execution_role.arn
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
      container_definitions = {
        fluent-bit = {
          cpu       = 512
          memory    = 1024
          essential = true
          image     = nonsensitive(data.aws_ssm_parameter.fluentbit.value)
          user      = "0"
          firelensConfiguration = {
            type = "fluentbit"
          }
          memoryReservation                      = 50
          cloudwatch_log_group_retention_in_days = 30
        }
        worker = {
          cpu       = 1024
          memory    = 2048
          essential = true
          image     = "apache/airflow:2.10.4"
          command   = ["celery", "worker"]
          placementStrategy = [
            {
              type  = "spread",
              field = "attribute:ecs.availability-zone"
            }
          ]
          healthCheck = {
            command = ["CMD-SHELL", "curl -f http://localhost:80 || exit 1"]
          }
          ulimits = [
            {
              name      = "nofile"
              softLimit = 65536
              hardLimit = 65536
            }
          ]
          environment = [
            { name = "AIRFLOW__CORE__EXECUTOR", value = "CeleryExecutor" },
            { name = "AIRFLOW__DATABASE__SQL_ALCHEMY_CONN", value = "postgresql+psycopg2://${tostring(data.vault_generic_secret.rds.data["username"])}:${tostring(data.vault_generic_secret.rds.data["password"])}@${module.airflow_metadata_db.endpoint}/airflow" },
            { name = "AIRFLOW__CELERY__BROKER_URL", value = "redis://:${tostring(data.vault_generic_secret.redis.data["auth_token"])}@${module.airflow_redis_cache.configuration_endpoint_address}:6379/0" },
            { name = "AIRFLOW__CELERY__RESULT_BACKEND", value = "db+postgresql://${tostring(data.vault_generic_secret.rds.data["username"])}:${tostring(data.vault_generic_secret.rds.data["password"])}@${module.airflow_metadata_db.endpoint}/airflow" },
            { name = "AIRFLOW__LOGGING__REMOTE_LOGGING", value = "True" },
            { name = "AIRFLOW__LOGGING__REMOTE_BASE_LOG_FOLDER", value = "s3://${module.airflow_logs_bucket.id}" },
            { name = "AIRFLOW__CELERY__WORKER_CONCURRENCY", value = "16" }
          ]
          portMappings = [
            {
              name          = "worker"
              containerPort = 80
              hostPort      = 80
              protocol      = "tcp"
            }
          ]
          readOnlyRootFilesystem = false
          dependsOn = [{
            containerName = "fluent-bit"
            condition     = "START"
          }]
          logConfiguration = {
            logDriver = "awsfirelens"
            options = {
              Name                    = "firehose"
              region                  = var.region
              delivery_stream         = "worker-stream"
              log-driver-buffer-limit = "2097152"
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
}

# -----------------------------------------------------------------------------------------
# Auto Scaling Configuration
# -----------------------------------------------------------------------------------------
resource "aws_appautoscaling_target" "worker" {
  max_capacity       = 20
  min_capacity       = 3
  resource_id        = "service/${module.ha_airflow_ecs_cluster.cluster_name}/${aws_ecs_service.worker.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "worker_scale_up" {
  name               = "worker-scale-up"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.worker.resource_id
  scalable_dimension = aws_appautoscaling_target.worker.scalable_dimension
  service_namespace  = aws_appautoscaling_target.worker.service_namespace
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
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
    ServiceName = aws_ecs_service.scheduler.name
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
    LoadBalancer = aws_lb.airflow.arn_suffix
    TargetGroup  = aws_lb_target_group.webserver.arn_suffix
  }
}