# -----------------------------------------------------------------------------------------
# Load Balancer Configuration
# -----------------------------------------------------------------------------------------
module "webserver_lb" {
  source                     = "terraform-aws-modules/alb/aws"
  name                       = "airflow-webserver-lb"
  load_balancer_type         = "application"
  vpc_id                     = module.vpc.vpc_id
  subnets                    = module.vpc.public_subnets
  enable_deletion_protection = false
  drop_invalid_header_fields = true
  ip_address_type            = "ipv4"
  internal                   = false
  security_groups = [
    module.airflow_webserver_lb_sg.id
  ]
  access_logs = {
    bucket = "${module.airflow_webserver_lb_logs.bucket}"
  }
  listeners = {
    webserver_lb_http_listener = {
      port     = 80
      protocol = "HTTP"
      forward = {
        target_group_key = "webserver_lb_target_group"
      }
    }
  }
  target_groups = {
    webserver_lb_target_group = {
      backend_protocol = "HTTP"
      backend_port     = 8080
      target_type      = "ip"
      vpc_id           = module.vpc.vpc_id
      stickiness = {
        enabled         = true
        type            = "lb_cookie"
        cookie_duration = 86400
      }
      health_check = {
        enabled             = true
        healthy_threshold   = 3
        interval            = 30
        path                = "/health"
        port                = 8080
        protocol            = "HTTP"
        unhealthy_threshold = 3
      }
      deregistration_delay   = 30
      connection_termination = false
      create_attachment      = false
    }
  }
  tags = {
    Name      = "airflow-webserver-lb"
    Project   = "ha-airflow"
    ManagedBy = "terraform"
  }
  depends_on = [
    module.vpc,
    module.airflow_webserver_lb_sg,
    module.airflow_webserver_lb_logs
  ]
}
