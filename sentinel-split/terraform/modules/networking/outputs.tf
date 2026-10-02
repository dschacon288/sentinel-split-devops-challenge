output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "private_subnet_ids" {
  description = "Private subnet IDs. Waits for the NAT route so nodes launched in them have outbound access."
  value       = aws_subnet.private[*].id

  depends_on = [
    aws_route.private_nat,
    aws_route_table_association.private,
  ]
}

output "public_subnet_ids" {
  description = "Public subnet IDs (NAT Gateway and internet-facing load balancers only)."
  value       = aws_subnet.public[*].id
}

output "private_route_table_id" {
  description = "Route table shared by the private subnets."
  value       = aws_route_table.private.id
}

output "public_route_table_id" {
  description = "Route table shared by the public subnets."
  value       = aws_route_table.public.id
}
