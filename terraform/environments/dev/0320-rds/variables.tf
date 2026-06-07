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

variable "db_password_ssm_path" {
  description = "SSM Parameter Store path holding the DB password (SecureString)"
  type        = string
  default     = "/platform/dev/0320-rds/db_password"
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "postgres"
}

variable "db_username" {
  description = "Master DB username"
  type        = string
  default     = "platform_admin"
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.medium"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GB"
  type        = number
  default     = 100
}

variable "max_allocated_storage" {
  description = "Max storage with autoscaling (GB)"
  type        = number
  default     = 1000
}

variable "backup_retention_period" {
  description = "Backup retention period in days (0 disables automated backups)"
  type        = number
  default     = 7
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot on destroy (set to false in prod)"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection (set to true in prod)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags. Set Project, Environment, ManagedBy, CostCenter at minimum."
  type        = map(string)
  default     = {}
}
