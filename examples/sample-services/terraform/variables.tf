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

variable "bucket_suffix" {
  description = "Suffix appended to environment for the demo S3 bucket name"
  type        = string
  default     = "sample-processed"
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags."
  type        = map(string)
  default     = {}
}
