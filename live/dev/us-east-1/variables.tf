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
