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
  description = "IAM role ARN to assume in the workload account"
  type        = string
}

variable "management_role_arn" {
  description = "IAM role ARN to assume in the management account (for TGW route table updates). Set to null for single-account deployments."
  type        = string
  default     = null
}

variable "state_bucket" {
  description = "S3 bucket name for Terraform remote state lookups"
  type        = string
}

variable "env_secondary_cidr" {
  description = "This environment's secondary CIDR (advertised to TGW for cross-VPC routing)"
  type        = string
  default     = "100.64.0.0/16"
}

variable "peer_cidr_blocks" {
  description = "List of peer environment CIDRs to route via TGW (e.g., stage and prod secondary CIDRs)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags. Set Project, Environment, ManagedBy, CostCenter at minimum."
  type        = map(string)
  default     = {}
}
