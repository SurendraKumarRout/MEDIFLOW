# environments/dev/variables.tf

variable "db_password" {
  type        = string
  sensitive   = true
  description = "RDS master password — never hardcode this, use Secrets Manager"
}
