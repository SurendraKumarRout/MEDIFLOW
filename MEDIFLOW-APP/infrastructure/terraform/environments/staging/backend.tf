# environments/staging/backend.tf
terraform {
  backend "s3" {
    bucket         = "mediflow-terraform-state-staging-123456789012"
    key            = "terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "mediflow-terraform-locks"
    encrypt        = true
  }
}
