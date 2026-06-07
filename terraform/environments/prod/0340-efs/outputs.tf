output "efs_id" {
  description = "EFS file system ID"
  value       = aws_efs_file_system.this.id
}

output "efs_arn" {
  description = "EFS file system ARN"
  value       = aws_efs_file_system.this.arn
}

output "efs_dns_name" {
  description = "EFS DNS name (use as NFS mount target hostname)"
  value       = aws_efs_file_system.this.dns_name
}

output "efs_security_group_id" {
  description = "EFS mount target security group ID"
  value       = aws_security_group.efs.id
}

output "mount_target_ids" {
  description = "List of mount target IDs (one per AZ)"
  value       = aws_efs_mount_target.this[*].id
}
