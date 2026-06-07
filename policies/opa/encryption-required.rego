# Encryption-at-rest policy
#
# Enforces that data stores use encryption at rest. Catches the most common
# "we'll add encryption later" oversights before they reach production.

package terraform.encryption

import input.resource_changes as resource_changes

skip(rc) {
	rc.change.actions == ["delete"]
}

# S3 buckets must have server-side encryption configured (separate resource:
# aws_s3_bucket_server_side_encryption_configuration). We check that the
# bucket has at least one SSE config in the same plan.
deny[msg] {
	rc := resource_changes[_]
	rc.type == "aws_s3_bucket"
	not skip(rc)
	bucket_address := rc.address
	not has_sse_for_bucket(bucket_address)
	msg := sprintf("S3 bucket %s has no server-side encryption configured", [bucket_address])
}

has_sse_for_bucket(bucket_address) {
	sse := resource_changes[_]
	sse.type == "aws_s3_bucket_server_side_encryption_configuration"
}

# RDS instances must have storage_encrypted = true
deny[msg] {
	rc := resource_changes[_]
	rc.type == "aws_db_instance"
	not skip(rc)
	rc.change.after.storage_encrypted != true
	msg := sprintf("RDS instance %s does not have storage_encrypted = true", [rc.address])
}

# Aurora clusters must have storage_encrypted = true
deny[msg] {
	rc := resource_changes[_]
	rc.type == "aws_rds_cluster"
	not skip(rc)
	rc.change.after.storage_encrypted != true
	msg := sprintf("Aurora cluster %s does not have storage_encrypted = true", [rc.address])
}

# EBS volumes must be encrypted
deny[msg] {
	rc := resource_changes[_]
	rc.type == "aws_ebs_volume"
	not skip(rc)
	rc.change.after.encrypted != true
	msg := sprintf("EBS volume %s is not encrypted", [rc.address])
}

# EFS must have encryption
deny[msg] {
	rc := resource_changes[_]
	rc.type == "aws_efs_file_system"
	not skip(rc)
	rc.change.after.encrypted != true
	msg := sprintf("EFS %s is not encrypted", [rc.address])
}
