variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name (dev, stage, prod)"
  type        = string
  default     = "dev"
}

variable "assume_role_arn" {
  description = "IAM role ARN to assume for cross-account access. Set to null for single-account deployments."
  type        = string
  default     = null
}

variable "state_bucket" {
  description = "S3 bucket name for Terraform remote state lookups"
  type        = string
}

variable "queues" {
  description = <<-EOT
    Map of SQS queues to create. Each queue gets a paired DLQ and an IAM policy
    granting standard producer/consumer actions. If `service_account` is set,
    an IRSA role is also created and bound to that service account.
  EOT
  type = map(object({
    visibility_timeout_seconds = optional(number, 30)
    message_retention_seconds  = optional(number, 345600) # 4 days
    max_receive_count          = optional(number, 5)
    kms_master_key_id          = optional(string, null)
    service_account = optional(object({
      namespace = string
      name      = string
    }), null)
  }))

  default = {
    example = {
      visibility_timeout_seconds = 60
      service_account = {
        namespace = "default"
        name      = "queue-consumer"
      }
    }
  }
}

variable "alert_email" {
  description = "Email address for DLQ alarm notifications. Set to null to skip SNS alerting."
  type        = string
  default     = null
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags. Set Project, Environment, ManagedBy, CostCenter at minimum."
  type        = map(string)
  default     = {}
}
