# =============================================================================
# environments/prod/main.tf
# PRODUCTION — Real customers, real money. Handle with extreme care.
# ALWAYS run terraform plan and get approval before terraform apply.
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
    tags = { Project = "mediflow", Environment = "prod", ManagedBy = "terraform" }
  }
}

module "vpc" {
  source             = "../../modules/vpc"
  environment        = "prod"
  vpc_cidr           = "10.2.0.0/16" # Prod uses 10.2.x.x

  # 3 AZs for prod — maximum high availability
  # If one AZ goes down (rare but happens), 2 others keep serving Rajesh
  availability_zones = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]

  public_subnet_cidrs   = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
  private_subnet_cidrs  = ["10.2.10.0/24", "10.2.11.0/24", "10.2.12.0/24"]
  database_subnet_cidrs = ["10.2.20.0/24", "10.2.21.0/24", "10.2.22.0/24"]
}

module "eks" {
  source             = "../../modules/eks"
  environment        = "prod"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  public_subnet_ids  = module.vpc.public_subnet_ids
  kubernetes_version = "1.29"

  # Prod uses larger instances to handle real customer load
  node_instance_type = "t3.xlarge" # 4 vCPU, 16GB RAM
  node_desired_count = 3            # Always 3 nodes running
  node_min_count     = 3            # Never go below 3 (high availability)
  node_max_count     = 10           # Scale to 10 on Black Friday spikes
}

module "rds" {
  source                     = "../../modules/rds"
  environment                = "prod"
  vpc_id                     = module.vpc.vpc_id
  db_subnet_group_name       = module.vpc.db_subnet_group_name
  eks_node_security_group_id = module.eks.node_security_group_id

  db_instance_class = "db.t3.medium" # Handles real traffic
  db_storage_gb     = 100
  db_password       = var.db_password
  # Multi-AZ and deletion protection are automatically enabled for prod in the module
}

module "elasticache" {
  source                     = "../../modules/elasticache"
  environment                = "prod"
  vpc_id                     = module.vpc.vpc_id
  cache_subnet_group_name    = module.vpc.cache_subnet_group_name
  eks_node_security_group_id = module.eks.node_security_group_id
  redis_node_type            = "cache.t3.medium"
  # 2 Redis nodes (primary + replica) are automatically configured for prod in the module
}

variable "db_password" { type = string; sensitive = true }

output "eks_cluster_name" { value = module.eks.cluster_name }
output "rds_endpoint" { value = module.rds.db_endpoint; sensitive = true }
output "redis_endpoint" { value = module.elasticache.redis_endpoint; sensitive = true }
