output "rds_endpoint" {
  description = "RDS endpoint (hostname:port)"
  value       = aws_db_instance.this.endpoint
}

output "rds_address" {
  description = "RDS hostname"
  value       = aws_db_instance.this.address
}

output "rds_port" {
  description = "RDS port"
  value       = aws_db_instance.this.port
}

output "rds_security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}

output "rds_db_name" {
  description = "Initial database name"
  value       = aws_db_instance.this.db_name
}
