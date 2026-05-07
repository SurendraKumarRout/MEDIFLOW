# =============================================================================
# modules/vpc/main.tf
#
# PURPOSE: Creates the complete networking foundation for ONE environment.
# Called three times — once each for dev, staging, prod.
# Each call creates a completely isolated network.
#
# WRITING ORDER: Write VPC module FIRST because:
# - EKS needs VPC IDs and subnet IDs
# - RDS needs subnet group (created here)
# - ElastiCache needs subnet group (created here)
# - Everything depends on networking
#
# WHAT GETS CREATED:
# ┌─────────────────────────────────────────────────┐
# │                    VPC                          │
# │  ┌─────────────┐    ┌─────────────┐            │
# │  │Public Subnet│    │Public Subnet│            │
# │  │(Load Balancers, NAT Gateways)  │            │
# │  └──────┬──────┘    └──────┬──────┘            │
# │         │                  │                   │
# │  ┌──────▼──────┐    ┌──────▼──────┐            │
# │  │Private Subnet│   │Private Subnet│           │
# │  │ (EKS Nodes) │   │ (EKS Nodes) │            │
# │  └──────┬──────┘    └──────┬──────┘            │
# │         │                  │                   │
# │  ┌──────▼──────┐    ┌──────▼──────┐            │
# │  │  DB Subnet  │   │  DB Subnet  │            │
# │  │(RDS, Redis) │   │(RDS, Redis) │            │
# │  └─────────────┘    └─────────────┘            │
# └─────────────────────────────────────────────────┘
# =============================================================================

# =============================================================================
# VPC — The isolated network boundary
# =============================================================================
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  # dev:     10.0.0.0/16 — 65,536 IP addresses
  # staging: 10.1.0.0/16
  # prod:    10.2.0.0/16
  # Different ranges prevent IP conflicts if environments ever connect

  enable_dns_hostnames = true # Required for EKS — pods need DNS names
  enable_dns_support   = true # Required for EKS — internal DNS resolution

  tags = {
    Name        = "mediflow-${var.environment}-vpc"
    Environment = var.environment
  }
}

# =============================================================================
# PUBLIC SUBNETS
# Who lives here: Load Balancers, NAT Gateways
# Who does NOT live here: EKS nodes (too exposed), databases (too exposed)
# Internet access: Direct via Internet Gateway
# =============================================================================
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true # Resources here get public IPs automatically

  tags = {
    Name        = "mediflow-${var.environment}-public-${var.availability_zones[count.index]}"
    Environment = var.environment
    # These tags tell EKS which subnets to use for external load balancers
    "kubernetes.io/role/elb"                              = "1"
    "kubernetes.io/cluster/mediflow-${var.environment}"  = "shared"
  }
}

# =============================================================================
# PRIVATE SUBNETS
# Who lives here: EKS worker nodes (where your microservice pods run)
# Internet access: Via NAT Gateway (outbound only — nodes can pull images, call Stripe)
# Nobody from internet can reach nodes directly
# =============================================================================
resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name        = "mediflow-${var.environment}-private-${var.availability_zones[count.index]}"
    Environment = var.environment
    # Tag for internal load balancers (service-to-service traffic)
    "kubernetes.io/role/internal-elb"                     = "1"
    "kubernetes.io/cluster/mediflow-${var.environment}"   = "shared"
  }
}

# =============================================================================
# DATABASE SUBNETS
# Who lives here: RDS PostgreSQL, ElastiCache Redis
# Internet access: NONE — completely isolated, only accessible within VPC
# Only EKS nodes can connect to databases (enforced by security groups)
# =============================================================================
resource "aws_subnet" "database" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.database_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name        = "mediflow-${var.environment}-database-${var.availability_zones[count.index]}"
    Environment = var.environment
  }
}

# =============================================================================
# INTERNET GATEWAY
# The door between your VPC and the public internet
# Only public subnets use this gateway
# =============================================================================
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "mediflow-${var.environment}-igw"
    Environment = var.environment
  }
}

# =============================================================================
# ELASTIC IPs FOR NAT GATEWAYS
# NAT Gateway needs a static public IP address
# One per availability zone — if one AZ goes down, others still work
# =============================================================================
resource "aws_eip" "nat" {
  count  = length(var.availability_zones)
  domain = "vpc"

  tags = {
    Name        = "mediflow-${var.environment}-nat-eip-${count.index + 1}"
    Environment = var.environment
  }

  depends_on = [aws_internet_gateway.main]
}

# =============================================================================
# NAT GATEWAYS
# Allows EKS nodes (private subnet) to reach internet for:
# - Pulling Docker images from ECR
# - Calling external APIs (Stripe payment gateway)
# - Downloading OS updates
#
# Traffic flow: EKS Node → NAT Gateway → Internet Gateway → Internet
# Return traffic: Internet → Internet Gateway → NAT Gateway → EKS Node
# Rajesh can NEVER directly reach an EKS node
# =============================================================================
resource "aws_nat_gateway" "main" {
  count = length(var.availability_zones)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id # NAT lives in PUBLIC subnet

  tags = {
    Name        = "mediflow-${var.environment}-nat-${var.availability_zones[count.index]}"
    Environment = var.environment
  }

  depends_on = [aws_internet_gateway.main]
}

# =============================================================================
# ROUTE TABLES
# Route tables tell traffic WHERE to go
# Each subnet is associated with exactly one route table
# =============================================================================

# Public route table — internet traffic goes via Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"          # All internet traffic
    gateway_id = aws_internet_gateway.main.id # Goes via Internet Gateway
  }

  tags = {
    Name        = "mediflow-${var.environment}-public-rt"
    Environment = var.environment
  }
}

# Private route tables — one per AZ
# Internet traffic goes via NAT Gateway (in same AZ for cost efficiency)
resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = {
    Name        = "mediflow-${var.environment}-private-rt-${var.availability_zones[count.index]}"
    Environment = var.environment
  }
}

# =============================================================================
# ROUTE TABLE ASSOCIATIONS
# Connect each subnet to its route table
# =============================================================================

# Public subnets → public route table
resource "aws_route_table_association" "public" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private subnets → private route tables
resource "aws_route_table_association" "private" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Database subnets → private route tables (no direct internet, via NAT only)
resource "aws_route_table_association" "database" {
  count          = length(var.availability_zones)
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# =============================================================================
# SUBNET GROUPS FOR DATABASES
# RDS and ElastiCache need subnet groups — tells them which subnets to use
# =============================================================================

resource "aws_db_subnet_group" "main" {
  name       = "mediflow-${var.environment}-db-subnet-group"
  subnet_ids = aws_subnet.database[*].id

  tags = {
    Name        = "mediflow-${var.environment}-db-subnet-group"
    Environment = var.environment
  }
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "mediflow-${var.environment}-cache-subnet-group"
  subnet_ids = aws_subnet.database[*].id

  tags = {
    Name        = "mediflow-${var.environment}-cache-subnet-group"
    Environment = var.environment
  }
}
