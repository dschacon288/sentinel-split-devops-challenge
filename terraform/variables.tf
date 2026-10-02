variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "eu-west-2"
}

variable "gateway_vpc_cidr" {
  description = "CIDR of vpc-gateway. Must not overlap with the backend VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "backend_vpc_cidr" {
  description = "CIDR of vpc-backend. Must not overlap with the gateway VPC."
  type        = string
  default     = "10.1.0.0/16"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Adjust if the account/region does not offer this one."
  type        = string
  default     = "1.33"
}

variable "node_instance_type" {
  description = "Instance type for the managed node groups."
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired number of nodes per cluster (spread across 2 AZs)."
  type        = number
  default     = 2
}