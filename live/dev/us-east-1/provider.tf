terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "6.27.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  # No static creds here –
  # Locally you'll use your AWS_PROFILE / env vars,
  # In CI, aws-actions/configure-aws-credentials will inject short-lived creds.
}