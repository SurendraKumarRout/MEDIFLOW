# modules/elasticache/variables.tf

variable "environment" { type = string }
variable "vpc_id" { type = string }

variable "cache_subnet_group_name" {
  type        = string
  description = "From vpc module output"
}

variable "eks_node_security_group_id" {
  type        = string
  description = "From eks module output — only EKS nodes can access Redis"
}

variable "redis_node_type" {
  type        = string
  description = "ElastiCache node size — dev: cache.t3.micro, prod: cache.t3.medium"
}
