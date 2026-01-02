variable "env" {
  description = "Environment name na this (e.g. dev, preprod, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names in this env."
  type        = string
}

variable "ecr_repos" {
  description = "List of logical ECR repos for this env."
  type        = list(string)
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}




variable "root_domain_name" {
  description = "Root Route53 hosted zone name, e.g. example.com"
  type        = string
}

variable "app_subdomain" {
  description = "Subdomain for the app in this env, e.g. dev"
  type        = string
  default     = "dev"
}

variable "db_username" {
  description = "Username for rds db"
  type        = string
  default     = "jimagorg"
}