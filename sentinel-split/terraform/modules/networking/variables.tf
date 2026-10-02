variable "name" {
  description = "Name of the VPC (e.g. vpc-gateway)."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster that will live in this VPC; used to tag subnets for load balancer discovery."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC (a /16 is expected)."
  type        = string
}

variable "azs" {
  description = "Availability Zones to use. One private and one public subnet is created per AZ (minimum 2)."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "At least two Availability Zones are required."
  }
}
