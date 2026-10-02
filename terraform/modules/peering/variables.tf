variable "requester_name" {
  description = "Name of the requester VPC (used in tags)."
  type        = string
}

variable "accepter_name" {
  description = "Name of the accepter VPC (used in tags)."
  type        = string
}

variable "requester_vpc_id" {
  description = "VPC that initiates the peering (gateway)."
  type        = string
}

variable "accepter_vpc_id" {
  description = "VPC that accepts the peering (backend)."
  type        = string
}

variable "requester_vpc_cidr" {
  description = "CIDR of the requester VPC."
  type        = string
}

variable "accepter_vpc_cidr" {
  description = "CIDR of the accepter VPC."
  type        = string
}

variable "requester_route_table_ids" {
  description = "Route tables in the requester VPC that need a route to the accepter CIDR."
  type        = list(string)
}

variable "accepter_route_table_ids" {
  description = "Route tables in the accepter VPC that need a route back to the requester CIDR."
  type        = list(string)
}

variable "backend_security_group_id" {
  description = "Security group of the backend nodes that receives the cross-VPC ingress rule."
  type        = string
}

variable "allowed_source_cidr" {
  description = "Only this CIDR (the gateway VPC) may reach the backend."
  type        = string
}

variable "node_port_from" {
  description = "Start of the Kubernetes NodePort range targeted by the internal NLB."
  type        = number
  default     = 30000
}

variable "node_port_to" {
  description = "End of the Kubernetes NodePort range targeted by the internal NLB."
  type        = number
  default     = 32767
}
