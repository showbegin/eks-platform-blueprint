output "queue_urls" {
  description = "Map of queue key → SQS queue URL"
  value       = { for k, v in aws_sqs_queue.main : k => v.url }
}

output "queue_arns" {
  description = "Map of queue key → SQS queue ARN"
  value       = { for k, v in aws_sqs_queue.main : k => v.arn }
}

output "dlq_urls" {
  description = "Map of queue key → DLQ URL"
  value       = { for k, v in aws_sqs_queue.dlq : k => v.url }
}

output "irsa_role_arns" {
  description = "Map of queue key → IRSA role ARN (only for queues with service_account configured)"
  value       = { for k, v in module.irsa : k => v.arn }
}
