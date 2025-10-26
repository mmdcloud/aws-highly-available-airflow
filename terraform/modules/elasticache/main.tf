resource "aws_elasticache_cluster" "cluster" {
  cluster_id           = "cluster-example"
  engine               = "redis"
  node_type            = "cache.m4.large"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis3.2"
  engine_version       = "3.2.10"
  port                 = 6379
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.cluster_name}-redis-subnet-group"
  subnet_ids = values(aws_subnet.private)[*].id
}

resource "aws_security_group" "redis_sg" {
  name        = "${var.cluster_name}-redis-sg"
  vpc_id      = aws_vpc.this.id
  description = "Allow redis from airflow instances"
  tags        = { Name = "redis-sg" }
}

resource "aws_elasticache_replication_group" "redis" {
  description                   = "Security group for Redis"
  replication_group_id          = "${var.cluster_name}-redis"
  replication_group_description = "Airflow celery broker"
  engine                        = "redis"
  engine_version                = "7.0"
  node_type                     = "cache.m6g.large"
  num_cache_clusters            = 2
  automatic_failover_enabled    = true
  subnet_group_name             = aws_elasticache_subnet_group.redis.name
  security_group_ids            = [aws_security_group.redis_sg.id]
  parameter_group_name          = "default.redis7"
  tags = {
    Name = "airflow-redis"
  }
}
