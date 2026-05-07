# =============================================================================
# bootstrap/main.tf
#
# PURPOSE: This is the VERY FIRST thing you run before anything else.
# It creates two things:
#   1. S3 buckets (to store Terraform state files for each environment)
#   2. DynamoDB table (to prevent two people running Terraform simultaneously)
#
# WHY BOOTSTRAP SEPARATELY?
# Terraform needs S3 to store its state. But S3 doesn't exist yet.
# Chicken-and-egg problem. So we create S3 manually using LOCAL state first.
# After this runs ONCE, all other Terraform code uses S3 as the backend.
#
# HOW TO RUN (one time only):
#   cd infrastructure/terraform/bootstrap
#   terraform init
#   terraform apply
# =============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # NOTE: No backend block here — bootstrap uses LOCAL state intentionally
  # This is the only Terraform code that uses local state
}

# =============================================================================
# HOW TERRAFORM AUTHENTICATES WITH AWS
# =============================================================================
# Option 1 — Local development (your laptop):
#   Run: aws configure
#   Enter your IAM user access key and secret key
#   Terraform picks up credentials from ~/.aws/credentials automatically
#
# Option 2 — Jenkins CI/CD (production):
#   Jenkins runs on an EC2 instance
#   That EC2 instance has an IAM Role attached to it
#   AWS automatically provides temporary credentials via instance metadata
#   Terraform uses those credentials — NO hardcoded keys anywhere
#   This is the SECURE production way
# =============================================================================

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "mediflow"
      ManagedBy = "terraform"
    }
  }
}

# =============================================================================
# S3 BUCKETS FOR TERRAFORM STATE
# One bucket per environment — complete isolation
# =============================================================================

locals {
  environments = ["dev", "staging", "prod"]
}

# Create one S3 bucket per environment
resource "aws_s3_bucket" "terraform_state" {
  for_each = toset(local.environments)

  bucket = "mediflow-terraform-state-${each.value}-${var.account_id}"
  # Example: mediflow-terraform-state-dev-123456789012
  # Account ID makes it globally unique (S3 bucket names are global)

  lifecycle {
    prevent_destroy = true # Prevent accidental deletion of state buckets
  }

  tags = {
    Name        = "mediflow-terraform-state-${each.value}"
    Environment = each.value
    Purpose     = "Terraform remote state storage"
  }
}

# Enable versioning on each bucket
# Why: If state file gets corrupted, you can restore a previous version
resource "aws_s3_bucket_versioning" "terraform_state" {
  for_each = toset(local.environments)

  bucket = aws_s3_bucket.terraform_state[each.value].id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encrypt state files at rest
# Why: State files contain sensitive info — DB passwords, API keys, secrets
# Anyone who reads the state file unencrypted gets all your secrets
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  for_each = toset(local.environments)

  bucket = aws_s3_bucket.terraform_state[each.value].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # AWS managed encryption key
    }
  }
}

# Block ALL public access
# Why: State files must NEVER be publicly readable
# Even if someone misconfigures bucket policy, public access is still blocked
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  for_each = toset(local.environments)

  bucket = aws_s3_bucket.terraform_state[each.value].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 storage class is STANDARD by default
# Why Standard: Terraform accesses state file every single run
# Glacier/Deep Archive have retrieval delays — Terraform would hang waiting
# Standard = immediate access, right tool for frequent access patterns

# Bucket policy — only Jenkins IAM role can access state buckets
resource "aws_s3_bucket_policy" "terraform_state" {
  for_each = toset(local.environments)

  bucket = aws_s3_bucket.terraform_state[each.value].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowJenkinsAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:role/mediflow-jenkins-role"
        }
        Action = [
          "s3:GetObject",      # Read state file
          "s3:PutObject",      # Write state file
          "s3:DeleteObject",   # Delete old state versions
          "s3:ListBucket",     # List bucket contents
          "s3:GetBucketVersioning" # Check versioning status
        ]
        Resource = [
          "arn:aws:s3:::mediflow-terraform-state-${each.value}-${var.account_id}",
          "arn:aws:s3:::mediflow-terraform-state-${each.value}-${var.account_id}/*"
        ]
      },
      {
        Sid    = "AllowAdminAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.account_id}:user/mediflow-terraform-admin"
        }
        Action   = "s3:*" # Admin has full access for emergency fixes
        Resource = [
          "arn:aws:s3:::mediflow-terraform-state-${each.value}-${var.account_id}",
          "arn:aws:s3:::mediflow-terraform-state-${each.value}-${var.account_id}/*"
        ]
      },
      {
        Sid       = "DenyEverythingElse"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          "arn:aws:s3:::mediflow-terraform-state-${each.value}-${var.account_id}",
          "arn:aws:s3:::mediflow-terraform-state-${each.value}-${var.account_id}/*"
        ]
        Condition = {
          StringNotLike = {
            "aws:PrincipalArn" = [
              "arn:aws:iam::${var.account_id}:role/mediflow-jenkins-role",
              "arn:aws:iam::${var.account_id}:user/mediflow-terraform-admin"
            ]
          }
        }
      }
    ]
  })
}

# =============================================================================
# DYNAMODB TABLE FOR STATE LOCKING
# ONE shared table for all environments — locks are temporary and auto-cleaned
# Why one table: Locks are just temporary entries. No persistent data to isolate.
# Terraform includes environment name in LockID — no collision possible.
# =============================================================================

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "mediflow-terraform-locks"
  billing_mode = "PAY_PER_REQUEST" # Pay only when used — cheapest for infrequent lock operations
  hash_key     = "LockID"          # Terraform REQUIRES this exact key name

  attribute {
    name = "LockID"
    type = "S" # String type
  }

  # Encrypt lock data at rest
  server_side_encryption {
    enabled = true
  }

  # Point-in-time recovery — restore table if accidentally deleted
  point_in_time_recovery {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name    = "mediflow-terraform-locks"
    Purpose = "Terraform state locking for all environments"
  }
}

# =============================================================================
# OUTPUTS — Save these values, you'll need them in backend.tf files
# =============================================================================

output "state_bucket_names" {
  value = {
    for env in local.environments :
    env => aws_s3_bucket.terraform_state[env].id
  }
  description = "S3 bucket names per environment — use in backend.tf"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.terraform_locks.name
  description = "DynamoDB table name — use in backend.tf of all environments"
}
