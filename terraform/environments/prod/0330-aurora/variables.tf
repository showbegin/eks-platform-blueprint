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

variable "engine_version" {
  description = "Aurora PostgreSQL engine version"
  type        = string
  default     = "17.6"
}

variable "instance_class" {
  description = "Aurora instance class"
  type        = string
  default     = "db.r6g.large"
}

variable "instance_count" {
  description = "Number of Aurora instances (1 writer + N readers; minimum 2 for HA)"
  type        = number
  default     = 3
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "postgres"
}

variable "master_username" {
  description = "Aurora cluster master username"
  type        = string
  default     = "platform_admin"
}

variable "master_password_ssm_path" {
  description = "SSM Parameter Store path for the master password (SecureString)"
  type        = string
  default     = "/platform/prod/0330-aurora/master_password"
}

variable "app_users" {
  description = "List of application user names — each gets its own Secrets Manager secret and RDS Proxy auth entry. Passwords loaded from SSM at {app_password_ssm_prefix}/{username}."
  type        = list(string)
  default     = []
}

variable "app_password_ssm_prefix" {
  description = "SSM Parameter Store path prefix for app user passwords. Each user reads from {prefix}/{username}."
  type        = string
  default     = "/platform/prod/0330-aurora/app_passwords"
}

variable "backup_retention_period" {
  description = "Backup retention in days (35 = 5 weeks for PITR)"
  type        = number
  default     = 35
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags. Set Project, Environment, ManagedBy, CostCenter at minimum."
  type        = map(string)
  default     = {}
}
