<!-- # 🚀 Production-Grade High Availability Apache Airflow on AWS

[![Terraform](https://img.shields.io/badge/Terraform-1.5+-623CE4?style=flat&logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Cloud-FF9900?style=flat&logo=amazon-aws)](https://aws.amazon.com/)
[![Apache Airflow](https://img.shields.io/badge/Apache%20Airflow-2.10.x-017CEE?style=flat&logo=apache-airflow)](https://airflow.apache.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17-336791?style=flat&logo=postgresql)](https://www.postgresql.org/)
[![Redis](https://img.shields.io/badge/Redis-7.0-DC382D?style=flat&logo=redis)](https://redis.io/)
[![HashiCorp Vault](https://img.shields.io/badge/Vault-1.x-000000?style=flat&logo=vault)](https://www.vaultproject.io/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

An enterprise-ready, fully parameterized, and highly available Apache Airflow deployment on AWS built with Terraform. This architecture leverages **AWS ECS Fargate**, **Amazon RDS PostgreSQL 17 (Multi-AZ)**, **Amazon ElastiCache Redis 7.0 (Multi-AZ)**, **Amazon EFS**, and **Amazon S3** to deliver a fault-tolerant, secure, and auto-scaling workflow orchestration platform with **zero single points of failure**.

---

## 📋 Table of Contents

- [Architecture](#-architecture)
- [Key Features](#-key-features)
- [Infrastructure Components](#-infrastructure-components)
- [Repository Structure](#-repository-structure)
- [Prerequisites](#-prerequisites)
- [Vault Secrets Management](#-vault-secrets-management)
- [Quick Start Guide](#-quick-start-guide)
- [DAG Deployment Workflow](#-dag-deployment-workflow)
- [Configuration Reference](#-configuration-reference)
- [Fargate vCPU Quota Sizing](#-fargate-vcpu-quota-sizing)
- [Monitoring & Observability](#-monitoring--observability)
- [Backup & Disaster Recovery](#-backup--disaster-recovery)
- [Security & Compliance](#-security--compliance)
- [Troubleshooting & Runbooks](#-troubleshooting--runbooks)
- [Cleanup](#-cleanup)

---

## 🏗 Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                       AWS VPC (Multi-AZ)                                │
│                                                                                         │
│  ┌───────────────────────────────────────────────────────────────────────────────────┐  │
│  │                              Public Subnets (3 AZs)                               │  │
│  │                                                                                   │  │
│  │  ┌─────────────────────────────────────────────────────────────────────────────┐  │  │
│  │  │                     Application Load Balancer (ALB)                         │  │  │
│  │  │                         HTTP (80) / HTTPS (443)                             │  │  │
│  │  └──────────────────────────────────┬──────────────────────────────────────────┘  │  │
│  └─────────────────────────────────────┼─────────────────────────────────────────────┘  │
│                                        │                                                │
│  ┌─────────────────────────────────────┼─────────────────────────────────────────────┐  │
│  │                                     │ Private Subnets (3 AZs)                     │  │
│  │                                     ▼                                             │  │
│  │  ┌─────────────────────────────────────────────────────────────────────────────┐  │  │
│  │  │                    Amazon ECS Fargate Cluster                               │  │  │
│  │  │                                                                             │  │  │
│  │  │  ┌───────────────────────┐  ┌───────────────────────┐                       │  │  │
│  │  │  │  Airflow Webserver    │  │  Airflow Webserver    │ (Auto-scaling 2-10)   │  │  │
│  │  │  │  (Port 8080)          │  │  (Port 8080)          │                       │  │  │
│  │  │  └───────────────────────┘  └───────────────────────┘                       │  │  │
│  │  │                                                                             │  │  │
│  │  │  ┌──────────────────────────────────────────────────┐                       │  │  │
│  │  │  │  Airflow Scheduler + S3 DAG Sync Sidecar         │ (CeleryExecutor)      │  │  │
│  │  │  └──────────────────────────────────────────────────┘                       │  │  │
│  │  │                                                                             │  │  │
│  │  │  ┌───────────────────────┐  ┌───────────────────────┐                       │  │  │
│  │  │  │  Airflow Celery Worker│  │  Airflow Celery Worker│ (Auto-scaling 2-10)   │  │  │
│  │  │  └───────────────────────┘  └───────────────────────┘                       │  │  │
│  │  └──────────────────────┬──────────────────┬──────────────────┬────────────────┘  │  │
│  │                         │                  │                  │                   │  │
│  │  ┌──────────────────────▼───┐  ┌───────────▼───────────┐  ┌───▼────────────────┐  │  │
│  │  │ Amazon RDS PostgreSQL 17 │  │ Amazon ElastiCache    │  │   Amazon EFS       │  │  │
│  │  │     (Multi-AZ)           │  │     Redis 7.0         │  │   Shared DAGs      │  │  │
│  │  │ db.r6g.large / GP3 Auto  │  │ Multi-AZ Auto-Failover│  │   POSIX Mounts     │  │  │
│  │  └──────────────────────────┘  └───────────────────────┘  └────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                         │
│  ┌───────────────────────────────────────────────────────────────────────────────────┐  │
│  │                                Supporting Services                                │  │
│  │                                                                                   │  │
│  │  ┌───────────────────────┐  ┌─────────────────────────┐  ┌─────────────────────┐  │  │
│  │  │  Amazon S3            │  │  AWS Secrets Manager    │  │ Amazon CloudWatch   │  │  │
│  │  │  - Remote Logs        │  │  - Admin Credentials    │  │  - Metric Alarms    │  │  │
│  │  │  - DAG Source Sync    │  │  - Webserver Secret Key │  │  - Container Logs   │  │  │
│  │  │  - ALB Access Logs    │  │  HashiCorp Vault        │  │  - SNS Notifications│  │  │
│  │  └───────────────────────┘  └─────────────────────────┘  └─────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## ✨ Key Features

- **True High Availability**: Multi-AZ architecture across ALB, ECS Fargate, RDS PostgreSQL 17, ElastiCache Redis 7.0, and EFS.
- **Automated Schema & Admin Initialization**: Self-healing one-off ECS Fargate migration tasks (`airflow db migrate` and `airflow users create`) run and verify automatically during deployment.
- **S3-to-EFS DAG Sync**: Continuously syncs DAGs from an S3 bucket to EFS shared volume via a lightweight sidecar container without redeploying containers or restarting tasks.
- **Enterprise Secret Management**: Zero credentials stored in code; credentials dynamically pulled from HashiCorp Vault into AWS Secrets Manager and task definitions.
- **Dynamic Auto-Scaling**: Worker and Webserver tasks automatically scale out/in based on workload and CloudWatch metrics.
- **Quota-Aware Compute Sizing**: Pre-tuned to launch smoothly within standard AWS Fargate account limits (8 vCPUs) while being fully configurable for enterprise scale.
- **Automated Backup & Recovery**: EFS backed up via AWS Backup (Daily & Weekly rules with retention); RDS automated Multi-AZ backups with 30-day retention.

---

## 🧩 Infrastructure Components

| Component | AWS Service | Sizing / Engine | High Availability & Resilience |
|-----------|-------------|-----------------|--------------------------------|
| **Ingress** | Application Load Balancer (ALB) | Public multi-AZ listeners, health checks | Cross-zone load balancing, session stickiness |
| **Orchestration** | Amazon ECS Fargate | Cluster with `FARGATE` & `FARGATE_SPOT` | Multi-AZ task placement, auto-recovery |
| **Web Interface** | ECS Fargate Service (`webserver`) | 1024 CPU / 2048 MB (2 desired, scales 2–10) | Multi-AZ auto-scaled, ALB target group |
| **Scheduler** | ECS Fargate Service (`scheduler`) | 1024 CPU / 2048 MB (768 CPU core + 256 CPU sync) | 1 active replica with S3 DAG sync sidecar |
| **Worker Nodes** | ECS Fargate Service (`worker`) | 1024 CPU / 2048 MB (2 desired, scales 2–10) | CeleryExecutor workers with dynamic StepScaling |
| **Metadata DB** | Amazon RDS PostgreSQL | PostgreSQL 17, `db.r6g.large`, GP3 Storage | Multi-AZ synchronous replication, 30-day backups |
| **Celery Broker**| Amazon ElastiCache Redis | Redis 7.0, `cache.t4g.micro`, 2 nodes | Multi-AZ auto-failover, In-transit & At-rest encryption |
| **DAG Storage** | Amazon EFS + S3 | Elastic throughput, generalPurpose | Multi-AZ POSIX locks + automated AWS Backup Vault |
| **Log Storage** | Amazon S3 | AES-256 encrypted, versioned | Remote task log persistence |
| **Secrets Engine**| HashiCorp Vault & AWS Secrets Manager | Key-Value stores | Dynamic retrieval, encrypted parameters |
| **Monitoring** | CloudWatch & SNS | Alarms on RDS, Redis, ECS, ALB | Email notifications via SNS |

---

## 📁 Repository Structure

```
.
├── terraform/                       # 👈 ALL TERRAFORM COMMANDS ARE RUN FROM HERE
│   ├── main.tf                      # Core infrastructure definition
│   ├── variables.tf                 # 30+ fully parameterized, typed variables
│   ├── terraform.tfvars             # Active configuration values
│   ├── terraform.tfvars.example     # Comprehensive template for prod/staging/dev
│   ├── provider.tf                  # AWS, Vault, Random, Time, Null providers
│   ├── outputs.tf                   # Exported endpoints, ARNs, and IDs
│   ├── README.md                    # Dedicated Terraform deployment guide
│   └── modules/                     # Local reusable modules (vpc, rds, ecs, etc.)
├── src/                             # Airflow configuration and utility scripts
├── README.md                        # Project documentation (this file)
└── LICENSE
```

---

## 📦 Prerequisites

Ensure you have the following tools installed and configured:

1. **Terraform** $\ge 1.5.0$ ([Installation Guide](https://developer.hashicorp.com/terraform/install))
2. **AWS CLI** $\ge 2.x$ ([Installation Guide](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)) with credentials configured
3. **HashiCorp Vault** (Local or Remote) with KV v2 secrets engine enabled
4. **`jq`** (used by local-exec verification scripts)

---

## 🔐 Vault Secrets Management

All database passwords, encryption keys, and tokens are stored securely in HashiCorp Vault.

### 1. Set Vault Environment Variables

```bash
export VAULT_ADDR="https://vault.yourdomain.com:8200"
export VAULT_TOKEN="s.your-vault-token"
```

### 2. Populate Required Secrets

```bash
# 1. Metadata Database Credentials (PostgreSQL 17)
vault kv put secret/rds \
  username="airflow" \
  password="YourStrongRDSMasterPassword123!"

# 2. Redis Authentication Token
vault kv put secret/redis \
  auth_token="YourStrongRedisAuthToken123!"

# 3. Airflow Application Secrets
# Fernet key must be a 32-byte URL-safe base64 string:
# python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
vault kv put secret/airflow \
  fernet_key="YOUR_GENERATED_FERNET_KEY_HERE=" \
  admin_password="YourInitialAirflowAdminPassword123!"
```

---

## 🚀 Quick Start Guide

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/aws-highly-available-airflow.git
cd aws-highly-available-airflow
```

### 2. Change into the Terraform Directory

> [!IMPORTANT]
> Always execute Terraform commands from the `terraform/` directory.

```bash
cd terraform/
```

### 3. Configure Your Variables

Review or copy the example configuration:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your CIDRs, domain, and notification email:

```hcl
project_name        = "ha-airflow"
environment         = "prod"
region              = "us-east-1"
domain_name         = "airflow.example.com"
alarm_email         = "alerts@example.com"
```

### 4. Initialize & Deploy

```bash
# Initialize providers and modules
terraform init

# Validate configuration
terraform validate

# Plan and review
terraform plan -out=tfplan

# Apply
terraform apply tfplan
```

During deployment, Terraform will:
1. Create VPC, multi-AZ subnets, NAT Gateways, Security Groups, RDS, Redis, and EFS.
2. Launch an on-demand Fargate task to run `airflow db migrate`.
3. Launch an on-demand Fargate task to create the initial Admin user.
4. Start the Webserver, Scheduler, and Worker services.

### 5. Retrieve Endpoints

```bash
terraform output
```

* **Webserver URL**: `terraform output -raw airflow_webserver_url`
* **RDS Endpoint**: `terraform output -raw rds_metadata_db_endpoint`
* **Redis Endpoint**: `terraform output -raw redis_primary_endpoint`
* **DAGs S3 Bucket**: `terraform output -raw s3_dags_bucket_name`

---

## 🔄 DAG Deployment Workflow

Deploying new or modified DAGs does **not** require container rebuilds or Terraform updates:

```bash
# Get the DAGs bucket name
DAGS_BUCKET=$(terraform output -raw s3_dags_bucket_name)

# Sync local DAGs directory to S3
aws s3 sync ./dags/ s3://${DAGS_BUCKET}/dags/ --delete
```

The `s3_dag_sync` sidecar container running on the Scheduler task automatically pulls updates from S3 into `/opt/airflow/dags` every 30 seconds.

---

## ⚙️ Configuration Reference

### Variable Highlights

| Variable | Description | Default | Production Value |
|----------|-------------|---------|------------------|
| `project_name` | Name prefix for resource naming and tagging | `"ha-airflow"` | Set per project |
| `environment` | Deployment environment (`prod`, `stage`, `dev`) | `"prod"` | `"prod"` |
| `single_nat_gateway` | Single NAT Gateway (saves costs) vs Multi-AZ NAT | `false` | `false` (HA) |
| `airflow_image` | Docker image URI for Airflow components | `"apache/airflow:2.10.4"` | Custom/Official ECR |
| `webserver_cpu` | Webserver task CPU allocation | `1024` | `1024` (1 vCPU) |
| `webserver_memory` | Webserver task RAM allocation | `2048` | `2048` (2 GiB) |
| `scheduler_cpu` | Scheduler task CPU allocation | `1024` | `1024` (1 vCPU) |
| `scheduler_memory`| Scheduler task RAM allocation | `2048` | `2048` (2 GiB) |
| `worker_cpu` | Worker task CPU allocation | `1024` | `1024` (1 vCPU) |
| `worker_memory` | Worker task RAM allocation | `2048` | `2048` (2 GiB) |
| `worker_min_capacity` | Minimum workers for autoscaling | `2` | `2` |
| `worker_max_capacity` | Maximum workers for autoscaling | `10` | `10`–`50` |
| `db_instance_class` | RDS PostgreSQL instance class | `"db.r6g.large"` | `"db.r6g.large"` |
| `db_multi_az` | Enable RDS Multi-AZ replication | `true` | `true` |
| `redis_node_type` | ElastiCache Redis node type | `"cache.t4g.micro"` | `"cache.t4g.medium"` |
| `s3_force_destroy` | Allow deletion of buckets containing objects | `true` | `false` |
| `alarm_email` | SNS destination email for CloudWatch alerts | Required | Team distribution list |

*See [terraform/variables.tf](file:///home/shiv/mohit/aws-highly-available-airflow/terraform/variables.tf) for all 30+ parameter definitions.*

---

## ⚡ Fargate vCPU Quota Sizing

Standard AWS accounts start with an 8 concurrent vCPU limit for Fargate in a region (`fargate/L-3032A538`).

### Default Resource Footprint:
* **Webserver**: $2 \times 1\text{ vCPU} = 2\text{ vCPUs}$
* **Scheduler**: $1 \times 1\text{ vCPU} = 1\text{ vCPU}$
* **Worker**: $2 \times 1\text{ vCPU} = 2\text{ vCPUs}$
* **Initial DB Migration Task**: $1 \times 1\text{ vCPU} = 1\text{ vCPU}$
* **Total Initialization Load**: $6\text{ vCPUs} \le 8\text{ vCPUs}$ (safely within default limits)

For high-volume production, request a Fargate vCPU quota increase via **AWS Service Quotas** $\to$ **Fargate On-Demand vCPU resource count** (`L-3032A538`) to 32 or 64 vCPUs.

---

## 📊 Monitoring & Observability

### CloudWatch Alarms

The stack configures proactive monitoring with automated SNS email notifications:

- **RDS CPU Utilization**: Alarms if $> 80\%$ for 10 minutes.
- **RDS Connections**: Alarms if connection count $> 400$.
- **Redis CPU Utilization**: Alarms if $> 75\%$ for 10 minutes.
- **Scheduler CPU Utilization**: Alarms if $> 80\%$.
- **ALB Unhealthy Target Count**: Alarms immediately if any container fails `/health`.

### Log Streaming

Inspect component logs in real-time:

```bash
# Webserver Logs
aws logs tail /aws/ecs/ha-airflow-prod/webserver --follow

# Scheduler Logs
aws logs tail /aws/ecs/ha-airflow-prod/scheduler --follow

# Worker Logs
aws logs tail /aws/ecs/ha-airflow-prod/worker --follow
```

---

## 💾 Backup & Disaster Recovery

- **Amazon RDS**: Automated daily snapshots retained for 30 days with Point-In-Time Restore (PITR).
- **Amazon EFS**: Dedicated AWS Backup Vault (`ha-airflow-prod-efs-backup-vault`) with automated daily (120-day retention) and weekly (90-day retention) backup plans.
- **Amazon S3**: Object versioning enabled on logs and DAGs buckets.

---

## 🔒 Security & Compliance

- **Private VPC Isolation**: Compute tasks, database instances, and cache clusters run in private subnets with no public IPs.
- **KMS Encryption**: Dedicated Customer Managed Keys for EFS, RDS, and S3 encryption at rest.
- **Transit Encryption**: TLS enabled for EFS mounts and ElastiCache Redis replication traffic.
- **Least-Privilege IAM**: Fine-grained IAM execution and task roles for each ECS component.

---

## 🛠 Troubleshooting & Runbooks

For in-depth troubleshooting of common issues (e.g., Fargate vCPU limits, container CPU/memory splits, AWS Backup vault errors), refer to the **[Terraform Troubleshooting Runbook](file:///home/shiv/mohit/aws-highly-available-airflow/terraform/README.md#-troubleshooting-runbook)**.

---

## 🧹 Cleanup

To tear down all provisioned resources:

```bash
cd terraform/
terraform destroy
```

> [!CAUTION]
> This will permanently destroy the RDS database, Redis cluster, ECS cluster, and all related cloud resources. Ensure you have backed up critical DAGs and data before destroying.

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details. -->

# 🚀 Production Terraform Deployment: Highly Available Apache Airflow on AWS

[![Terraform](https://img.shields.io/badge/Terraform-1.5+-623CE4?style=flat&logo=terraform)](https://www.terraform.io/)
[![AWS Provider](https://img.shields.io/badge/AWS%20Provider-6.x-FF9900?style=flat&logo=amazon-aws)](https://registry.terraform.io/providers/hashicorp/aws/latest)
[![Apache Airflow](https://img.shields.io/badge/Apache%20Airflow-2.10.x-017CEE?style=flat&logo=apache-airflow)](https://airflow.apache.org/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17-336791?style=flat&logo=postgresql)](https://www.postgresql.org/)
[![Redis](https://img.shields.io/badge/Redis-7.0-DC382D?style=flat&logo=redis)](https://redis.io/)
[![HashiCorp Vault](https://img.shields.io/badge/Vault-1.x-000000?style=flat&logo=vault)](https://www.vaultproject.io/)

This directory contains the production-grade, enterprise-ready Terraform infrastructure code for running a **Highly Available, Auto-Scaling Apache Airflow** cluster on AWS with zero single points of failure (SPOF).

---

## 📋 Table of Contents

- [Architecture Overview](#-architecture-overview)
- [Infrastructure Components](#-infrastructure-components)
- [Directory Structure](#-directory-structure)
- [Prerequisites & Requirements](#-prerequisites--requirements)
- [Vault Secrets Setup](#-vault-secrets-setup)
- [AWS Service Quotas (Fargate vCPUs)](#-aws-service-quotas-fargate-vcpus)
- [Configuration & Parameterization](#-configuration--parameterization)
- [Deployment Step-by-Step](#-deployment-step-by-step)
- [DAG Deployment Workflow](#-dag-deployment-workflow)
- [Day-2 Operations & Monitoring](#-day-2-operations--monitoring)
- [Disaster Recovery & Backup](#-disaster-recovery--backup)
- [Security & Compliance](#-security--compliance)
- [Troubleshooting Runbook](#-troubleshooting-runbook)

---

## 🏗 Architecture Overview

```
                                  INTERNET / USERS
                                         │
                                         ▼
                 ┌──────────────────────────────────────────────┐
                 │        Application Load Balancer (ALB)       │
                 │          Public Subnets (Multi-AZ)           │
                 └───────────────────────┬──────────────────────┘
                                         │
                        HTTPS / HTTP 8080 (Private VPC)
                                         │
          ┌──────────────────────────────┴──────────────────────────────┐
          │                                                             │
          ▼                                                             ▼
┌─────────────────────────────────┐           ┌─────────────────────────────────┐
│     ECS Fargate: Webserver      │           │      ECS Fargate: Scheduler     │
│   (2 Replicas, Auto-scaled)     │           │  (1 Primary + S3 DAG Sync Sidecar)│
└────────────────┬────────────────┘           └────────────────┬────────────────┘
                 │                                             │
                 │        ┌────────────────────────────┐       │
                 └───────►│  EFS Shared Volume (DAGs)  │◄──────┘
                          │(Multi-AZ, Access Points, AP)│
                          └──────────────▲─────────────┘
                                         │
                                         │ Mount Points (/opt/airflow/dags)
                                         │
                          ┌──────────────┴─────────────┐
                          │    ECS Fargate: Workers    │
                          │   (2-10 Tasks Auto-scaled) │
                          └──────────────┬─────────────┘
                                         │
                 ┌───────────────────────┴───────────────────────┐
                 │                                               │
                 ▼                                               ▼
┌─────────────────────────────────┐             ┌─────────────────────────────────┐
│     RDS PostgreSQL 17 (DB)      │             │    ElastiCache Redis 7.0        │
│   Multi-AZ, Storage Auto-scale  │             │   Multi-AZ, Celery Broker       │
│    Metadata & Results Backend   │             │   Transit & Rest Encryption     │
└─────────────────────────────────┘             └─────────────────────────────────┘
```

---

## 🧩 Infrastructure Components

| Tier | AWS Service | Sizing / Configuration | High Availability & Resilience |
|------|-------------|------------------------|--------------------------------|
| **Ingress** | Application Load Balancer (ALB) | Dual-AZ public listeners, HTTP/HTTPS, health checks on `/health` | Managed multi-AZ with target group deregistration delay |
| **Orchestration** | ECS Fargate (`ha-airflow-ecs-cluster`) | Capacity Providers: `FARGATE`, `FARGATE_SPOT` | Multi-AZ task placement, task definitions with soft/hard tmpfs limits |
| **Web UI** | ECS Fargate Service (`webserver`) | 1024 CPU / 2048 MB, 2 Desired (scales 2–10) | Auto-recovery, ALB session stickiness via cookies |
| **Scheduler** | ECS Fargate Service (`scheduler`) | 1024 CPU / 2048 MB (768 CPU core + 256 CPU sidecar) | 1 Active replica (CeleryExecutor model), S3 auto-sync sidecar |
| **Task Execution**| ECS Fargate Service (`worker`) | 1024 CPU / 2048 MB, 2 Desired (scales 2–10) | StepScaling policies driven by CloudWatch alarms |
| **Metadata DB** | RDS PostgreSQL 17 | `db.r6g.large` (configurable), GP3 storage auto-scaling 100–200 GB | Multi-AZ synchronous replication, automated 30-day backups |
| **Celery Broker**| ElastiCache Redis 7.0 | `cache.t4g.micro` (configurable), 2 nodes | Multi-AZ automatic failover, in-transit TLS & Auth Token |
| **DAG Storage** | Amazon EFS | Elastic throughput, generalPurpose, access points | Native multi-AZ file locks, AWS Backup daily & weekly plans |
| **Log Storage** | Amazon S3 | Server-side encrypted, versioned, lifecycle rules | 99.999999999% durability remote task log storage |
| **Secrets** | HashiCorp Vault & AWS Secrets Manager | Encrypted key-value stores | Dynamic credentials, no plain-text passwords in code |
| **Monitoring** | Amazon CloudWatch & SNS | Alarms on RDS CPU/Connections, Redis CPU, ECS CPU, ALB health | Real-time email notifications via SNS topic |

---

## 📁 Directory Structure

```
terraform/
├── main.tf                    # Core orchestration: VPC, DB, Redis, EFS, ECS, ALB, Alarms
├── variables.tf               # Fully typed, documented variable definitions with defaults
├── terraform.tfvars           # Active deployment variable values
├── terraform.tfvars.example   # Reference configuration template for dev, stage, prod
├── provider.tf                # AWS, Vault, Random, Time, Null provider configurations
├── outputs.tf                 # Exported endpoints, ARNs, and connection identifiers
├── modules/                   # Internal reusable Terraform modules
│   ├── autoscaling/           # Application AutoScaling scalable targets & policies
│   ├── cloudwatch/            # CloudWatch alarms and log groups
│   ├── efs/                   # EFS file system, mount targets, access points, backup plans
│   ├── elasticache/           # Redis replication group and subnet groups
│   ├── iam/                   # IAM roles and policies with least privilege
│   ├── rds/                   # PostgreSQL RDS instance and parameter groups
│   ├── s3/                    # Secure S3 buckets with policies & lifecycle
│   ├── secrets-manager/       # AWS Secrets Manager secrets
│   ├── security-groups/       # Modular security groups with minimal egress/ingress
│   ├── sns/                   # SNS topics and subscriptions
│   ├── vpc/                   # VPC wrapper around terraform-aws-modules/vpc/aws
│   └── waf/                   # Optional WAFv2 rules for ALB protection
```

---

## 📦 Prerequisites & Requirements

1. **Terraform**: `v1.5.0` or later
2. **AWS CLI**: `v2.x` configured with administrative or pipeline credentials
3. **HashiCorp Vault**: Running instance accessible from where Terraform executes
4. **`jq`** and **`aws-cli`**: Installed locally (used by `local-exec` provisioners)

---

## 🔐 Vault Secrets Setup

The Terraform configuration retrieves sensitive credentials directly from HashiCorp Vault. Before applying Terraform, initialize the required paths in Vault:

### 1. Set Vault Environment Variables

```bash
export VAULT_ADDR="https://vault.yourdomain.com:8200"
export VAULT_TOKEN="s.your-vault-token"
```

### 2. Populate Vault Secrets

```bash
# 1. Metadata Database Credentials (PostgreSQL)
vault kv put secret/rds \
  username="airflow" \
  password="YourStrongRDSMasterPassword123!"

# 2. Redis Authentication Token
vault kv put secret/redis \
  auth_token="YourStrongRedisAuthToken123!"

# 3. Airflow Application Secrets
# Note: Fernet key must be a 32-byte URL-safe base64-encoded string
# Generate with: python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
vault kv put secret/airflow \
  fernet_key="YOUR_GENERATED_FERNET_KEY_HERE=" \
  admin_password="YourInitialAirflowAdminPassword123!"
```

> [!IMPORTANT]
> The database name (`airflow`), RDS username, and passwords stored in Vault will be automatically injected into ECS environment variables via `postgresql+psycopg2://` connection strings.

---

## ⚡ AWS Service Quotas (Fargate vCPUs)

AWS accounts typically have an initial default quota of **8 concurrent vCPUs** for Fargate On-Demand in a region (`fargate/L-3032A538`).

### Default Sizing Budget (Fits within 8 vCPU quota):
* **Webserver**: $2 \times 1024\text{ CPU} = 2\text{ vCPUs}$
* **Scheduler**: $1 \times 1024\text{ CPU} = 1\text{ vCPU}$
* **Worker**: $2 \times 1024\text{ CPU} = 2\text{ vCPUs}$
* **Temporary DB Migration Task**: $1 \times 1024\text{ CPU} = 1\text{ vCPU}$
* **Total Peak Initialization**: $6\text{ vCPUs} \le 8\text{ vCPUs}$ (Fits safely)

### Requesting Quota Increase for Large Scale Production:
If your production deployment requires heavier instances (e.g. 4 vCPU scheduler or 10+ workers):
1. Navigate to **AWS Service Quotas Console** $\to$ **AWS Fargate**.
2. Select **Fargate On-Demand vCPU resource count** (Quota code: `L-3032A538`).
3. Request an increase to **32** or **64** vCPUs.

---

## ⚙️ Configuration & Parameterization

Customize your deployment by creating `terraform.tfvars` from `terraform.tfvars.example`:

```bash
cp terraform.tfvars.example terraform.tfvars
```

### Core Configuration Parameters

| Variable | Description | Type | Default | Production Recommendation |
|----------|-------------|------|---------|---------------------------|
| `project_name` | Name prefix for all resources | `string` | `"ha-airflow"` | Set per workload |
| `environment` | Deployment environment (`prod`, `stage`, `dev`) | `string` | `"prod"` | `"prod"` |
| `region` | Target AWS region | `string` | `"us-east-1"` | Target region |
| `single_nat_gateway` | Use 1 NAT gateway vs 1 per AZ | `bool` | `false` | `false` (HA multi-AZ) |
| `airflow_image` | Docker image for all Airflow components | `string` | `"apache/airflow:2.10.4"` | ECR production image URI |
| `webserver_cpu` | CPU units for webserver task | `number` | `1024` | 1024–2048 |
| `webserver_memory` | Memory (MiB) for webserver task | `number` | `2048` | 2048–4096 |
| `scheduler_cpu` | CPU units for scheduler task | `number` | `1024` | 1024–4096 |
| `scheduler_memory`| Memory (MiB) for scheduler task | `number` | `2048` | 2048–8192 |
| `scheduler_container_cpu` | Scheduler container CPU share | `number` | `768` | Matches task minus sync |
| `scheduler_container_memory` | Scheduler container RAM share | `number` | `1536` | Matches task minus sync |
| `dag_sync_cpu` | S3 DAG sync sidecar CPU share | `number` | `256` | 128–256 |
| `dag_sync_memory` | S3 DAG sync sidecar RAM share | `number` | `512` | 256–512 |
| `worker_cpu` | CPU units for worker tasks | `number` | `1024` | 1024–4096 |
| `worker_memory` | Memory (MiB) for worker tasks | `number` | `2048` | 2048–8192 |
| `worker_concurrency` | Concurrency per worker instance | `number` | `16` | Sized to worker RAM |
| `worker_min_capacity` | Min workers for autoscaling | `number` | `2` | 2–5 |
| `worker_max_capacity` | Max workers for autoscaling | `number` | `10` | 10–50 |
| `db_instance_class` | RDS database instance size | `string` | `"db.r6g.large"` | `"db.r6g.large"` or bigger |
| `db_multi_az` | Enable RDS Multi-AZ replication | `bool` | `true` | `true` |
| `db_deletion_protection` | Prevent accidental DB deletion | `bool` | `false` | `true` for production |
| `db_skip_final_snapshot` | Skip final snapshot on destroy | `bool` | `true` | `false` for production |
| `redis_node_type` | Redis cache node class | `string` | `"cache.t4g.micro"` | `"cache.t4g.medium"` |
| `redis_multi_az_enabled` | Enable Redis Multi-AZ failover | `bool` | `true` | `true` |
| `s3_force_destroy` | Allow bucket destroy with files | `bool` | `true` | `false` for production |
| `alarm_email` | Target email for SNS CloudWatch alerts | `string` | required | Team alerting email |

---

## 🚀 Deployment Step-by-Step

### Step 1: Navigate to the Terraform Directory

All Terraform operations must be run from inside the `terraform/` folder:

```bash
cd terraform/
```

### Step 2: Initialize Terraform

Downloads AWS, Vault, and third-party modules:

```bash
terraform init
```

### Step 3: Validate the Configuration

Ensure syntax and configuration consistency:

```bash
terraform validate
```

### Step 4: Review the Execution Plan

Generate and inspect the deployment plan:

```bash
terraform plan -out=tfplan
```

### Step 5: Apply Infrastructure

Apply the plan to provision the infrastructure:

```bash
terraform apply tfplan
```

### Lifecycle Execution Sequence

```
1. VPC, Subnets, Routing, and Multi-AZ NAT Gateways created
2. KMS Keys, S3 Buckets (DAGs, Logs, ALB Access Logs) created
3. EFS File System, Access Points, and AWS Backup Vault provisioned
4. RDS PostgreSQL 17 Multi-AZ and ElastiCache Redis 7.0 Multi-AZ deployed
5. Application Load Balancer, Listeners, and Target Groups configured
6. ECS Cluster with Fargate Capacity Providers registered
7. null_resource.airflow_db_init runs on-demand Fargate task: "airflow db migrate"
8. null_resource.airflow_create_user creates initial Admin user
9. ECS Services (Webserver, Scheduler, Worker) launch in steady-state
10. CloudWatch Alarms and Application AutoScaling policies attached
```

---

## 🔄 DAG Deployment Workflow

You do **not** need to rebuild Docker containers or redeploy Terraform to update DAGs!

DAG synchronization is automated via S3 and the `s3_dag_sync` sidecar:

```
[Developer / CI/CD] ────► aws s3 sync ./dags/ s3://<s3-dags-bucket-name>/dags/ --delete
                                      │
                                      ▼ (Every 30 seconds)
                       [s3_dag_sync sidecar on Scheduler]
                                      │
                                      ▼
                       [EFS Volume: /opt/airflow/dags]
                                      │
                         ┌────────────┴────────────┐
                         ▼                         ▼
                    [Scheduler]                [Workers]
```

### Sync DAGs using AWS CLI:

```bash
DAGS_BUCKET=$(terraform output -raw s3_dags_bucket_name)

# Upload/Sync DAGs to S3
aws s3 sync ./dags/ s3://${DAGS_BUCKET}/dags/ --delete
```

---

## 📊 Day-2 Operations & Monitoring

### Key Outputs

After deployment, display endpoints:

```bash
terraform output
```

* **Webserver URL**: `terraform output -raw airflow_webserver_url`
* **RDS Endpoint**: `terraform output -raw rds_metadata_db_endpoint`
* **Redis Endpoint**: `terraform output -raw redis_primary_endpoint`
* **EFS ID**: `terraform output -raw efs_dags_file_system_id`

### CloudWatch Log Groups

Inspect live component logs via AWS CLI:

```bash
# Webserver Logs
aws logs tail /aws/ecs/ha-airflow-prod/webserver --follow

# Scheduler Logs
aws logs tail /aws/ecs/ha-airflow-prod/scheduler --follow

# Worker Logs
aws logs tail /aws/ecs/ha-airflow-prod/worker --follow

# Redis Slow Log
aws logs tail /aws/elasticache/ha-airflow-prod-redis/slow-log --follow
```

### Pre-Configured CloudWatch Alarms

1. **RDS High CPU**: Triggers if PostgreSQL CPU $> 80\%$ for 10 minutes.
2. **RDS High Connections**: Triggers if active connections $> 400$.
3. **Redis High CPU**: Triggers if Redis CPU $> 75\%$ for 10 minutes.
4. **Scheduler High CPU**: Triggers if Scheduler CPU $> 80\%$.
5. **ALB Unhealthy Targets**: Triggers immediately if any target fails health checks.

---

## 🛡 Security & Compliance

* **Private VPC Isolation**: All ECS tasks, RDS databases, Redis clusters, and EFS mount targets reside exclusively within private subnets with no public IPs (`assignPublicIp=DISABLED`).
* **Zero Hardcoded Secrets**: Credentials are dynamically extracted from Vault at plan/apply time.
* **Encryption at Rest**:
  * RDS: AES-256 AWS KMS storage encryption.
  * EFS: Dedicated KMS Customer Managed Key with transit encryption enforced (`tls`).
  * S3: AES-256 default encryption with bucket public access blocks enabled.
* **Encryption in Transit**:
  * Redis: In-transit TLS encryption (`transit_encryption_enabled = true`) with token authentication.
  * EFS: TLS encryption enabled on Fargate volume configurations.
* **Least Privilege IAM**: Separate task execution roles and task roles per component.

---

## 🛠 Troubleshooting Runbook

### 1. `db init` fails with `taskId length should be one of [32,36]`
* **Cause**: `aws ecs run-task` failed to place the task (usually due to reaching the Fargate vCPU account limit).
* **Fix**: Check `aws service-quotas list-service-quotas --service-code fargate --region <region>`. Ensure services do not request more vCPUs than your quota allows.

### 2. Container memory or CPU greater than task limit
* **Cause**: Sum of container `cpu` or `memory` values inside a task definition exceeds task-level `cpu` or `memory`.
* **Fix**: Ensure `scheduler_container_cpu + dag_sync_cpu == scheduler_cpu` and `scheduler_container_memory + dag_sync_memory == scheduler_memory`.

### 3. Backup Plan fails with `A Backup vault does not exist`
* **Cause**: Referencing default vault `"Default"` when AWS Backup hasn't been initialized.
* **Fix**: The Terraform configuration automatically provisions a managed dedicated vault (`aws_backup_vault.efs`) and passes `aws_backup_vault.efs.name` directly.

### 4. Airflow Webserver showing 502 Bad Gateway
* **Cause**: Container still initializing or failed health check on `:8080/health`.
* **Fix**:
  ```bash
  aws logs tail /aws/ecs/ha-airflow-prod/webserver --since 15m
  ```
  Ensure database migrations have finished (`airflow-db-init` completed).

---

## 🧹 Teardown & Clean Up

To destroy all provisioned infrastructure:

> [!CAUTION]
> This will permanently destroy the RDS database, Redis cluster, ECS cluster, and all resources.

```bash
terraform destroy
```