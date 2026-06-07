output "tgw_attachment_id" {
  description = "Transit Gateway VPC attachment ID"
  value       = aws_ec2_transit_gateway_vpc_attachment.this.id
}
