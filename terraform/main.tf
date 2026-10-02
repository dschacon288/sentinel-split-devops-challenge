data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# ---------------------------------------------------------------- Networking

module "gateway_network" {
  source = "./modules/networking"

  name         = "vpc-chacon-gateway"
  cluster_name = "eks-chacon-gateway"
  vpc_cidr     = var.gateway_vpc_cidr
  azs          = local.azs
}

module "backend_network" {
  source = "./modules/networking"

  name         = "vpc-chacon-backend"
  cluster_name = "eks-chacon-backend"
  vpc_cidr     = var.backend_vpc_cidr
  azs          = local.azs
}

# ---------------------------------------------------------------------- EKS

module "gateway_eks" {
  source = "./modules/eks"

  cluster_name       = "eks-chacon-gateway"
  kubernetes_version = var.kubernetes_version
  subnet_ids         = module.gateway_network.private_subnet_ids
  node_instance_type = var.node_instance_type
  node_desired_size  = var.node_desired_size
}

module "backend_eks" {
  source = "./modules/eks"

  cluster_name       = "eks-chacon-backend"
  kubernetes_version = var.kubernetes_version
  subnet_ids         = module.backend_network.private_subnet_ids
  node_instance_type = var.node_instance_type
  node_desired_size  = var.node_desired_size
}

# ------------------------------------------------- Peering, routes, SG rules
# run actions . 

module "peering" {
  source = "./modules/peering"

  requester_name = "vpc-chacon-gateway"
  accepter_name  = "vpc-chacon-backend"

  requester_vpc_id = module.gateway_network.vpc_id
  accepter_vpc_id  = module.backend_network.vpc_id

  requester_vpc_cidr = module.gateway_network.vpc_cidr
  accepter_vpc_cidr  = module.backend_network.vpc_cidr

  requester_route_table_ids = [
    module.gateway_network.private_route_table_id,
    module.gateway_network.public_route_table_id,
  ]
  accepter_route_table_ids = [
    module.backend_network.private_route_table_id,
    module.backend_network.public_route_table_id,
  ]

  # Only the gateway VPC may reach the backend nodes (NodePort range used by
  # the internal NLB that fronts the backend service).
  backend_security_group_id = module.backend_eks.node_security_group_id
  allowed_source_cidr       = module.gateway_network.vpc_cidr
}
