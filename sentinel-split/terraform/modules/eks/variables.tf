variable "cluster_name" {
  description = "EKS cluster name (eks-gateway or eks-backend). Also used as the IAM role name prefix, which must start with 'eks-'."
  type        = string

  validation {
    condition     = startswith(var.cluster_name, "eks-")
    error_message = "Cluster name must start with 'eks-' so the derived IAM roles match the allowed prefix."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version of the control plane."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs (at least two AZs) for the control plane ENIs and the node group."
  type        = list(string)
}

variable "node_instance_type" {
  description = "EC2 instance type of the managed node group."
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired node count."
  type        = number
  default     = 2
}
