# =============================================================================
# environments/dev/backend.tf
#
# PURPOSE: Tells Terraform WHERE to store its state file.
# This file connects dev environment to:
#   - S3 bucket (state storage)
#   - DynamoDB table (state locking)
#
# HOW IT WORKS:
# When you run `terraform init`:
#   1. Terraform reads this file
#   2. Connects to S3 bucket mediflow-terraform-state-dev-ACCOUNT_ID
#   3. Connects to DynamoDB table mediflow-terraform-locks
#   4. All state operations now happen remotely
#
# When you run `terraform plan` or `terraform apply`:
#   1. Terraform acquires lock in DynamoDB
#   2. Reads current state from S3
#   3. Compares with desired state (your code)
#   4. Makes changes
#   5. Writes updated state back to S3
#   6. Releases DynamoDB lock
# =============================================================================

terraform {
  backend "s3" {
    bucket         = "mediflow-terraform-state-dev-123456789012" # Replace with your account ID
    key            = "terraform.tfstate"    # Filename inside the S3 bucket
    region         = "ap-south-1"
    dynamodb_table = "mediflow-terraform-locks" # Shared lock table
    encrypt        = true                   # Encrypt state file in transit
  }
}
