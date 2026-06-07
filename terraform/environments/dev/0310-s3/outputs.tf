output "bucket_names" {
  description = "Map of bucket key → bucket name"
  value       = { for k, v in aws_s3_bucket.this : k => v.id }
}

output "bucket_arns" {
  description = "Map of bucket key → bucket ARN"
  value       = { for k, v in aws_s3_bucket.this : k => v.arn }
}

output "bucket_domain_names" {
  description = "Map of bucket key → bucket regional domain name"
  value       = { for k, v in aws_s3_bucket.this : k => v.bucket_regional_domain_name }
}
