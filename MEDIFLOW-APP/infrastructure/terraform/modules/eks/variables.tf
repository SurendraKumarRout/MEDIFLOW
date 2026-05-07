# modules/eks/variables.tf

variable "environment" {
  type = string
}

variable "vpc_id" {
  type        = string
  description = "VPC ID — comes from vpc module output"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs — EKS nodes run here (from vpc module output)"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs — load balancers go here (from vpc module output)"
}

variable "kubernetes_version" {
  type        = string
  default     = "1.29"
  description = "Kubernetes version for EKS cluster"
}

variable "node_instance_type" {
  type        = string
  description = "EC2 instance type for worker nodes — dev: t3.medium, prod: t3.xlarge"
}

variable "node_desired_count" {
  type        = number
  description = "Normal number of worker nodes"
}

variable "node_min_count" {
  type        = number
  description = "Minimum number of worker nodes (never scale below this)"
}

variable "node_max_count" {
  type        = number
  description = "Maximum number of worker nodes (never scale above this)"
}
