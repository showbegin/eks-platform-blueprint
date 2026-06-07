output "bastion_public_ip" {
  description = "Public IP of the bastion host"
  value       = aws_instance.bastion.public_ip
}

output "bastion_security_group_id" {
  description = "Security group ID of the bastion (use for RDS/OpenSearch ingress rules)"
  value       = aws_security_group.bastion.id
}

output "bastion_instance_id" {
  description = "EC2 instance ID of the bastion"
  value       = aws_instance.bastion.id
}

output "bastion_role_arn" {
  description = "IAM role ARN of the bastion. Add to EKS module's access_entries to grant cluster access."
  value       = aws_iam_role.bastion.arn
}

output "bastion_role_name" {
  description = "IAM role name of the bastion."
  value       = aws_iam_role.bastion.name
}
