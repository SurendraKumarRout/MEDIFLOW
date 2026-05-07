# modules/rds/variables.tf

variable "environment" { type = string }
variable "vpc_id" { type = string }

variable "db_subnet_group_name" {
  type        = string
  description = "From vpc module output — tells RDS which subnets to use"
}

variable "eks_node_security_group_id" {
  type        = string
  description = "From eks module output — only EKS nodes can access RDS"
}

variable "db_instance_class" {
  type        = string
  description = "RDS instance size — dev: db.t3.micro, prod: db.t3.medium"
}

variable "db_storage_gb" {
  type        = number
  description = "Initial storage in GB — dev: 20, prod: 100"
}

variable "db_password" {
  type        = string
  sensitive   = true
  description = "Database password — comes from AWS Secrets Manager, never hardcoded"
}
