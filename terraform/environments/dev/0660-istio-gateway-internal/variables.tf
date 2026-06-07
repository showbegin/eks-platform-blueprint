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

# NOTE on chart_version removal:
#   Same architectural shift as module 0650 — the gateway is now a Gateway API
#   `Gateway` resource auto-provisioned by Istio's controller, not a Helm chart.
#   See 0650/variables.tf for full rationale. Data-plane image version follows
#   istiod's chart_version (module 0640).

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate for TLS termination at the internal LoadBalancer. Set to null for HTTP-only evaluation."
  type        = string
  default     = null
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags."
  type        = map(string)
  default     = {}
}
