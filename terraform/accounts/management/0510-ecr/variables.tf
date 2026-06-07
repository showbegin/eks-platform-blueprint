variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "assume_role_arn" {
  description = "IAM role ARN to assume in the management account. Set to null for single-account deployments."
  type        = string
  default     = null
}

variable "repositories" {
  description = <<-EOT
    Map of ECR repositories to create. Key becomes the repository name.

    `tag_prefixes` controls per-service lifecycle retention — each prefix gets
    its own rule keeping the last N images independently (otherwise tag prefix
    lists share a single counter).
  EOT
  type = map(object({
    image_tag_mutability = optional(string, "MUTABLE")
    kms_key_arn          = optional(string, null)
    tag_prefixes         = optional(list(string), [])
  }))

  default = {
    platform-services = {
      tag_prefixes = ["dev-", "stage-", "prod-"]
    }
  }
}

variable "untagged_expiration_days" {
  description = "Expire untagged images after this many days"
  type        = number
  default     = 1
}

variable "images_per_tag_prefix" {
  description = "Keep this many images per tag prefix"
  type        = number
  default     = 10
}

variable "catch_all_expiration_days" {
  description = "Catch-all: expire any image older than this many days"
  type        = number
  default     = 90
}

variable "push_principals" {
  description = "List of IAM principal ARNs (build accounts, CI runners) granted push access"
  type        = list(string)
  default     = []
}

variable "pull_principals" {
  description = "List of IAM principal ARNs (env accounts, EKS node roles) granted pull access"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags. Set Project, Environment, ManagedBy, CostCenter at minimum."
  type        = map(string)
  default     = {}
}
