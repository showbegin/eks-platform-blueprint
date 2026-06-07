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

variable "project_name" {
  description = "Project name prefix for bucket naming (e.g., 'platform' → buckets named 'platform-dev-{key}')"
  type        = string
  default     = "platform"
}

variable "buckets" {
  description = "Map of buckets to create. Key becomes the bucket suffix."
  type = map(object({
    purpose            = string
    versioning_enabled = optional(bool, true)
    kms_key_arn        = optional(string, null)
    lifecycle_rules = optional(list(object({
      id                                 = string
      expiration_days                    = optional(number)
      noncurrent_version_expiration_days = optional(number)
      transition_to_glacier_days         = optional(number)
    })), null)
  }))

  default = {
    documents = {
      purpose            = "Application document storage (versioned, encrypted)"
      versioning_enabled = true
      lifecycle_rules = [
        {
          id                                 = "expire-old-versions"
          noncurrent_version_expiration_days = 90
        }
      ]
    }
    logs = {
      purpose            = "Application logs (no versioning, transition to Glacier after 30 days)"
      versioning_enabled = false
      lifecycle_rules = [
        {
          id                         = "archive-old-logs"
          transition_to_glacier_days = 30
          expiration_days            = 365
        }
      ]
    }
  }
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags. Set Project, Environment, ManagedBy, CostCenter at minimum."
  type        = map(string)
  default     = {}
}
