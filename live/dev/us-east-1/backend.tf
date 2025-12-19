terraform {
  backend "s3" {
    bucket         = "jimag-terraform-state-dev"          
    key            = "live/dev/us-east-1/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "jimag-terraform-locks-dev"           
    encrypt        = true
  }
}