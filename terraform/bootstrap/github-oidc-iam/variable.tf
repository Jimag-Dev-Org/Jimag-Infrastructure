variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for the bootstrap IAM resources"
}

variable "github_org" {
  type        = string
  default     = "Jimag-Dev-Org"
  description = "GitHub organization that owns the infra repo"
}

variable "github_repo" {
  type        = string
  default     = "Jimag-Infrastructure"
  description = "Infra repo name"
}

variable "allowed_branches" {
  type        = list(string)
  default     = ["develop", "main"]
  description = "Branches allowed to assume the Terraform role"
}