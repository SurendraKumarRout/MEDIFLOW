# =============================================================================
# modules/elasticache/main.tf
#
# PURPOSE: Creates AWS ElastiCache Redis for MediFlow Cart Service.
# Cart Service uses Redis to store shopping carts — fast, in-memory storage.
# When Rajesh adds Amoxicillin to cart, it's stored in Redis instantly.
#
# WHY REDIS OUTSIDE EKS?
# Same reason as RDS — data must survive cluster crashes.
# Also, ElastiCache is managed by AWS — no maintenance needed.
# =============================================================================

resource "aws_security_group" "redis" {
  name        = "mediflow-${var.environment}-redis-sg"
  description = "Allow Redis access from EKS nodes only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis port 6379 — from EKS nodes only"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "mediflow-${var.environment}-redis-sg"
    Environment = var.environment
  }
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "mediflow-${var.environment}-redis"
  description          = "Redis for MediFlow ${var.environment} Cart Service"

  node_type = var.redis_node_type
  # dev:     cache.t3.micro  — tiny, cheapest
  # staging: cache.t3.small
  # prod:    cache.t3.medium — handles real cart traffic

  num_cache_clusters = var.environment == "prod" ? 2 : 1
  # prod: 2 nodes (primary + replica) — if primary fails, replica takes over
  # dev/staging: 1 node — cheaper

  port               = 6379
  subnet_group_name  = var.cache_subnet_group_name
  security_group_ids = [aws_security_group.redis.id]

  # Security
  at_rest_encryption_enabled = true  # Encrypt cart data at rest
  transit_encryption_enabled = true  # Encrypt traffic between app and Redis

  # High availability for prod only
  automatic_failover_enabled = var.environment == "prod"

  tags = {
    Name        = "mediflow-${var.environment}-redis"
    Environment = var.environment
  }
}

output "redis_endpoint" {
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
  description = "Redis endpoint — Cart Service connects here"
  sensitive   = true
}
