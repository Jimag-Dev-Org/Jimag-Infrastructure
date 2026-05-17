# EKS module usually outputs the OIDC provider ARN and issuer URL.
data "aws_iam_openid_connect_provider" "eks" {
  arn = module.eks.oidc_provider_arn
}

locals {
  eso_namespace       = "external-secrets"
  eso_sa_name         = "external-secrets"
  inventory_namespace = "dev"
  inventory_sa_name   = "inventory-svc"
  oidc_hostpath       = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
}

resource "aws_iam_role" "eso_irsa" {
  name = "${var.name_prefix}-eso-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = module.eks.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_hostpath}:aud" = "sts.amazonaws.com"
          "${local.oidc_hostpath}:sub" = "system:serviceaccount:${local.eso_namespace}:${local.eso_sa_name}"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "eso_read_sm" {
  name = "${var.name_prefix}-eso-read-secretsmanager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ReadInventoryDbSecret"
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:/jimag/dev/inventory/db-*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eso_attach" {
  role       = aws_iam_role.eso_irsa.name
  policy_arn = aws_iam_policy.eso_read_sm.arn
}



resource "aws_iam_role" "inventory_s3_irsa" {
  name = "${var.name_prefix}-inventory-s3-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"

      Principal = {
        Federated = module.eks.oidc_provider_arn
      }

      Action = "sts:AssumeRoleWithWebIdentity"

      Condition = {
        StringEquals = {
          "${local.oidc_hostpath}:aud" = "sts.amazonaws.com"
          "${local.oidc_hostpath}:sub" = "system:serviceaccount:${local.inventory_namespace}:${local.inventory_sa_name}"
        }
      }
    }]
  })
}