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

variable "repository_names" {
  description = "ECR repository names to create. Default matches the CI single-repo pattern (ECR_REPO_NAME)."
  type        = list(string)
  default     = ["platform-services"]
}

variable "image_tag_mutability" {
  description = "MUTABLE or IMMUTABLE. IMMUTABLE is safer for prod; MUTABLE eases the demo flow."
  type        = string
  default     = "MUTABLE"
}

variable "untagged_expiry_days" {
  description = "Expire untagged images after this many days."
  type        = number
  default     = 14
}

variable "force_delete" {
  description = "Allow `terraform destroy` to delete repositories that still contain images. Useful for PoC teardown."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags."
  type        = map(string)
  default     = {}
}
