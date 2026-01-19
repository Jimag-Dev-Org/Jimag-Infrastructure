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

variable "github_repos" {
  type        = list(string)
  default     = ["Jimag-Infrastructure", "inventory-svc", "car-website-frontend", "Jimag-GitOps"]
  description = "Infra repo names"
}

variable "allowed_branches" {
  type        = list(string)
  default     = ["develop", "main"]
  description = "Branches allowed to assume the Terraform role"
}