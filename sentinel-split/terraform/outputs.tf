output "region" {
  value = var.region
}

output "gateway_cluster_name" {
  value = module.gateway_eks.cluster_name
}

output "backend_cluster_name" {
  value = module.backend_eks.cluster_name
}

output "gateway_vpc_id" {
  value = module.gateway_network.vpc_id
}

output "backend_vpc_id" {
  value = module.backend_network.vpc_id
}

output "gateway_vpc_cidr" {
  value = module.gateway_network.vpc_cidr
}

output "backend_vpc_cidr" {
  value = module.backend_network.vpc_cidr
}

output "peering_connection_id" {
  value = module.peering.peering_connection_id
}
