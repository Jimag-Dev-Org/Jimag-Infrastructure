
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

  addons = {
    coredns = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
  }
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

      instance_types             = ["t3.medium"]
      capacity_type              = "ON_DEMAND"
      iam_role_attach_cni_policy = true
      subnet_ids                 = module.vpc.private_subnets # nodes in private subnets

      tags = {
        Name        = "${var.name_prefix}-eks-ng-default"
        Environment = var.env
      }
    }
  }
  iam_role_additional_policies = {
    ecr_read = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  }

  tags = {
    Environment = var.env
    Terraform   = "true"
  }
}



resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds-sg"
  description = "RDS Postgres security group"
  vpc_id      = module.vpc.vpc_id



  tags = {
    Environment = var.env
    Terraform   = "true"
  }
}
resource "aws_vpc_security_group_ingress_rule" "rds_postgres_from_vpc" {
  security_group_id = aws_security_group.rds.id

  description = "Allow Postgres from VPC CIDR"
  cidr_ipv4   = "10.0.0.0/16" # ⬅️ your VPC CIDR
  from_port   = 5432
  to_port     = 5432
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "rds_egress_all" {
  security_group_id = aws_security_group.rds.id

  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1" # all protocols
}




module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "6.13.1"

  identifier = "${var.name_prefix}-inventory-db"

  engine         = "postgres"
  engine_version = "16.10"
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

  vpc_security_group_ids = [aws_security_group.rds.id]

  subnet_ids             = module.vpc.private_subnets
  create_db_subnet_group = true
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

resource "kubernetes_secret_v1" "argocd_gitops_repo" {
  provider = kubernetes.eks
  metadata {
    name      = "argocd-github-jimag-gitops"
    namespace = "argocd"
    labels = {
      # This label tells Argo: "This secret describes a Git repository"
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {

    url      = "https://github.com/Jimag-Dev-Org/Jimag-GitOps.git"
    username = "x-access-token"
    password = var.argocd_gitops_pat
  }

  type = "Opaque"


  depends_on = [
    helm_release.argocd,
    module.eks
  ]
}


locals {
  rds_master_secret_arn = module.db.db_instance_master_user_secret_arn
}

data "aws_secretsmanager_secret_version" "rds_master" {
  secret_id = local.rds_master_secret_arn
}

locals {
  rds_master = jsondecode(data.aws_secretsmanager_secret_version.rds_master.secret_string)

  db_username = local.rds_master.username
  db_password = local.rds_master.password

  db_host = module.db.db_instance_address
  db_port = tostring(module.db.db_instance_port)

  db_name = "jimag_inventory"
}

resource "aws_secretsmanager_secret" "inventory_db_app" {
  name = "/jimag/dev/inventory/db"
}


resource "aws_secretsmanager_secret_version" "inventory_db_app" {
  secret_id = aws_secretsmanager_secret.inventory_db_app.id
  secret_string = jsonencode({
    username = local.db_username
    password = local.db_password
    host     = local.db_host
    port     = local.db_port
    dbname   = local.db_name
  })
}