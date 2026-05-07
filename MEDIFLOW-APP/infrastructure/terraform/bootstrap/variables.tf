# bootstrap/variables.tf

variable "aws_region" {
  description = "AWS region for MediFlow infrastructure"
  type        = string
  default     = "ap-south-1" # Mumbai — closest to MediFlow's Indian customers
}

variable "account_id" {
  description = <<-EOT
    Your AWS account ID — makes S3 bucket names globally unique.
    Get it by running: aws sts get-caller-identity --query Account --output text
  EOT
  type        = string
}
