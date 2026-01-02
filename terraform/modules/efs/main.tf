# -----------------------------------------------------------------------------------------
# KMS Key for EFS Encryption
# -----------------------------------------------------------------------------------------
resource "aws_kms_key" "efs" {
  count                   = var.create_kms_key ? 1 : 0
  description             = "KMS key for EFS encryption - ${var.name}"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true
  
  tags = merge(
    var.tags,
    {
      Name = "${var.name}-efs-kms-key"
    }
  )
}

resource "aws_kms_alias" "efs" {
  count         = var.create_kms_key ? 1 : 0
  name          = "alias/${var.name}-efs"
  target_key_id = aws_kms_key.efs[0].key_id
}

# -----------------------------------------------------------------------------------------
# EFS File System
# -----------------------------------------------------------------------------------------
resource "aws_efs_file_system" "this" {
  creation_token = var.creation_token != "" ? var.creation_token : var.name
  encrypted      = var.encrypted
  kms_key_id     = var.encrypted && var.create_kms_key ? aws_kms_key.efs[0].arn : var.kms_key_id

  # Performance settings
  performance_mode                = var.performance_mode
  throughput_mode                 = var.throughput_mode
  provisioned_throughput_in_mibps = var.throughput_mode == "provisioned" ? var.provisioned_throughput_in_mibps : null

  # Lifecycle management for cost optimization
  dynamic "lifecycle_policy" {
    for_each = var.lifecycle_policies
    content {
      transition_to_ia                    = lookup(lifecycle_policy.value, "transition_to_ia", null)
      transition_to_primary_storage_class = lookup(lifecycle_policy.value, "transition_to_primary_storage_class", null)
      transition_to_archive               = lookup(lifecycle_policy.value, "transition_to_archive", null)
    }
  }

  # Protection settings
  dynamic "protection" {
    for_each = var.enable_protection ? [1] : []
    content {
      replication_overwrite = var.replication_overwrite_protection
    }
  }

  tags = merge(
    var.tags,
    {
      Name = var.name
    }
  )
}

# -----------------------------------------------------------------------------------------
# EFS Mount Targets (Multi-AZ)
# -----------------------------------------------------------------------------------------
resource "aws_efs_mount_target" "this" {
  count           = length(var.subnet_ids)
  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = var.security_group_ids

  # IP address can be specified for deterministic mounting
  ip_address = length(var.mount_target_ip_addresses) > 0 ? var.mount_target_ip_addresses[count.index] : null
}

# -----------------------------------------------------------------------------------------
# EFS Access Points (for Application-Specific Access)
# -----------------------------------------------------------------------------------------
resource "aws_efs_access_point" "this" {
  for_each = var.access_points

  file_system_id = aws_efs_file_system.this.id

  # Root directory configuration
  root_directory {
    path = lookup(each.value, "root_directory_path", "/")
    
    dynamic "creation_info" {
      for_each = lookup(each.value, "creation_info", null) != null ? [each.value.creation_info] : []
      content {
        owner_gid   = creation_info.value.owner_gid
        owner_uid   = creation_info.value.owner_uid
        permissions = creation_info.value.permissions
      }
    }
  }

  # POSIX user identity
  dynamic "posix_user" {
    for_each = lookup(each.value, "posix_user", null) != null ? [each.value.posix_user] : []
    content {
      gid            = posix_user.value.gid
      uid            = posix_user.value.uid
      secondary_gids = lookup(posix_user.value, "secondary_gids", null)
    }
  }

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = "${var.name}-${each.key}"
    }
  )
}

# -----------------------------------------------------------------------------------------
# EFS File System Policy (IAM-based access control)
# -----------------------------------------------------------------------------------------
resource "aws_efs_file_system_policy" "this" {
  count = var.file_system_policy != null ? 1 : 0

  file_system_id                     = aws_efs_file_system.this.id
  bypass_policy_lockout_safety_check = var.bypass_policy_lockout_safety_check
  policy                             = var.file_system_policy
}

