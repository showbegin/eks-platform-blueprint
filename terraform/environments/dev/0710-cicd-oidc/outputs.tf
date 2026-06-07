output "oidc_provider_arn" {
  description = "ARN of the GitLab OIDC identity provider"
  value       = aws_iam_openid_connect_provider.gitlab.arn
}

output "deploy_role_arn" {
  description = "ARN of the GitLab CI deploy role (set as AWS_ROLE_ARN / DEPLOY_ROLE_NAME in CI)"
  value       = aws_iam_role.deploy.arn
}

output "deploy_role_name" {
  description = "Name of the deploy role"
  value       = aws_iam_role.deploy.name
}

output "ai_review_role_arn" {
  description = "ARN of the Bedrock-only AI MR-review role (null if disabled)"
  value       = var.ai_review_enabled ? aws_iam_role.ai_review[0].arn : null
}

output "github_ai_review_role_arn" {
  description = "ARN of the GitHub Actions Bedrock-only AI-review role (null if disabled)"
  value       = var.github_ai_review_enabled ? aws_iam_role.github_ai_review[0].arn : null
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider (null if disabled)"
  value       = var.github_ai_review_enabled ? aws_iam_openid_connect_provider.github[0].arn : null
}
