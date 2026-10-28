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

resource "aws_backup_vault" "efs" {
  name = "airflow-dags-efs-backup-vault"
  tags = {
    Name      = "airflow-dags-efs-backup-vault"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
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
  backup_vault_name         = aws_backup_vault.efs.name
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