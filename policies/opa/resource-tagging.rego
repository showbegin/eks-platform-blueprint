# Resource tagging policy
#
# Ensures every taggable AWS resource has the required tags. Without these,
# cost reports cannot attribute resources, audit logs cannot identify owners,
# and orphan resources accumulate.
#
# Apply via conftest:
#   conftest test plans/*.json --policy policies/opa/

package terraform.tagging

import input.resource_changes as resource_changes

required_tags := ["Project", "Environment", "ManagedBy"]

# Resource types that AWS supports tagging on. Not exhaustive — extend as needed.
taggable_types := {
	"aws_s3_bucket",
	"aws_db_instance",
	"aws_rds_cluster",
	"aws_eks_cluster",
	"aws_eks_node_group",
	"aws_instance",
	"aws_ebs_volume",
	"aws_efs_file_system",
	"aws_lb",
	"aws_sqs_queue",
	"aws_kms_key",
	"aws_ecr_repository",
	"aws_route53_zone",
	"aws_vpc",
	"aws_subnet",
	"aws_security_group",
}

# Skip resources being destroyed
skip(rc) {
	rc.change.actions == ["delete"]
}

deny[msg] {
	rc := resource_changes[_]
	taggable_types[rc.type]
	not skip(rc)
	required := required_tags[_]
	not has_tag(rc, required)
	msg := sprintf("%s [%s] missing required tag: %s", [rc.type, rc.address, required])
}

# A resource has a tag if it appears in either tags or tags_all (provider-injected)
has_tag(rc, key) {
	rc.change.after.tags[key]
}

has_tag(rc, key) {
	rc.change.after.tags_all[key]
}
