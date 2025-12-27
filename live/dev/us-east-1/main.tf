
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "${var.name_prefix}-vpc"
  cidr = var.vpc_cidr

  azs = [
    "${var.aws_region}a",
    "${var.aws_region}b",
  ]

  public_subnets = [
    "10.0.0.0/20",
    "10.0.16.0/20",
  ]

  private_subnets = [
    "10.0.32.0/20",
    "10.0.48.0/20",
  ]

  enable_nat_gateway   = true
  single_nat_gateway   = true # cost saver
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Environment = var.env
    Terraform   = "true"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = "${var.name_prefix}-eks"
  kubernetes_version = "1.33"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true

  endpoint_public_access  = true
  endpoint_private_access = true

  # Control-plane logs -> CloudWatch (observability baseline)
  enabled_log_types                      = ["api", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = 14

  eks_managed_node_groups = {
    default = {
      desired_size = 2
      min_size     = 1
      max_size     = 3

      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"

      subnet_ids = module.vpc.private_subnets

      tags = {
        Name        = "${var.name_prefix}-eks-ng-default"
        Environment = var.env
      }
    }
  }

  tags = {
    Environment = var.env
    Terraform   = "true"
  }
}

module "rds" {
  source = "terraform-aws-modules/rds/aws"

  identifier = "${var.name_prefix}-inventory-db"

  engine         = "postgres"
  engine_version = "16.3"
  family         = "postgres16"

  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100

  db_name                     = "jimag_inventory"
  username                    = var.db_username
  manage_master_user_password = true

  multi_az                = false # dev only
  publicly_accessible     = false
  port                    = 5432
  storage_encrypted       = true
  deletion_protection     = false # dev only; prod will be true
  skip_final_snapshot     = true  # dev only; prod will be false
  backup_retention_period = 3

  vpc_security_group_ids = [module.vpc.default_security_group_id]

  subnet_ids = module.vpc.private_subnets

  tags = {
    Environment = var.env
    Terraform   = "true"
  }
}

module "images_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = "${var.name_prefix}-car-images"

  acl                      = null
  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced" # disables ACLs
  block_public_acls        = true                  # helps block any public ACLs
  block_public_policy      = true                  # helps block any public policies
  ignore_public_acls       = true                  # helps ignore any public ACLs
  restrict_public_buckets  = true                  # helps restrict public access
  force_destroy            = true                  # dev: allow bucket delete even with objects
  versioning = {
    enabled = true
  }

  tags = {
    Environment = var.env
    Terraform   = "true"
  }
}


locals {
  # Build full repo names with a prefix, e.g. "jimag-dev-inventory-svc"
  full_repo_names = [
    for r in var.ecr_repos : "${var.name_prefix}-${r}"
  ]
}

module "ecr_repos" {
  source = "../../../terraform/modules/ecr-repo"

  for_each = toset(local.full_repo_names)

  name = each.value
}