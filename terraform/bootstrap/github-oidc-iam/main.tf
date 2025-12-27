data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  github_oidc_arn = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"

  # Branch-based subjects (develop, main, etc.)
  github_branch_sub_patterns = [
    for b in var.allowed_branches :
    "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${b}"
  ]

  # PR-based subject
  github_pr_sub_patterns = [
    "repo:${var.github_org}/${var.github_repo}:pull_request"
  ]

  # Final list used in the trust policy
  github_sub_patterns = concat(
    local.github_branch_sub_patterns,
    local.github_pr_sub_patterns
  )
}

resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    # Replace with the thumbprint you used when creating the provider,
    # or import the existing resource and let Terraform show you the current value.
    "2b18947a6a9fc7764fd8b5fb18a863b0c6dac24f" # placeholder
  ]
}

resource "aws_iam_role" "github_terraform" {
  name = "Githubrole-forinfra" # ⬅️ must match the real role name if importing

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.github_oidc_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.github_sub_patterns
          }
        }
      }
    ]
  })
}

# Permissions for Terraform (example – extend as your infra grows)
resource "aws_iam_policy" "github_terraform_policy" {
  name        = "Terraform-policy-github"
  description = "Permissions for Terraform runs from GitHub Actions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ------------------------------------------------------------------
      # 1) S3 backend for Terraform state (remote state bucket only)
      # ------------------------------------------------------------------
      {
        Sid    = "TerraformStateS3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::jimag-terraform-state-dev",
          "arn:aws:s3:::jimag-terraform-state-dev/*"
        ]
      },

      # ------------------------------------------------------------------
      # 2) DynamoDB lock table for Terraform state
      # ------------------------------------------------------------------
      {
        Sid    = "TerraformStateLockDynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:UpdateItem",
          "dynamodb:DescribeTable"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${local.account_id}:table/jimag-terraform-locks-dev"
      },

      # ------------------------------------------------------------------
      # 3) ECR management for jimag-* repos (infra + app repos)
      # ------------------------------------------------------------------
      {
        Sid    = "TerraformECRManagement"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository",
          "ecr:DeleteRepository",
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
          "ecr:ListImages",
          "ecr:GetRepositoryPolicy",
          "ecr:SetRepositoryPolicy",
          "ecr:PutLifecyclePolicy",
          "ecr:GetLifecyclePolicy",
          "ecr:DeleteLifecyclePolicy",
          "ecr:TagResource",
          "ecr:UntagResource",
          "ecr:ListTagsForResource",
          "ecr:DescribeRegistry",
          "ecr:GetRegistryPolicy",
          "ecr:PutImage"
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${local.account_id}:repository/jimag-*"
      },

      # ------------------------------------------------------------------
      # 4) Read public EKS-optimized AMIs from SSM (for EKS module)
      # ------------------------------------------------------------------
      {
        Sid    = "SsmReadEksOptimizedAmis"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:DescribeParameters",
          "kms:DescribeKey",
          "kms:CreateGrant",
          "kms:Encrypt",
          "kms:Decrypt"
        ]
        Resource = [
          "arn:aws:ssm:${var.aws_region}::parameter/aws/service/eks/*"
        ]
      },

      # ------------------------------------------------------------------
      # 5) Dev-only broad infra permissions
      #
      #    This is the "make Terraform apply actually work" block.
      #    For DEV, we allow wide actions on infra-related services.
      #    In PROD you'd split and scope this more tightly.
      # ------------------------------------------------------------------
      {
        Sid    = "DevInfraWidePermissions"
        Effect = "Allow"
        Action = [
          # VPC / networking / ENIs / SGs / routes / subnets / NAT / IGW
          "ec2:*",

          # EKS control plane & managed node groups
          "eks:*",
          "autoscaling:*",
          "elasticloadbalancing:*",

          # IAM for cluster roles, node roles, and IRSA roles
          # (create/update/delete/attach/pass/etc.)
          "iam:*",

          # RDS DB instances, subnet groups, parameter groups, tags
          "rds:*",

          # App data & images buckets + any future jimag-* buckets
          "s3:*",

          # Logs for EKS, RDS, etc. (log groups, retention, tags)
          "logs:*",

          # Secrets Manager for DB passwords, app secrets, etc.
          "secretsmanager:*",

          # KMS for encryption keys used by RDS / Secrets Manager / S3
          "kms:DescribeKey",
          "kms:CreateGrant",
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:ReEncrypt*",
          "kms:TagResource",
          "kms:*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_terraform_attach" {
  role       = aws_iam_role.github_terraform.name
  policy_arn = aws_iam_policy.github_terraform_policy.arn
}