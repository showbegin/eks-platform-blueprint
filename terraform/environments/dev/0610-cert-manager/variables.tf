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
  description = "cert-manager Helm chart version"
  type        = string
  default     = "v1.20.2"
}

variable "acme_email" {
  description = "Email address for ACME (Let's Encrypt) account registration. Set to null to use self-signed issuer only."
  type        = string
  default     = null
}

variable "acme_server" {
  description = "ACME directory URL. Use staging for dev/stage to avoid Let's Encrypt rate limits."
  type        = string
  default     = "https://acme-staging-v02.api.letsencrypt.org/directory"
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags. Set Project, Environment, ManagedBy, CostCenter at minimum."
  type        = map(string)
  default     = {}
}
