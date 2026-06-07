output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "The primary CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "private_subnets" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets
}

output "eks_worker_subnets" {
  description = "List of EKS worker node subnet IDs (from secondary CIDR)"
  value       = module.vpc.elasticache_subnets
}

output "nat_gateway_ids" {
  description = "List of NAT gateway IDs"
  value       = module.vpc.natgw_ids
}
