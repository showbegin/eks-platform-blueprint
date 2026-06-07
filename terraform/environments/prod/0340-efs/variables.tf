variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
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

variable "efs_name" {
  description = "Name suffix for the EFS file system (e.g., 'shared', 'monitoring', 'documents')"
  type        = string
  default     = "shared"
}

variable "performance_mode" {
  description = "EFS performance mode: 'generalPurpose' or 'maxIO'"
  type        = string
  default     = "generalPurpose"
}

variable "throughput_mode" {
  description = "EFS throughput mode: 'bursting' or 'elastic' or 'provisioned'"
  type        = string
  default     = "bursting"
}

variable "transition_to_ia" {
  description = "Transition to Infrequent Access after this period of inactivity"
  type        = string
  default     = "AFTER_30_DAYS"
  validation {
    condition = contains([
      "AFTER_7_DAYS", "AFTER_14_DAYS", "AFTER_30_DAYS",
      "AFTER_60_DAYS", "AFTER_90_DAYS"
    ], var.transition_to_ia)
    error_message = "transition_to_ia must be one of: AFTER_7_DAYS, AFTER_14_DAYS, AFTER_30_DAYS, AFTER_60_DAYS, AFTER_90_DAYS."
  }
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags. Set Project, Environment, ManagedBy, CostCenter at minimum."
  type        = map(string)
  default     = {}
}
