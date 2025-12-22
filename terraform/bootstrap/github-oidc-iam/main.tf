data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  github_oidc_arn = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com"

  github_sub_patterns = [
    for b in var.allowed_branches :
    "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${b}"
  ]
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
      # S3 remote state
      {
        Sid    = "TerraformStateS3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::jimag-terraform-state-dev",  # ⬅️ update
          "arn:aws:s3:::jimag-terraform-state-dev/*" # ⬅️ update
        ]
      },
      # DynamoDB lock
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
        Resource = "arn:aws:dynamodb:${var.aws_region}:${local.account_id}:table/jimag-terraform-locks-dev" # ⬅️ update
      },
      # ECR management (scoped to your repos)
      {
        Sid    = "TerraformECRManagement"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository",
          "ecr:DescribeRepositories",
          "ecr:PutLifecyclePolicy",
          "ecr:DeleteRepository",
          "ecr:GetRepositoryPolicy",
          "ecr:SetRepositoryPolicy",
          "ecr:TagResource",
          "ecr:UntagResource",
          "ecr:ListTagsForResource",
          "ecr:DescribeImages",
          "ecr:DescribePullThroughCacheRules",
          "ecr:ListImages",
          "ecr:DescribeRegistry",
          "ecr:DescribeRepositories",
          "ecr:GetLifecyclePolicy",
          "ecr:GetRegistryPolicy",
          "ecr:CreateRepository",
          "ecr:CreateRepositoryCreationTemplate",
          "ecr:DeleteLifecyclePolicy",
          "ecr:DeleteRepository",
          "ecr:PutImage",
        ]
        Resource = "arn:aws:ecr:${var.aws_region}:${local.account_id}:repository/jimag-*"
      },
      # Secrets Manager read for dev (example – we’ll widen as needed)
      {
        Sid    = "SecretsManagerReadDev"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${local.account_id}:secret:/jimag/dev/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_terraform_attach" {
  role       = aws_iam_role.github_terraform.name
  policy_arn = aws_iam_policy.github_terraform_policy.arn
}