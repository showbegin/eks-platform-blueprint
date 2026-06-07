output "repository_urls" {
  description = "Map of repository name → repository URL (use as ECR_REGISTRY base)"
  value       = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "repository_arns" {
  description = "Map of repository name → repository ARN"
  value       = { for k, v in aws_ecr_repository.this : k => v.arn }
}
