# environments/prod/backend.tf
terraform {
  backend "s3" {
    bucket         = "mediflow-terraform-state-prod-123456789012"
    key            = "terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "mediflow-terraform-locks"
    encrypt        = true
  }
}
