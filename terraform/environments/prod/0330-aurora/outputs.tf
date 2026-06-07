output "cluster_endpoint" {
  description = "Aurora cluster writer endpoint (use for writes — apps should prefer the proxy)"
  value       = aws_rds_cluster.aurora.endpoint
}

output "cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint (load-balanced across readers)"
  value       = aws_rds_cluster.aurora.reader_endpoint
}

output "proxy_endpoint" {
  description = "RDS Proxy endpoint — recommended connection target for applications"
  value       = aws_db_proxy.aurora.endpoint
}

output "cluster_security_group_id" {
  description = "Aurora cluster security group ID"
  value       = aws_security_group.aurora.id
}

output "proxy_security_group_id" {
  description = "RDS Proxy security group ID"
  value       = aws_security_group.rds_proxy.id
}

output "master_secret_arn" {
  description = "Secrets Manager ARN for the master credentials"
  value       = aws_secretsmanager_secret.master.arn
}

output "app_user_secret_arns" {
  description = "Map of app username → Secrets Manager ARN"
  value       = { for k, v in aws_secretsmanager_secret.app_user : k => v.arn }
}
