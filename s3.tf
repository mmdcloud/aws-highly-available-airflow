# -----------------------------------------------------------------------------------------
# S3 Configuration
# -----------------------------------------------------------------------------------------
module "airflow_logs_bucket" {
  source             = "./modules/s3"
  bucket_name        = "airflow-logs-bucket-${random_id.id.hex}"
  objects            = []
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  bucket_policy = ""
  force_destroy = true
  bucket_notification = {
    queue           = []
    lambda_function = []
  }
  tags = {
    Name      = "airflow-logs-bucket-${random_id.id.hex}"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

module "airflow_dags_bucket" {
  source             = "./modules/s3"
  bucket_name        = "airflow-dags-bucket-${random_id.id.hex}"
  objects            = []
  versioning_enabled = "Enabled"
  cors               = []
  bucket_policy      = ""
  force_destroy      = true
  bucket_notification = {
    queue           = []
    lambda_function = []
  }
  tags = {
    Name      = "airflow-dags-bucket-${random_id.id.hex}"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}

module "airflow_webserver_lb_logs" {
  source             = "./modules/s3"
  bucket_name        = "airflow-webserver-lb-logs-${random_id.id.hex}"
  objects            = []
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    },
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSLogDeliveryWrite"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::airflow-webserver-lb-logs-${random_id.id.hex}/*"
      },
      {
        Sid    = "AWSLogDeliveryAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = "arn:aws:s3:::airflow-webserver-lb-logs-${random_id.id.hex}"
      },
      {
        Sid    = "AWSELBAccountWrite"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_elb_service_account.main.id}:root"
        }
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::airflow-webserver-lb-logs-${random_id.id.hex}/*"
      }
    ]
  })
  force_destroy = true
  bucket_notification = {
    queue           = []
    lambda_function = []
  }
  tags = {
    Name      = "airflow-webserver-lb-logs-${random_id.id.hex}"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
}