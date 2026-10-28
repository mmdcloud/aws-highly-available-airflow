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
              "Resource": [
                "${module.metadata_db_credentials.arn}",
                "${module.airflow_admin_credentials.arn}"
              ]
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
              "Resource": [
                "${module.metadata_db_credentials.arn}",
                "${module.airflow_admin_credentials.arn}"
              ]
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
      cpu                    = 1024
      memory                 = 2048
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
          cpu       = 768
          memory    = 1536
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