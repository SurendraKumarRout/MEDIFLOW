# modules/vpc/variables.tf
# These are the INPUTS to the VPC module
# Dev, staging, prod all pass different values for these variables

variable "environment" {
  description = "Environment name: dev, staging, or prod"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "vpc_cidr" {
  description = <<-EOT
    CIDR block for the entire VPC.
    dev:     10.0.0.0/16
    staging: 10.1.0.0/16
    prod:    10.2.0.0/16
    Different ranges prevent IP conflicts if environments ever connect via VPC peering.
  EOT
  type        = string
}

variable "availability_zones" {
  description = <<-EOT
    List of AWS Availability Zones to use.
    Always use at least 2 for high availability.
    dev/staging: 2 AZs (cost saving)
    prod: 3 AZs (maximum availability)
  EOT
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets — one per availability zone"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets — EKS nodes run here"
  type        = list(string)
}

variable "database_subnet_cidrs" {
  description = "CIDR blocks for database subnets — RDS and ElastiCache run here"
  type        = list(string)
}
