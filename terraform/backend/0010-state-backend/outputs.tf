output "state_bucket_name" {
  description = "S3 bucket name for Terraform state"
  value       = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  description = "S3 bucket ARN for Terraform state"
  value       = aws_s3_bucket.state.arn
}

output "lock_table_name" {
  description = "DynamoDB table name for state locking"
  value       = aws_dynamodb_table.locks.name
}

output "lock_table_arn" {
  description = "DynamoDB table ARN for state locking"
  value       = aws_dynamodb_table.locks.arn
}

output "aws_region" {
  description = "AWS region where state infrastructure lives"
  value       = var.aws_region
}
