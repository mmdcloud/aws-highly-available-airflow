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
  database_subnets        = var.database_subnets
  elasticache_subnets     = var.elasticache_subnets
  enable_dns_hostnames    = true
  enable_dns_support      = true
  create_igw              = true
  map_public_ip_on_launch = true
  enable_nat_gateway      = true
  single_nat_gateway      = false
  one_nat_gateway_per_az  = true
  tags = {
    Name      = "vpc"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
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
    Name      = "airflow-scheduler-sg"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
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
    Name      = "airflow-worker-sg"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
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
    Name      = "airflow-webserver-lb-sg"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
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
    Name      = "airflow-webserver-sg"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
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
  egress_rules = []
  tags = {
    Name      = "airflow-rds-sg"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
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
  egress_rules = []
  tags = {
    Name      = "airflow-redis-sg"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

module "efs_sg" {
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
      description     = "Allow all outbound traffic"
      from_port       = 0
      to_port         = 0
      protocol        = "-1"
      security_groups = []
      cidr_blocks     = ["0.0.0.0/0"]
    }
  ]
  tags = {
    Name      = "airflow-efs-sg"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}