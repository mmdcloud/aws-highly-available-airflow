# 🚀 High Availability Apache Airflow on AWS

[![Terraform](https://img.shields.io/badge/Terraform-1.0+-623CE4?style=flat&logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Cloud-FF9900?style=flat&logo=amazon-aws)](https://aws.amazon.com/)
[![Apache Airflow](https://img.shields.io/badge/Apache%20Airflow-2.x-017CEE?style=flat&logo=apache-airflow)](https://airflow.apache.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A production-ready, highly available Apache Airflow deployment on AWS using Terraform. This infrastructure leverages AWS ECS Fargate, RDS PostgreSQL, ElastiCache Redis, and EFS to provide a scalable, fault-tolerant data orchestration platform.

## 📋 Table of Contents

- [Architecture](#-architecture)
- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Cost Considerations](#-cost-considerations)
- [Quick Start](#-quick-start)
- [Configuration](#-configuration)
- [Deployment](#-deployment)
- [Monitoring](#-monitoring)
- [Scaling](#-scaling)
- [Backup & Recovery](#-backup--recovery)
- [Troubleshooting](#-troubleshooting)
- [Cleanup](#-cleanup)
- [Security](#-security)
- [Contributing](#-contributing)

## 🏗 Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         AWS Cloud (VPC)                          │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │                    Public Subnets (3 AZs)                   │ │
│  │                                                              │ │
│  │  ┌──────────────────────────────────────────────────────┐  │ │
│  │  │          Application Load Balancer (ALB)             │  │ │
│  │  │              (Port 80/443)                           │  │ │
│  │  └─────────────────────┬────────────────────────────────┘  │ │
│  └────────────────────────┼───────────────────────────────────┘ │
│                           │                                      │
│  ┌────────────────────────┼───────────────────────────────────┐ │
│  │                    Private Subnets (3 AZs)                  │ │
│  │                        │                                     │ │
│  │  ┌─────────────────────▼──────────────────────────┐         │ │
│  │  │      ECS Fargate Services (Auto Scaling)       │         │ │
│  │  │                                                 │         │ │
│  │  │  ┌──────────────┐  ┌──────────────┐           │         │ │
│  │  │  │  Webserver   │  │  Webserver   │  (x2)     │         │ │
│  │  │  │  (8080)      │  │  (8080)      │           │         │ │
│  │  │  └──────────────┘  └──────────────┘           │         │ │
│  │  │                                                 │         │ │
│  │  │  ┌──────────────┐  ┌──────────────┐           │         │ │
│  │  │  │  Scheduler   │  │  Scheduler   │  (x2)     │         │ │
│  │  │  └──────────────┘  └──────────────┘           │         │ │
│  │  │                                                 │         │ │
│  │  │  ┌──────────────┐  ┌──────────────┐           │         │ │
│  │  │  │   Worker     │  │   Worker     │  (3-20)   │         │ │
│  │  │  └──────────────┘  └──────────────┘           │         │ │
│  │  └──────────┬──────────────┬──────────────────────┘         │ │
│  │             │              │                                 │ │
│  │  ┌──────────▼──────┐  ┌───▼──────────┐  ┌────────────────┐ │ │
│  │  │  RDS PostgreSQL │  │ ElastiCache  │  │   EFS (DAGs)   │ │ │
│  │  │   (Multi-AZ)    │  │    Redis     │  │                │ │ │
│  │  │   db.r6g.large  │  │  (Multi-AZ)  │  │  Shared Storage│ │ │
│  │  └─────────────────┘  └──────────────┘  └────────────────┘ │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                      Supporting Services                      │ │
│  │                                                               │ │
│  │  ┌────────────┐  ┌─────────────┐  ┌──────────────────────┐ │ │
│  │  │ S3 Buckets │  │   Secrets   │  │  CloudWatch Alarms   │ │ │
│  │  │ (DAGs/Logs)│  │   Manager   │  │   & Monitoring       │ │ │
│  │  └────────────┘  └─────────────┘  └──────────────────────┘ │ │
│  └─────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────┘
```

### Architecture Components

| Component | Service | Purpose | High Availability |
|-----------|---------|---------|-------------------|
| **Web Interface** | ALB + ECS Fargate | User interface for Airflow | Multi-AZ, Auto-scaling |
| **Scheduler** | ECS Fargate | DAG parsing and task scheduling | Multi-instance, Health checks |
| **Workers** | ECS Fargate | Task execution | Auto-scaling (3-20 instances) |
| **Metadata DB** | RDS PostgreSQL 15.4 | Store Airflow metadata | Multi-AZ, Automated backups |
| **Message Broker** | ElastiCache Redis 7.0 | Celery task queue | Multi-AZ, Auto-failover |
| **DAG Storage** | EFS | Shared DAG repository | Multi-AZ, Encrypted |
| **Log Storage** | S3 | Remote log storage | Versioned, Durable |

## ✨ Features

- **High Availability**: Multi-AZ deployment across all components
- **Auto Scaling**: Dynamic worker scaling (3-20 instances) based on CPU utilization
- **Security**: 
  - Encryption at rest (RDS, EFS, S3)
  - Encryption in transit (Redis TLS)
  - Private subnets for all compute resources
  - Security groups with least privilege access
- **Monitoring**: CloudWatch alarms for critical metrics
- **Backup**: Automated RDS backups (30-day retention)
- **Performance**: 
  - RDS Enhanced Monitoring
  - Performance Insights enabled
  - Optimized PostgreSQL parameters
- **Logging**: Centralized logging with FluentBit and CloudWatch
- **Observability**: SNS notifications for critical alerts

## 📦 Prerequisites

Before deploying this infrastructure, ensure you have:

- **AWS Account** with appropriate permissions
- **Terraform** >= 1.0
- **AWS CLI** configured with credentials
- **Vault** (for secrets management)
- **Docker** images for Airflow components pushed to ECR

### Required IAM Permissions

The deploying user/role needs permissions for:
- VPC, Subnet, Security Group, Internet Gateway
- ECS (Cluster, Service, Task Definition)
- RDS (DB Instance, Subnet Group, Parameter Group)
- ElastiCache (Replication Group, Subnet Group)
- EFS (File System, Mount Target, Access Point)
- ALB (Load Balancer, Target Group, Listener)
- S3 (Bucket creation and policies)
- Secrets Manager
- CloudWatch (Alarms, Log Groups)
- SNS (Topics and Subscriptions)
- IAM (Roles and Policies)

## 💰 Cost Considerations

### Monthly Cost Estimate (US East-1)

| Service | Configuration | Estimated Cost |
|---------|--------------|----------------|
| **RDS PostgreSQL** | db.r6g.large, Multi-AZ, 100GB GP3 | ~$450/month |
| **ElastiCache Redis** | 3x cache.t4g.micro, Multi-AZ | ~$60/month |
| **ECS Fargate** | 2 Webservers (2vCPU, 4GB) | ~$90/month |
| **ECS Fargate** | 2 Schedulers (2vCPU, 4GB) | ~$90/month |
| **ECS Fargate** | 3-20 Workers (2vCPU, 4GB) | ~$135-900/month |
| **EFS** | 50GB storage + requests | ~$20/month |
| **ALB** | Standard load balancer | ~$25/month |
| **S3** | 100GB storage + requests | ~$10/month |
| **NAT Gateway** | Per AZ (if enabled) | ~$100/month/AZ |
| **CloudWatch** | Logs and metrics | ~$30/month |
| **Data Transfer** | Varies by usage | Variable |

**Total Estimated Cost**: $910 - $1,775/month (minimum to maximum worker scaling)

### Cost Optimization Tips

1. **Right-size RDS**: Start with db.t4g.large if appropriate for your workload
2. **Disable NAT Gateway**: If workers don't need internet access (`enable_nat_gateway = false`)
3. **Use Spot Instances**: Consider Fargate Spot for workers (50-70% discount)
4. **Optimize Storage**: Enable S3 lifecycle policies for log archival
5. **Reserved Capacity**: Purchase RDS Reserved Instances for 1-3 year commitment (40-60% savings)
6. **Monitoring**: Set up AWS Budgets and Cost Anomaly Detection

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/ha-airflow-aws.git
cd ha-airflow-aws
```

### 2. Configure Variables

Create a `terraform.tfvars` file:

```hcl
# Region Configuration
region = "us-east-1"
azs    = ["us-east-1a", "us-east-1b", "us-east-1c"]

# Network Configuration
public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnets = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

# Database Credentials (Store in Vault)
db_username = "airflow"
db_password = "your-secure-password"  # Use Vault instead

# Redis Auth Token
redis_auth_token = "your-redis-token"  # Use Vault instead

# Domain Configuration (optional)
domain_name = "airflow.yourdomain.com"
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Review the Plan

```bash
terraform plan
```

### 5. Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted to confirm the deployment.

## ⚙️ Configuration

### Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `region` | AWS region | - | Yes |
| `azs` | Availability zones | - | Yes |
| `public_subnets` | Public subnet CIDRs | - | Yes |
| `private_subnets` | Private subnet CIDRs | - | Yes |
| `db_username` | RDS username | - | Yes |
| `db_password` | RDS password | - | Yes |
| `redis_auth_token` | Redis authentication token | - | Yes |
| `domain_name` | Custom domain name | - | No |

### Environment Variables

Configure Airflow through environment variables in the ECS task definitions:

```hcl
AIRFLOW__CORE__EXECUTOR = "CeleryExecutor"
AIRFLOW__DATABASE__SQL_ALCHEMY_CONN = "postgresql+psycopg2://..."
AIRFLOW__CELERY__BROKER_URL = "redis://..."
AIRFLOW__LOGGING__REMOTE_LOGGING = "True"
```

## 🎯 Deployment

### Initial Deployment

```bash
# Validate configuration
terraform validate

# Plan deployment
terraform plan -out=tfplan

# Apply changes
terraform apply tfplan
```

### Updating Infrastructure

```bash
# Make changes to .tf files

# Review changes
terraform plan

# Apply updates
terraform apply
```

### Deploying New Airflow Images

```bash
# Build and push new image to ECR
docker build -t airflow:latest .
docker tag airflow:latest <account-id>.dkr.ecr.<region>.amazonaws.com/airflow:latest
docker push <account-id>.dkr.ecr.<region>.amazonaws.com/airflow:latest

# Force new deployment
aws ecs update-service \
  --cluster ha-airflow-ecs-cluster \
  --service webserver \
  --force-new-deployment
```

## 📊 Monitoring

### CloudWatch Alarms

The infrastructure includes pre-configured alarms for:

- **RDS CPU Utilization** (Threshold: 80%)
- **RDS Connection Count** (Threshold: 400 connections)
- **Redis CPU Utilization** (Threshold: 75%)
- **ECS Scheduler CPU** (Threshold: 80%)
- **ALB Unhealthy Targets** (Threshold: 0)

### Accessing Logs

```bash
# View ECS service logs
aws logs tail /aws/ecs/airflow-webserver --follow

# View RDS logs
aws rds describe-db-log-files \
  --db-instance-identifier airflow-metadata-db
```

### Metrics Dashboard

Access CloudWatch metrics:
1. Navigate to CloudWatch Console
2. Select **Dashboards**
3. Create custom dashboard with:
   - ECS service metrics
   - RDS performance metrics
   - ALB request metrics
   - ElastiCache metrics

## 📈 Scaling

### Worker Auto Scaling

Workers automatically scale between 3-20 instances based on CPU utilization (target: 70%).

**Manual Scaling**:

```bash
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --scalable-dimension ecs:service:DesiredCount \
  --resource-id service/ha-airflow-ecs-cluster/worker \
  --min-capacity 5 \
  --max-capacity 30
```

### Vertical Scaling

To increase service capacity, modify the task definitions:

```hcl
# In main.tf
services = {
  webserver = {
    cpu    = 4096  # Increase from 2048
    memory = 8192  # Increase from 4096
    # ...
  }
}
```

## 💾 Backup & Recovery

### Automated Backups

- **RDS**: Daily automated backups with 30-day retention
- **EFS**: AWS Backup enabled
- **S3**: Versioning enabled on all buckets

### Manual Backup

```bash
# Create RDS snapshot
aws rds create-db-snapshot \
  --db-instance-identifier airflow-metadata-db \
  --db-snapshot-identifier airflow-backup-$(date +%Y%m%d)

# Export DAGs from EFS
aws efs create-backup \
  --file-system-id <efs-id>
```

### Disaster Recovery

**RTO**: ~30 minutes  
**RPO**: 5 minutes (automated backups)

**Recovery Steps**:
1. Restore RDS from latest snapshot
2. Update Terraform with restored RDS endpoint
3. Re-apply Terraform configuration
4. Verify service health

## 🔧 Troubleshooting

### Common Issues

#### Services Not Starting

```bash
# Check ECS service events
aws ecs describe-services \
  --cluster ha-airflow-ecs-cluster \
  --services webserver

# Check task failures
aws ecs describe-tasks \
  --cluster ha-airflow-ecs-cluster \
  --tasks <task-id>
```

#### Database Connection Issues

```bash
# Test RDS connectivity
aws rds describe-db-instances \
  --db-instance-identifier airflow-metadata-db \
  --query 'DBInstances[0].Endpoint'

# Verify security group rules
aws ec2 describe-security-groups \
  --group-ids <rds-sg-id>
```

#### High CPU on RDS

- Review slow query logs
- Optimize DAG parsing frequency
- Increase RDS instance size
- Add read replicas

## 🧹 Cleanup

### Destroy All Resources

```bash
# Disable deletion protection (if enabled)
terraform apply -var="deletion_protection=false"

# Destroy infrastructure
terraform destroy
```

**⚠️ Warning**: This will permanently delete:
- All ECS services and tasks
- RDS database (unless `skip_final_snapshot = false`)
- ElastiCache cluster
- EFS file system
- S3 buckets (if `force_destroy = true`)

### Selective Cleanup

```bash
# Remove specific resources
terraform destroy -target=module.ha_airflow_ecs_cluster.aws_ecs_service.worker
```

### Pre-Cleanup Checklist

- [ ] Backup critical DAGs and data
- [ ] Export important logs
- [ ] Create final RDS snapshot
- [ ] Document any custom configurations
- [ ] Notify team members

## 🔒 Security

### Best Practices Implemented

- ✅ All compute resources in private subnets
- ✅ Encryption at rest (RDS, EFS, S3)
- ✅ Encryption in transit (Redis TLS)
- ✅ Secrets stored in AWS Secrets Manager
- ✅ Least privilege IAM roles
- ✅ Security groups with minimal required access
- ✅ Multi-AZ deployment for fault tolerance
- ✅ Automated backups enabled
- ✅ CloudWatch monitoring and alarms

### Security Checklist

Before production deployment:

- [ ] Rotate default credentials
- [ ] Enable MFA for AWS accounts
- [ ] Configure VPC Flow Logs
- [ ] Set up AWS CloudTrail
- [ ] Implement AWS WAF rules on ALB
- [ ] Enable GuardDuty
- [ ] Configure AWS Config rules
- [ ] Set up AWS Security Hub
- [ ] Review IAM policies regularly
- [ ] Enable RDS encryption with KMS

## 🤝 Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Follow Terraform best practices
- Update documentation for any changes
- Test changes in a non-production environment
- Include cost impact in PR description

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Apache Airflow](https://airflow.apache.org/)
- [Terraform AWS Modules](https://github.com/terraform-aws-modules)
- AWS Documentation and Best Practices

---

**Made with ❤️ by Your Team**

*Last Updated: December 2025*
