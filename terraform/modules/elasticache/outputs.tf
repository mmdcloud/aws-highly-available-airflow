output "id" {
  value = aws_elasticache_replication_group.replication_group.id
}

output "configuration_endpoint_address" {
  value = aws_elasticache_replication_group.replication_group.configuration_endpoint_address 
}

output "primary_endpoint_address" {
  value = aws_elasticache_replication_group.replication_group.primary_endpoint_address 
}