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