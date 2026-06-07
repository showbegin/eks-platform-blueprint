output "queue_url" {
  description = "SQS queue URL — pass to producer/consumer as SQS_QUEUE_URL"
  value       = data.terraform_remote_state.messaging.outputs.queue_urls[local.queue_key]
}

output "queue_arn" {
  description = "SQS queue ARN"
  value       = local.queue_arn
}

output "bucket_name" {
  description = "S3 bucket — pass to consumer as S3_BUCKET"
  value       = aws_s3_bucket.processed.id
}

output "producer_role_arn" {
  description = "IRSA role ARN for the producer ServiceAccount"
  value       = module.producer_irsa.arn
}

output "consumer_role_arn" {
  description = "IRSA role ARN for the consumer ServiceAccount"
  value       = module.consumer_irsa.arn
}

output "deploy_command_producer" {
  description = "helm upgrade command for the producer"
  value = join(" ", [
    "helm upgrade --install sample-producer ../../../helm/microservice-chart",
    "-f ../../sample-producer/helm-values.yaml",
    "--namespace sample-producer --create-namespace",
    "--set environment=${var.environment}",
    "--set serviceAccount.roleArn=${module.producer_irsa.arn}",
    "--set extraEnv.SQS_QUEUE_URL=${data.terraform_remote_state.messaging.outputs.queue_urls[local.queue_key]}",
  ])
}

output "deploy_command_consumer" {
  description = "helm upgrade command for the consumer"
  value = join(" ", [
    "helm upgrade --install sample-consumer ../../../helm/microservice-chart",
    "-f ../../sample-consumer/helm-values.yaml",
    "--namespace sample-consumer --create-namespace",
    "--set environment=${var.environment}",
    "--set serviceAccount.roleArn=${module.consumer_irsa.arn}",
    "--set extraEnv.SQS_QUEUE_URL=${data.terraform_remote_state.messaging.outputs.queue_urls[local.queue_key]}",
    "--set extraEnv.S3_BUCKET=${aws_s3_bucket.processed.id}",
  ])
}
