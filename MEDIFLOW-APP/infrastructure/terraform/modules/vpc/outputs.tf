# modules/vpc/outputs.tf
# These are the OUTPUTS from the VPC module
# Other modules (EKS, RDS, ElastiCache) use these values

output "vpc_id" {
  value       = aws_vpc.main.id
  description = "VPC ID — passed to EKS, RDS, ElastiCache modules"
}

output "public_subnet_ids" {
  value       = aws_subnet.public[*].id
  description = "Public subnet IDs — used for Load Balancers"
}

output "private_subnet_ids" {
  value       = aws_subnet.private[*].id
  description = "Private subnet IDs — used for EKS worker nodes"
}

output "database_subnet_ids" {
  value       = aws_subnet.database[*].id
  description = "Database subnet IDs — used for RDS and ElastiCache"
}

output "db_subnet_group_name" {
  value       = aws_db_subnet_group.main.name
  description = "RDS subnet group name — passed to RDS module"
}

output "cache_subnet_group_name" {
  value       = aws_elasticache_subnet_group.main.name
  description = "ElastiCache subnet group name — passed to ElastiCache module"
}
