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

variable "ssh_public_key" {
  description = "SSH public key for bastion access"
  type        = string
}

variable "allowed_ssh_cidrs" {
  description = "CIDRs allowed to SSH into the bastion"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "instance_type" {
  description = "EC2 instance type for the bastion"
  type        = string
  default     = "t3.micro"
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags. Set Project, Environment, ManagedBy, CostCenter at minimum."
  type        = map(string)
  default     = {}
}
