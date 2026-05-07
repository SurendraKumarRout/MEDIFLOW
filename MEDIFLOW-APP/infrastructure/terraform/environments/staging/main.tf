# =============================================================================
# environments/staging/main.tf
# Mirrors production settings — same structure as prod but slightly smaller
# Used for final testing before code goes to real customers
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "ap-south-1"
  default_tags {
    tags = { Project = "mediflow", Environment = "staging", ManagedBy = "terraform" }
  }
}

module "vpc" {
  source             = "../../modules/vpc"
  environment        = "staging"
  vpc_cidr           = "10.1.0.0/16" # Staging uses 10.1.x.x — different from dev (10.0) and prod (10.2)
  availability_zones = ["ap-south-1a", "ap-south-1b"]

  public_subnet_cidrs   = ["10.1.1.0/24", "10.1.2.0/24"]
  private_subnet_cidrs  = ["10.1.10.0/24", "10.1.11.0/24"]
  database_subnet_cidrs = ["10.1.20.0/24", "10.1.21.0/24"]
}

module "eks" {
  source             = "../../modules/eks"
  environment        = "staging"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
  kubernetes_version = "1.29"

  node_instance_type = "t3.large" # Bigger than dev, mirrors prod closely
  node_desired_count = 2
  node_min_count     = 2
  node_max_count     = 4
}

module "rds" {
  source                     = "../../modules/rds"
  environment                = "staging"
  vpc_id                     = module.vpc.vpc_id
  db_subnet_group_name       = module.vpc.db_subnet_group_name
  eks_node_security_group_id = module.eks.node_security_group_id
  db_instance_class          = "db.t3.small"
  db_storage_gb              = 50
  db_password                = var.db_password
}

module "elasticache" {
  source                     = "../../modules/elasticache"
  environment                = "staging"
  vpc_id                     = module.vpc.vpc_id
  cache_subnet_group_name    = module.vpc.cache_subnet_group_name
  eks_node_security_group_id = module.eks.node_security_group_id
  redis_node_type            = "cache.t3.small"
}

variable "db_password" { type = string; sensitive = true }

output "eks_cluster_name" { value = module.eks.cluster_name }
output "rds_endpoint" { value = module.rds.db_endpoint; sensitive = true }
output "redis_endpoint" { value = module.elasticache.redis_endpoint; sensitive = true }
