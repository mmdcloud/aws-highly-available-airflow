variable "max_capacity" {}
variable "min_capacity" {}
variable "resource_id" {}
variable "scalable_dimension" {}
variable "service_namespace" {}
variable "policies" {
  type = object({
    name        = string
    policy_type = string
    step_scaling_policy_configuration = optional(object({
      adjustment_type          = string
      cooldown                 = number
      metric_aggregation_type  = string
      min_adjustment_magnitude = number
      step_adjustment = list(object({
        metric_interval_lower_bound = number
        metric_interval_upper_bound = number
        scaling_adjustment          = number
      }))
    }))
    predictive_scaling_policy_configuration = optional(object({
      metric_specification = object({
        target_value = number
        predefined_metric_pair_specification = object({
          predefined_metric_type = string
          resource_label         = string
        })
      })
      max_capacity_buffer          = number
      mode                         = string
      scheduling_buffer_time       = number
      max_capacity_breach_behavior = string
    }))
    target_tracking_scaling_policy_configuration = optional(object({
      predefined_metric_specification = object({
        predefined_metric_type = string
        resource_label         = string
      })
      target_value       = number
      disable_scale_in   = bool
      scale_in_cooldown  = number
      scale_out_cooldown = number
    }))
  })
}