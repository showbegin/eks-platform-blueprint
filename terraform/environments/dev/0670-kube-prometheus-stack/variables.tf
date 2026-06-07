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
  description = "kube-prometheus-stack chart version"
  type        = string
  default     = "86.1.0"
}

variable "grafana_admin_password" {
  description = "Initial admin password for Grafana. Rotate after first login."
  type        = string
  sensitive   = true
}

variable "prometheus_retention" {
  description = "Prometheus metrics retention duration"
  type        = string
  default     = "30d"
}

variable "prometheus_storage_size" {
  description = "Persistent volume size for Prometheus"
  type        = string
  default     = "50Gi"
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags. Set Project, Environment, ManagedBy, CostCenter at minimum."
  type        = map(string)
  default     = {}
}
