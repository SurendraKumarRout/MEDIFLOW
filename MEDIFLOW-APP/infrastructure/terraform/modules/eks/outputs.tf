# modules/eks/outputs.tf

output "cluster_name" {
  value       = aws_eks_cluster.main.name
  description = "EKS cluster name — Jenkins uses this to configure kubectl"
}

output "cluster_endpoint" {
  value       = aws_eks_cluster.main.endpoint
  description = "Kubernetes API server endpoint — Jenkins connects here to deploy"
}

output "cluster_certificate_authority" {
  value       = aws_eks_cluster.main.certificate_authority[0].data
  description = "CA certificate for authenticating with cluster"
  sensitive   = true
}

output "node_security_group_id" {
  value       = aws_security_group.eks_nodes.id
  description = "Security group of worker nodes — RDS uses this to allow connections from nodes only"
}

output "cluster_oidc_issuer_url" {
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
  description = "OIDC URL — used for IRSA (IAM Roles for Service Accounts)"
}
