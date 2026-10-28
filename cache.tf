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