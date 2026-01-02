output "id" {
  description = "The ID of the EFS file system"
  value       = aws_efs_file_system.this.id
}

output "arn" {
  description = "The ARN of the EFS file system"
  value       = aws_efs_file_system.this.arn
}

output "dns_name" {
  description = "The DNS name of the EFS file system"
  value       = aws_efs_file_system.this.dns_name
}

output "mount_target_ids" {
  description = "List of mount target IDs"
  value       = aws_efs_mount_target.this[*].id
}

output "mount_target_dns_names" {
  description = "List of mount target DNS names"
  value       = aws_efs_mount_target.this[*].dns_name
}

output "mount_target_network_interface_ids" {
  description = "List of mount target network interface IDs"
  value       = aws_efs_mount_target.this[*].network_interface_id
}

output "access_point_ids" {
  description = "Map of access point names to IDs"
  value       = { for k, v in aws_efs_access_point.this : k => v.id }
}

output "access_point_arns" {
  description = "Map of access point names to ARNs"
  value       = { for k, v in aws_efs_access_point.this : k => v.arn }
}

output "kms_key_id" {
  description = "The KMS key ID used for encryption"
  value       = var.encrypted && var.create_kms_key ? aws_kms_key.efs[0].id : var.kms_key_id
}

output "kms_key_arn" {
  description = "The KMS key ARN used for encryption"
  value       = var.encrypted && var.create_kms_key ? aws_kms_key.efs[0].arn : null
}