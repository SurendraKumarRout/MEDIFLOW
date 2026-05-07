# =============================================================================
# environments/dev/main.tf
#
# PURPOSE: Creates complete MediFlow DEV environment by calling all modules.
# This file is the "orchestrator" — it calls VPC, EKS, RDS, ElastiCache modules
# and passes dev-specific values (small instances, low cost settings).
#
# DEPENDENCY FLOW (Terraform figures this out automatically):
# bootstrap → S3 + DynamoDB exist
# vpc module → VPC + subnets + networking exists
# eks module → reads vpc outputs → EKS cluster exists
# rds module → reads vpc + eks outputs → Database exists
# elasticache module → reads vpc + eks outputs → Redis exists
#
# TO DEPLOY DEV:
#   cd infrastructure/terraform/environments/dev
#   terraform init     ← connects to S3 backend, downloads modules
#   terraform plan     ← shows what will be created (ALWAYS review first)
#   terraform apply    ← creates everything (takes ~20 minutes)
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Backend config is in backend.tf
}

# =============================================================================
# AWS PROVIDER — HOW JENKINS AUTHENTICATES
# =============================================================================
# Jenkins runs on EC2 instance with IAM Role attached.
# AWS automatically provides temporary credentials via instance metadata.
# Terraform picks them up — no hardcoded keys anywhere.
#
# For local development: run `aws configure` first.
# =============================================================================
provider "aws" {
  region = "ap-south-1"

  default_tags {
    tags = {
      Project     = "mediflow"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

# =============================================================================
# STEP 1: VPC MODULE — Create networking foundation FIRST
# Everything else depends on this
# =============================================================================
module "vpc" {
  source = "../../modules/vpc"

  environment = "dev"
  vpc_cidr    = "10.0.0.0/16" # Dev uses 10.0.x.x range

  availability_zones = ["ap-south-1a", "ap-south-1b"] # 2 AZs for dev

  # Public subnets — load balancers go here
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]

  # Private subnets — EKS nodes go here
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

  # Database subnets — RDS and Redis go here
  database_subnet_cidrs = ["10.0.20.0/24", "10.0.21.0/24"]
}

# =============================================================================
# STEP 2: EKS MODULE — Create Kubernetes cluster
# Uses VPC outputs: vpc_id, private_subnet_ids, public_subnet_ids
# =============================================================================
module "eks" {
  source = "../../modules/eks"

  environment = "dev"

  # VPC details — from VPC module outputs
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids

  kubernetes_version = "1.29"

  # Dev uses small, cheap instances
  node_instance_type = "t3.medium" # 2 vCPU, 4GB RAM
  node_desired_count = 2            # 2 nodes normally
  node_min_count     = 1            # Can scale down to 1 if idle (saves money)
  node_max_count     = 3            # Can scale up to 3 under load
}

# =============================================================================
# STEP 3: RDS MODULE — Create PostgreSQL database
# Uses VPC outputs: vpc_id, db_subnet_group_name
# Uses EKS outputs: node_security_group_id (so only EKS nodes can connect)
# =============================================================================
module "rds" {
  source = "../../modules/rds"

  environment = "dev"

  vpc_id                     = module.vpc.vpc_id
  db_subnet_group_name       = module.vpc.db_subnet_group_name
  eks_node_security_group_id = module.eks.node_security_group_id

  # Dev uses smallest, cheapest instance
  db_instance_class = "db.t3.micro"
  db_storage_gb     = 20

  # In real setup: fetch from AWS Secrets Manager
  # aws secretsmanager get-secret-value --secret-id mediflow/dev/db-password
  db_password = var.db_password
}

# =============================================================================
# STEP 4: ELASTICACHE MODULE — Create Redis for Cart Service
# Uses VPC outputs: vpc_id, cache_subnet_group_name
# Uses EKS outputs: node_security_group_id
# =============================================================================
module "elasticache" {
  source = "../../modules/elasticache"

  environment = "dev"

  vpc_id                     = module.vpc.vpc_id
  cache_subnet_group_name    = module.vpc.cache_subnet_group_name
  eks_node_security_group_id = module.eks.node_security_group_id

  redis_node_type = "cache.t3.micro" # Smallest for dev
}

# =============================================================================
# ECR REPOSITORIES — Docker image registry for all 7 services
# Jenkins pushes images here. EKS pulls images from here.
# ECR is shared across environments — no need to create per environment
# (Only create in dev environment, staging/prod use same repos)
# =============================================================================
locals {
  services = [
    "user-service",
    "product-service",
    "cart-service",
    "order-service",
    "payment-service",
    "inventory-service",
    "notification-service"
  ]
}

resource "aws_ecr_repository" "services" {
  for_each = toset(local.services)

  name                 = "mediflow/${each.value}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true # Automatically scan for security vulnerabilities
  }

  tags = {
    Name    = "mediflow/${each.value}"
    Service = each.value
  }
}

# =============================================================================
# OUTPUTS — Jenkins reads these to connect to the cluster
# =============================================================================
output "eks_cluster_name" {
  value       = module.eks.cluster_name
  description = "Jenkins runs: aws eks update-kubeconfig --name <this value>"
}

output "eks_cluster_endpoint" {
  value       = module.eks.cluster_endpoint
  description = "Kubernetes API server — Jenkins kubectl commands go here"
}

output "rds_endpoint" {
  value       = module.rds.db_endpoint
  description = "PostgreSQL endpoint — stored in Kubernetes Secret for microservices"
  sensitive   = true
}

output "redis_endpoint" {
  value       = module.elasticache.redis_endpoint
  description = "Redis endpoint — Cart Service connects here"
  sensitive   = true
}

output "ecr_repository_urls" {
  value = {
    for k, v in aws_ecr_repository.services : k => v.repository_url
  }
  description = "ECR URLs — Jenkins tags and pushes images to these URLs"
}
