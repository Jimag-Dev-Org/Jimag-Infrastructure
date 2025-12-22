env         = "dev"
aws_region  = "us-east-1"
name_prefix = "jimag-dev"
ecr_repos   = ["inventory-svc", "car-website-frontend"]

vpc_cidr         = "10.0.0.0/16"
db_username      = "jimag_dev"
db_password      = "CHANGE-ME-STRONG-PASSWORD"
root_domain_name = "example.com" # <-- replace with your real hosted zone later
app_subdomain    = "dev"