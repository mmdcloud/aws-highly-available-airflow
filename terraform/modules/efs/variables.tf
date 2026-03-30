# -----------------------------------------------------------------------------------------
# modules/efs/variables.tf
# -----------------------------------------------------------------------------------------

# -----------------------------------------------------------------------------------------
# Basic Configuration
# -----------------------------------------------------------------------------------------
variable "name" {
  description = "Name of the EFS file system"
  type        = string
}

variable "creation_token" {
  description = "A unique name used as reference when creating the EFS file system"
  type        = string
  default     = ""
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------------------
# Encryption Configuration
# -----------------------------------------------------------------------------------------
variable "encrypted" {
  description = "Whether to encrypt the file system"
  type        = bool
  default     = true
}

variable "create_kms_key" {
  description = "Whether to create a KMS key for encryption"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "ARN of the KMS key to use (if not creating a new one)"
  type        = string
  default     = null
}

variable "kms_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 30
}

# -----------------------------------------------------------------------------------------
# Performance Configuration
# -----------------------------------------------------------------------------------------
variable "performance_mode" {
  description = "Performance mode of the file system (generalPurpose or maxIO)"
  type        = string
  default     = "generalPurpose"

  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.performance_mode)
    error_message = "Performance mode must be either 'generalPurpose' or 'maxIO'."
  }
}

variable "throughput_mode" {
  description = "Throughput mode (bursting, provisioned, or elastic)"
  type        = string
  default     = "elastic"

  validation {
    condition     = contains(["bursting", "provisioned", "elastic"], var.throughput_mode)
    error_message = "Throughput mode must be 'bursting', 'provisioned', or 'elastic'."
  }
}

variable "provisioned_throughput_in_mibps" {
  description = "Throughput in MiB/s (only used when throughput_mode is provisioned)"
  type        = number
  default     = null
}

# -----------------------------------------------------------------------------------------
# Network Configuration
# -----------------------------------------------------------------------------------------
variable "subnet_ids" {
  description = "List of subnet IDs where mount targets will be created"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs to attach to mount targets"
  type        = list(string)
}

variable "mount_target_ip_addresses" {
  description = "List of IP addresses for mount targets (optional)"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------------------
# Lifecycle Management
# -----------------------------------------------------------------------------------------
variable "lifecycle_policies" {
  description = "List of lifecycle policies for the file system"
  type = list(object({
    transition_to_ia                    = optional(string)
    transition_to_primary_storage_class = optional(string)
    transition_to_archive               = optional(string)
  }))
  default = [
    {
      transition_to_ia = "AFTER_30_DAYS"
    }
  ]
}

# -----------------------------------------------------------------------------------------
# Protection Settings
# -----------------------------------------------------------------------------------------
variable "enable_protection" {
  description = "Whether to enable replication overwrite protection"
  type        = bool
  default     = false
}

variable "replication_overwrite_protection" {
  description = "Replication overwrite protection setting (ENABLED or DISABLED)"
  type        = string
  default     = "DISABLED"
}

# -----------------------------------------------------------------------------------------
# Access Points Configuration
# -----------------------------------------------------------------------------------------
variable "access_points" {
  description = "Map of access point configurations"
  type = map(object({
    root_directory_path = optional(string)
    creation_info = optional(object({
      owner_gid   = number
      owner_uid   = number
      permissions = string
    }))
    posix_user = optional(object({
      gid            = number
      uid            = number
      secondary_gids = optional(list(number))
    }))
    tags = optional(map(string))
  }))
  default = {}
}

# -----------------------------------------------------------------------------------------
# File System Policy
# -----------------------------------------------------------------------------------------
variable "file_system_policy" {
  description = "JSON-formatted file system policy"
  type        = string
  default     = null
}

variable "bypass_policy_lockout_safety_check" {
  description = "Whether to bypass the file system policy lockout safety check"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------------------
# Backup Configuration
# -----------------------------------------------------------------------------------------
variable "enable_backup_policy" {
  description = "Whether to enable automatic backups using EFS backup policy"
  type        = bool
  default     = true
}

variable "create_custom_backup_plan" {
  description = "Whether to create a custom AWS Backup plan"
  type        = bool
  default     = true
}

variable "backup_vault_name" {
  description = "Name of the AWS Backup vault"
  type        = string
  default     = "Default"
}

variable "backup_schedule" {
  description = "Cron expression for backup schedule"
  type        = string
  default     = "cron(0 2 * * ? *)" # Daily at 2 AM UTC
}

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 35
}

variable "backup_cold_storage_after" {
  description = "Number of days before moving backups to cold storage"
  type        = number
  default     = 30
}

variable "backup_iam_role_arn" {
  description = "IAM role ARN for AWS Backup"
  type        = string
  default     = null
}

variable "backup_copy_actions" {
  description = "List of backup copy actions for cross-region/cross-account backups"
  type = list(object({
    destination_vault_arn = string
    cold_storage_after    = optional(number)
    delete_after          = optional(number)
  }))
  default = []
}

variable "backup_selection_conditions" {
  description = "List of conditions for backup selection"
  type = list(object({
    string_equals = optional(list(object({
      key   = string
      value = string
    })))
    string_not_equals = optional(list(object({
      key   = string
      value = string
    })))
  }))
  default = []
}

# Weekly backup settings
variable "enable_weekly_backup" {
  description = "Whether to enable weekly backups with longer retention"
  type        = bool
  default     = true
}

variable "weekly_backup_schedule" {
  description = "Cron expression for weekly backup schedule"
  type        = string
  default     = "cron(0 3 ? * SUN *)" # Weekly on Sunday at 3 AM UTC
}

variable "weekly_backup_retention_days" {
  description = "Number of days to retain weekly backups"
  type        = number
  default     = 90
}

variable "weekly_backup_cold_storage_after" {
  description = "Number of days before moving weekly backups to cold storage"
  type        = number
  default     = 60
}

# -----------------------------------------------------------------------------------------
# CloudWatch Alarms
# -----------------------------------------------------------------------------------------
variable "enable_cloudwatch_alarms" {
  description = "Whether to enable CloudWatch alarms"
  type        = bool
  default     = true
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarms trigger"
  type        = list(string)
  default     = []
}

variable "burst_credit_balance_threshold" {
  description = "Threshold for burst credit balance alarm (in bytes)"
  type        = number
  default     = 1000000000000 # 1 TB
}

variable "percent_io_limit_threshold" {
  description = "Threshold for percent I/O limit alarm"
  type        = number
  default     = 80
}

# -----------------------------------------------------------------------------------------
# Replication Configuration (Disaster Recovery)
# -----------------------------------------------------------------------------------------
variable "enable_replication" {
  description = "Whether to enable EFS replication for disaster recovery"
  type        = bool
  default     = false
}

variable "replication_destination_region" {
  description = "AWS region for replication destination"
  type        = string
  default     = null
}

variable "replication_destination_file_system_id" {
  description = "File system ID for replication destination (if pre-existing)"
  type        = string
  default     = null
}

variable "replication_destination_az" {
  description = "Availability zone for replication destination (One Zone only)"
  type        = string
  default     = null
}

variable "replication_destination_kms_key_id" {
  description = "KMS key ID for replication destination encryption"
  type        = string
  default     = null
}