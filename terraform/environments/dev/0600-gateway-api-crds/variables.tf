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

variable "gateway_api_version" {
  description = "Gateway API release version (kubernetes-sigs/gateway-api). Pinned for reproducibility; bump in lockstep with Istio compatibility matrix. See https://github.com/kubernetes-sigs/gateway-api/releases"
  type        = string
  default     = "v1.5.1"
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags."
  type        = map(string)
  default     = {}
}
