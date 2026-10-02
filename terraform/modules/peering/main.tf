# Same account, same region: the peering is auto-accepted.
resource "aws_vpc_peering_connection" "this" {
  vpc_id      = var.requester_vpc_id
  peer_vpc_id = var.accepter_vpc_id
  auto_accept = true

  tags = { Name = "${var.requester_name}-to-${var.accepter_name}" }
}

# Gateway -> Backend
resource "aws_route" "requester_to_accepter" {
  count = length(var.requester_route_table_ids)

  route_table_id            = var.requester_route_table_ids[count.index]
  destination_cidr_block    = var.accepter_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}

# Backend -> Gateway (return path)
resource "aws_route" "accepter_to_requester" {
  count = length(var.accepter_route_table_ids)

  route_table_id            = var.accepter_route_table_ids[count.index]
  destination_cidr_block    = var.requester_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}

# Security group: backend nodes accept traffic only from the gateway VPC CIDR,
# and only on the NodePort range used by the internal NLB.
resource "aws_vpc_security_group_ingress_rule" "backend_from_gateway" {
  security_group_id = var.backend_security_group_id
  description       = "NodePort traffic from the gateway VPC only (via peering)"

  cidr_ipv4   = var.allowed_source_cidr
  ip_protocol = "tcp"
  from_port   = var.node_port_from
  to_port     = var.node_port_to

  tags = { Name = "backend-from-gateway-vpc" }
}
