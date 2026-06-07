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

variable "vpc_cidr" {
  description = "Primary VPC CIDR block for infrastructure subnets"
  type        = string
  default     = "10.0.0.0/16"
}

variable "secondary_cidr_blocks" {
  description = "Secondary CIDR blocks (typically for EKS worker nodes)"
  type        = list(string)
  default     = ["100.64.0.0/16"]
}

variable "availability_zones" {
  description = "List of AZs to use"
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b"]
}

variable "private_subnets" {
  description = "Private subnet CIDRs (from primary CIDR)"
  type        = list(string)
  default     = ["10.0.31.0/24", "10.0.32.0/24"]
}

variable "public_subnets" {
  description = "Public subnet CIDRs (from primary CIDR)"
  type        = list(string)
  default     = ["10.0.131.0/24", "10.0.132.0/24"]
}

variable "eks_worker_subnets" {
  description = "EKS worker node subnet CIDRs (from secondary CIDR)"
  type        = list(string)
  default     = ["100.64.0.0/20", "100.64.16.0/20"]
}

variable "one_nat_gateway_per_az" {
  description = "Deploy one NAT gateway per AZ (true for HA, false for cost savings)"
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway (cost-optimized for dev/stage)"
  type        = bool
  default     = true
}

variable "enable_vpn_gateway" {
  description = "Enable VPN gateway for cross-VPC or on-prem connectivity"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags. Set Project, Environment, ManagedBy, CostCenter at minimum."
  type        = map(string)
  default     = {}
}
