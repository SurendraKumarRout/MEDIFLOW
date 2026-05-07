# =============================================================================
# modules/eks/main.tf
#
# PURPOSE: Creates a fully functional EKS Kubernetes cluster for ONE environment.
# This is where your 7 MediFlow microservices actually run as pods.
#
# WRITING ORDER: Write AFTER VPC module because:
# - EKS needs VPC ID (from vpc module output)
# - EKS needs subnet IDs (from vpc module output)
#
# WHAT GETS CREATED:
# - IAM Role for EKS control plane (AWS manages master nodes on your behalf)
# - IAM Role for worker nodes (nodes need permission to join cluster, pull images)
# - Security Groups (firewall rules for cluster and nodes)
# - EKS Cluster (Kubernetes control plane — AWS manages this, you don't touch it)
# - Node Group (EC2 instances that run your pods — you manage these)
# - EKS Add-ons (CoreDNS, kube-proxy, VPC CNI — essential components)
# =============================================================================

# =============================================================================
# IAM ROLE FOR EKS CONTROL PLANE
# AWS needs permission to manage the Kubernetes control plane on your behalf
# This is NOT for your application code — it's for AWS internal management
# =============================================================================
resource "aws_iam_role" "eks_cluster" {
  name = "mediflow-${var.environment}-eks-cluster-role"

  # Trust policy — allows EKS service to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "mediflow-${var.environment}-eks-cluster-role"
    Environment = var.environment
  }
}

# Attach AWS managed policy — gives EKS permission to:
# - Create/manage EC2 instances for nodes
# - Configure networking (ENIs, security groups)
# - Write CloudWatch logs
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# =============================================================================
# IAM ROLE FOR WORKER NODES
# EC2 instances (worker nodes) need permission to:
# - Join the EKS cluster
# - Pull Docker images from ECR (where Jenkins pushes images)
# - Write application logs to CloudWatch
# =============================================================================
resource "aws_iam_role" "eks_nodes" {
  name = "mediflow-${var.environment}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "mediflow-${var.environment}-eks-node-role"
    Environment = var.environment
  }
}

# Minimum required policies for worker nodes
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  # CNI = Container Network Interface — gives pods their own IP addresses
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  # Allows nodes to pull Docker images from ECR
  # Jenkins pushes images, nodes pull images
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "cloudwatch_logs" {
  # Allows pods to send logs to CloudWatch
  # Your Order Service, Payment Service logs go here
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.eks_nodes.name
}

# =============================================================================
# SECURITY GROUP FOR EKS CLUSTER CONTROL PLANE
# =============================================================================
resource "aws_security_group" "eks_cluster" {
  name        = "mediflow-${var.environment}-eks-cluster-sg"
  description = "Security group for EKS cluster control plane communication"
  vpc_id      = var.vpc_id

  # Allow all outbound traffic from control plane
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "mediflow-${var.environment}-eks-cluster-sg"
    Environment = var.environment
  }
}

# =============================================================================
# SECURITY GROUP FOR WORKER NODES
# =============================================================================
resource "aws_security_group" "eks_nodes" {
  name        = "mediflow-${var.environment}-eks-nodes-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  # Nodes can talk to each other (pod-to-pod communication)
  # When Order Service pod calls Payment Service pod, this rule allows it
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true # Allow traffic from other nodes in same security group
  }

  # Nodes accept traffic from EKS control plane
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  # Nodes can reach internet (via NAT Gateway — for ECR pulls, Stripe API calls)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "mediflow-${var.environment}-eks-nodes-sg"
    Environment = var.environment
  }
}

# =============================================================================
# EKS CLUSTER — The Kubernetes Control Plane
# AWS manages: API server, etcd (state store), scheduler, controller manager
# You manage: Worker nodes, what runs on them
# =============================================================================
resource "aws_eks_cluster" "main" {
  name     = "mediflow-${var.environment}"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids = concat(
      var.private_subnet_ids, # Worker nodes in private subnets
      var.public_subnet_ids   # Load balancers in public subnets
    )
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_private_access = true  # Jenkins (inside VPC) can reach API server privately
    endpoint_public_access  = var.environment != "prod"
    # Dev/Staging: Public API endpoint enabled (easier for learning/debugging)
    # Prod: Disabled — API server only accessible from within VPC (more secure)
  }

  # Enable control plane logging to CloudWatch
  # Helps debug Kubernetes issues
  enabled_cluster_log_types = [
    "api",               # API server requests
    "audit",             # Who did what (security audit trail)
    "authenticator",     # Authentication attempts
    "controllerManager", # Kubernetes controller decisions
    "scheduler"          # Pod scheduling decisions
  ]

  tags = {
    Name        = "mediflow-${var.environment}"
    Environment = var.environment
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# =============================================================================
# EKS NODE GROUP — The Worker Nodes (EC2 instances that run your pods)
# AWS manages: node replacement, updates, auto-scaling
# You define: instance type, count, scaling limits
# =============================================================================
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "mediflow-${var.environment}-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = var.private_subnet_ids # Nodes in PRIVATE subnets — never public

  instance_types = [var.node_instance_type]
  # dev:     t3.medium  (2 vCPU, 4GB RAM)  — cheap, enough for dev
  # staging: t3.large   (2 vCPU, 8GB RAM)
  # prod:    t3.xlarge  (4 vCPU, 16GB RAM) — handles real customer load

  scaling_config {
    desired_size = var.node_desired_count # How many nodes normally running
    min_size     = var.node_min_count     # Never go below this
    max_size     = var.node_max_count     # Never go above this (cost control)
    # dev:     desired=2, min=1, max=3
    # staging: desired=2, min=2, max=4
    # prod:    desired=3, min=3, max=10 (can scale to 10 on Black Friday)
  }

  update_config {
    max_unavailable = 1 # During updates, take down max 1 node at a time
    # This ensures your services keep running during node updates
  }

  tags = {
    Name        = "mediflow-${var.environment}-node"
    Environment = var.environment
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ecr_read_only,
  ]
}

# =============================================================================
# EKS ADD-ONS — Essential components every EKS cluster needs
# =============================================================================

# VPC CNI — Gives each pod its own IP address from your VPC subnet
# When Order Service pod starts, it gets a real VPC IP like 10.0.10.45
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"
}

# CoreDNS — Internal DNS for service discovery
# When Order Service calls "http://payment-service:3004", CoreDNS resolves it
# to the actual pod IP. This is how microservices find each other.
resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"

  depends_on = [aws_eks_node_group.main] # CoreDNS needs nodes to run on
}

# kube-proxy — Handles network routing rules on each node
# Maintains iptables rules that route service traffic to correct pods
resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"
}
