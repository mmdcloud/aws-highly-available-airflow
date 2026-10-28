# -----------------------------------------------------------------------------------------
# Auto Scaling Configuration
# -----------------------------------------------------------------------------------------
module "airflow_webserver_autoscaling_policy" {
  source             = "./modules/autoscaling"
  min_capacity       = 2
  max_capacity       = 10
  resource_id        = "service/${module.ha_airflow_ecs_cluster.cluster_name}/${module.ha_airflow_ecs_cluster.services["webserver"].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  policies = [
    {
      name        = "worker-scale-up"
      policy_type = "StepScaling"
      step_scaling_policy_configuration = {
        adjustment_type         = "ChangeInCapacity"
        cooldown                = 60
        metric_aggregation_type = "Average"
        step_adjustment = [
          {
            metric_interval_lower_bound = 0
            metric_interval_upper_bound = 20
            scaling_adjustment          = 1
          },
          {
            metric_interval_lower_bound = 20
            scaling_adjustment          = 2
          }
        ]
      }
    },
    {
      name        = "webserver-scale-down"
      policy_type = "StepScaling"
      step_scaling_policy_configuration = {
        adjustment_type         = "ChangeInCapacity"
        cooldown                = 300
        metric_aggregation_type = "Average"
        step_adjustment = [
          {
            metric_interval_upper_bound = 0
            scaling_adjustment          = -1
          }
        ]
      }
    }
  ]
}

module "airflow_scheduler_autoscaling_policy" {
  source             = "./modules/autoscaling"
  min_capacity       = 1
  max_capacity       = 1
  resource_id        = "service/${module.ha_airflow_ecs_cluster.cluster_name}/${module.ha_airflow_ecs_cluster.services["scheduler"].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  policies = []
}

module "airflow_worker_autoscaling_policy" {
  source             = "./modules/autoscaling"
  min_capacity       = 2
  max_capacity       = 10
  resource_id        = "service/${module.ha_airflow_ecs_cluster.cluster_name}/${module.ha_airflow_ecs_cluster.services["worker"].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
  policies = [
    {
      name        = "worker-scale-up"
      policy_type = "StepScaling"
      step_scaling_policy_configuration = {
        adjustment_type         = "ChangeInCapacity"
        cooldown                = 60
        metric_aggregation_type = "Average"
        step_adjustment = [
          {
            metric_interval_lower_bound = 0
            metric_interval_upper_bound = 20
            scaling_adjustment          = 1
          },
          {
            metric_interval_lower_bound = 20
            scaling_adjustment          = 2
          }
        ]
      }
    },
    {
      name        = "worker-scale-down"
      policy_type = "StepScaling"
      step_scaling_policy_configuration = {
        adjustment_type         = "ChangeInCapacity"
        cooldown                = 300
        metric_aggregation_type = "Average"
        step_adjustment = [
          {
            metric_interval_upper_bound = 0
            scaling_adjustment          = -1
          }
        ]
      }
    }
  ]
}