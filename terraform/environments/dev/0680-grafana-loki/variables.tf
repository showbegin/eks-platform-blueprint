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

variable "chart_version" {
  description = "loki-stack Helm chart version. NOTE: loki-stack is in maintenance mode; consider migrating to the modern grafana/loki chart (7.x) in a future revision."
  type        = string
  default     = "2.10.3"
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags. Set Project, Environment, ManagedBy, CostCenter at minimum."
  type        = map(string)
  default     = {}
}
