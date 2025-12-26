terraform {
  backend "s3" {
    bucket         = "jimag-terraform-state-dev"
    key            = "bootstrap/github-oidc-iam.tfstate"
    region         = "us-east-1"
    dynamodb_table = "jimag-terraform-locks-dev"
    encrypt        = true
  }
}