# -----------------------------------------------------------------------------------------
# AWS Backup Configuration for EFS
# -----------------------------------------------------------------------------------------
resource "aws_efs_backup_policy" "this" {
  count          = var.enable_backup_policy ? 1 : 0
  file_system_id = aws_efs_file_system.this.id

  backup_policy {
    status = "ENABLED"
  }
}

# Custom AWS Backup Plan for Production
resource "aws_backup_plan" "efs" {
  count = var.create_custom_backup_plan ? 1 : 0
  name  = "${var.name}-efs-backup-plan"

  # Daily backups with lifecycle management
  rule {
    rule_name         = "daily_backup"
    target_vault_name = var.backup_vault_name
    schedule          = var.backup_schedule

    lifecycle {
      cold_storage_after = var.backup_cold_storage_after
      delete_after       = var.backup_retention_days
    }

    dynamic "copy_action" {
      for_each = var.backup_copy_actions
      content {
        destination_vault_arn = copy_action.value.destination_vault_arn
        
        lifecycle {
          cold_storage_after = lookup(copy_action.value, "cold_storage_after", null)
          delete_after       = lookup(copy_action.value, "delete_after", null)
        }
      }
    }

    recovery_point_tags = merge(
      var.tags,
      {
        BackupPlan = "${var.name}-efs-backup-plan"
      }
    )
  }

  # Weekly backups (longer retention)
  dynamic "rule" {
    for_each = var.enable_weekly_backup ? [1] : []
    content {
      rule_name         = "weekly_backup"
      target_vault_name = var.backup_vault_name
      schedule          = var.weekly_backup_schedule

      lifecycle {
        cold_storage_after = var.weekly_backup_cold_storage_after
        delete_after       = var.weekly_backup_retention_days
      }

      recovery_point_tags = merge(
        var.tags,
        {
          BackupPlan = "${var.name}-efs-weekly-backup"
        }
      )
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-efs-backup-plan"
    }
  )
}

resource "aws_backup_selection" "efs" {
  count        = var.create_custom_backup_plan ? 1 : 0
  name         = "${var.name}-efs-backup-selection"
  plan_id      = aws_backup_plan.efs[0].id
  iam_role_arn = var.backup_iam_role_arn

  resources = [
    aws_efs_file_system.this.arn
  ]

  dynamic "condition" {
    for_each = var.backup_selection_conditions
    content {
      dynamic "string_equals" {
        for_each = lookup(condition.value, "string_equals", [])
        content {
          key   = string_equals.value.key
          value = string_equals.value.value
        }
      }

      dynamic "string_not_equals" {
        for_each = lookup(condition.value, "string_not_equals", [])
        content {
          key   = string_not_equals.value.key
          value = string_not_equals.value.value
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------------------
# CloudWatch Alarms for EFS Monitoring
# -----------------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "burst_credit_balance" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.name}-efs-low-burst-credit"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.burst_credit_balance_threshold
  alarm_description   = "EFS burst credit balance is low - may impact performance"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    FileSystemId = aws_efs_file_system.this.id
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "percent_io_limit" {
  count               = var.enable_cloudwatch_alarms ? 1 : 0
  alarm_name          = "${var.name}-efs-high-io-limit"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "PercentIOLimit"
  namespace           = "AWS/EFS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.percent_io_limit_threshold
  alarm_description   = "EFS I/O limit percentage is high"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    FileSystemId = aws_efs_file_system.this.id
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------------------
# EFS Replication (Optional - for DR)
# -----------------------------------------------------------------------------------------
resource "aws_efs_replication_configuration" "this" {
  count                 = var.enable_replication ? 1 : 0
  source_file_system_id = aws_efs_file_system.this.id

  destination {
    region                 = var.replication_destination_region
    file_system_id         = var.replication_destination_file_system_id
    availability_zone_name = var.replication_destination_az
    kms_key_id             = var.replication_destination_kms_key_id
  }
}