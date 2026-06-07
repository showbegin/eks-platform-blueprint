variable "project_name" {
  description = "Project name used as prefix for resource naming (e.g., 'platform')"
  type        = string
  default     = "platform"
}

variable "aws_region" {
  description = "AWS region for the state bucket and lock table"
  type        = string
  default     = "eu-central-1"
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default     = {}
}
