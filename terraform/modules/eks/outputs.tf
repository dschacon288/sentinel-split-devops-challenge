output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "node_security_group_id" {
  description = "EKS-managed cluster security group, attached to the managed nodes."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id

  depends_on = [aws_eks_node_group.this]
}

output "node_role_arn" {
  description = "IAM role ARN used by the nodes."
  value       = aws_iam_role.node.arn
}
