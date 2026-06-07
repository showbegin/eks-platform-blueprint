# Network rules policy
#
# Catches common networking footguns:
#   - Security groups with 0.0.0.0/0 ingress on non-standard ports
#   - RDS instances marked publicly_accessible
#   - EKS clusters with public endpoint without endpoint_public_access_cidrs

package terraform.network

import input.resource_changes as resource_changes

skip(rc) {
	rc.change.actions == ["delete"]
}

# Allowed public ingress ports (HTTP, HTTPS) — extend if you have IPv6/HTTP3 needs
allowed_public_ports := {80, 443}

deny[msg] {
	rc := resource_changes[_]
	rc.type == "aws_security_group_rule"
	not skip(rc)
	rule := rc.change.after
	rule.type == "ingress"
	cidr := rule.cidr_blocks[_]
	cidr == "0.0.0.0/0"
	not allowed_public_ports[rule.from_port]
	msg := sprintf("Security group rule %s allows 0.0.0.0/0 on port %d (non-HTTP/HTTPS)", [rc.address, rule.from_port])
}

# Same check for embedded ingress rules in aws_security_group resources
deny[msg] {
	rc := resource_changes[_]
	rc.type == "aws_security_group"
	not skip(rc)
	ingress := rc.change.after.ingress[_]
	cidr := ingress.cidr_blocks[_]
	cidr == "0.0.0.0/0"
	not allowed_public_ports[ingress.from_port]
	msg := sprintf("Security group %s ingress rule allows 0.0.0.0/0 on port %d", [rc.address, ingress.from_port])
}

# RDS must not be publicly accessible
deny[msg] {
	rc := resource_changes[_]
	rc.type == "aws_db_instance"
	not skip(rc)
	rc.change.after.publicly_accessible == true
	msg := sprintf("RDS instance %s is publicly_accessible — should be private", [rc.address])
}

# EKS API endpoint should not be wide-open public
deny[msg] {
	rc := resource_changes[_]
	rc.type == "aws_eks_cluster"
	not skip(rc)
	vpc := rc.change.after.vpc_config[_]
	vpc.endpoint_public_access == true
	count(vpc.public_access_cidrs) == 0
	msg := sprintf("EKS cluster %s has public endpoint with no CIDR restriction", [rc.address])
}
