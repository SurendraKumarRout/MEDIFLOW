# =============================================================================
# modules/rds/main.tf
#
# PURPOSE: Creates PostgreSQL RDS for MediFlow microservices.
# Lives OUTSIDE EKS cluster in database subnets.
#
# WHY OUTSIDE EKS?
# EKS clusters can crash, get deleted, need recreation.
# Customer data (orders, users, payments) must survive that.
# RDS has automatic backups, multi-AZ failover, encryption.
# Even if entire EKS cluster is destroyed, RDS keeps running safely.
#
# WRITING ORDER: Write AFTER VPC module because:
# - RDS needs db_subnet_group_name (from vpc module output)
# - RDS needs security group that references EKS node security group
# =============================================================================

# =============================================================================
# SECURITY GROUP FOR RDS
# Only EKS worker nodes can connect to PostgreSQL
# Nothing else — not your laptop, not the internet, not other AWS services
# =============================================================================
resource "aws_security_group" "rds" {
  name        = "mediflow-${var.environment}-rds-sg"
  description = "Allow PostgreSQL access from EKS worker nodes only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL port 5432 — from EKS nodes only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.eks_node_security_group_id]
    # Only EKS nodes (which run your microservices) can reach the database
    # Even if someone hacks into a public subnet resource, they can't reach RDS
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "mediflow-${var.environment}-rds-sg"
    Environment = var.environment
  }
}

# =============================================================================
# RDS PARAMETER GROUP
# Fine-tune PostgreSQL settings for MediFlow workload
# =============================================================================
resource "aws_db_parameter_group" "postgres" {
  name   = "mediflow-${var.environment}-postgres15"
  family = "postgres15"

  # Log connections — useful for debugging "who connected to the database"
  parameter {
    name  = "log_connections"
    value = "1"
  }

  # Log slow queries
  # Dev: log queries slower than 100ms (aggressive — helps catch issues early)
  # Prod: log queries slower than 1000ms (1 second — only really slow queries)
  parameter {
    name  = "log_min_duration_statement"
    value = var.environment == "prod" ? "1000" : "100"
  }

  tags = {
    Name        = "mediflow-${var.environment}-postgres15"
    Environment = var.environment
  }
}

# =============================================================================
# RDS INSTANCE
# =============================================================================
resource "aws_db_instance" "main" {
  identifier = "mediflow-${var.environment}-postgres"

  # Database engine
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = var.db_instance_class
  # dev:     db.t3.micro  (1 vCPU, 1GB RAM)  — cheapest, fine for dev
  # staging: db.t3.small  (1 vCPU, 2GB RAM)
  # prod:    db.t3.medium (2 vCPU, 4GB RAM)  — handles real traffic

  # Storage
  allocated_storage     = var.db_storage_gb
  max_allocated_storage = var.db_storage_gb * 3 # Auto-expand up to 3x if needed
  storage_type          = "gp3"                  # Latest generation, better performance than gp2
  storage_encrypted     = true                   # Always encrypt data at rest

  # Credentials
  db_name  = "mediflow"         # Initial database name
  username = "mediflow_admin"
  password = var.db_password    # Comes from AWS Secrets Manager (never hardcoded)

  # Networking — where RDS lives
  db_subnet_group_name   = var.db_subnet_group_name   # From VPC module output
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false # NEVER expose RDS to internet — ever

  # High Availability
  multi_az = var.environment == "prod"
  # Prod: Multi-AZ = automatic failover if primary database goes down
  #       AWS automatically promotes standby to primary (typically <60 seconds)
  #       Rajesh's order doesn't fail even if one database server crashes
  # Dev/Staging: Single AZ — cheaper, fine for non-production

  # Backups
  backup_retention_period = var.environment == "prod" ? 30 : 7
  # Prod: Keep 30 days of backups
  # Dev/Staging: Keep 7 days
  backup_window      = "03:00-04:00"      # 3-4 AM IST — lowest traffic time
  maintenance_window = "Mon:04:00-Mon:05:00" # 4-5 AM Monday for patches

  # Parameter group with our custom settings
  parameter_group_name = aws_db_parameter_group.postgres.name

  # Safety
  deletion_protection       = var.environment == "prod" # Can't delete prod DB accidentally
  skip_final_snapshot       = var.environment != "prod" # Take final snapshot when deleting prod
  final_snapshot_identifier = var.environment == "prod" ? "mediflow-prod-final-${formatdate("YYYY-MM-DD", timestamp())}" : null

  tags = {
    Name        = "mediflow-${var.environment}-postgres"
    Environment = var.environment
  }
}

# =============================================================================
# OUTPUTS
# =============================================================================
output "db_endpoint" {
  value       = aws_db_instance.main.endpoint
  description = "RDS endpoint — stored in Kubernetes Secret for microservices to use"
  sensitive   = true
}

output "db_name" {
  value       = aws_db_instance.main.db_name
  description = "Database name"
}
