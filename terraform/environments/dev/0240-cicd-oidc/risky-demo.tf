# DEMO ONLY — intentionally risky change to exercise the AI PR reviewer. Do not merge.
resource "aws_iam_role_policy" "node_wildcard" {
  name   = "node-extra"
  role   = "dev-node-role"
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "*", Resource = "*" }] })
}
resource "aws_security_group_rule" "world_open" {
  type = "ingress", from_port = 0, to_port = 0, protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"], security_group_id = "sg-deadbeef"
}
