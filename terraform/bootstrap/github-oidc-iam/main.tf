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
          "s3:GetBucketLocation",
          "s3:ListAllMyBuckets"
        ]
        Resource = [
          "arn:aws:s3:::jimag-terraform-state-dev", # ⬅️ update
          "arn:aws:s3:::jimag-terraform-state-dev/*",
          "*" # ⬅️ update
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
      },
      {
        "Sid" : "IamGetRoleSelf",
        "Effect" : "Allow",
        "Action" : [
          "iam:GetRole"
        ],
        "Resource" : "arn:aws:iam::${local.account_id}:role/Githubrole-forinfra"
      },
      {
        "Sid" : "SsmReadEksOptimizedAmis",
        "Effect" : "Allow",
        "Action" : [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ssm:DescribeParameters"
        ],
        "Resource" : "arn:aws:ssm:${var.aws_region}::parameter/aws/service/eks/*"
      },

      # --- EC2 / VPC networking (for VPC subnets, route tables, SGs, ENIs, etc.) ---
      {
        "Sid" : "Ec2VpcDescribes",
        "Effect" : "Allow",
        "Action" : [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeRouteTables",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeNatGateways",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeVpcEndpoints",
          "ec2:DescribeVpcPeeringConnections"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "Ec2VpcManage",
        "Effect" : "Allow",
        "Action" : [
          "ec2:CreateVpc",
          "ec2:DeleteVpc",
          "ec2:CreateSubnet",
          "ec2:DeleteSubnet",
          "ec2:CreateRouteTable",
          "ec2:DeleteRouteTable",
          "ec2:CreateRoute",
          "ec2:DeleteRoute",
          "ec2:AssociateRouteTable",
          "ec2:DisassociateRouteTable",
          "ec2:CreateInternetGateway",
          "ec2:AttachInternetGateway",
          "ec2:DetachInternetGateway",
          "ec2:DeleteInternetGateway",
          "ec2:CreateNatGateway",
          "ec2:DeleteNatGateway",
          "ec2:AllocateAddress",
          "ec2:ReleaseAddress",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:CreateTags",
          "ec2:DeleteTags"
        ],
        "Resource" : "*"
      },

      # --- EKS clusters + nodegroups (terraform-aws-modules/eks) ---
      {
        "Sid" : "EksClusterAndNodegroups",
        "Effect" : "Allow",
        "Action" : [
          "eks:CreateCluster",
          "eks:DescribeCluster",
          "eks:ListClusters",
          "eks:UpdateClusterConfig",
          "eks:UpdateClusterVersion",
          "eks:DeleteCluster",
          "eks:TagResource",
          "eks:UntagResource",
          "eks:CreateNodegroup",
          "eks:UpdateNodegroupConfig",
          "eks:UpdateNodegroupVersion",
          "eks:DescribeNodegroup",
          "eks:ListNodegroups",
          "eks:DeleteNodegroup"
        ],
        "Resource" : [
          "arn:aws:eks:${var.aws_region}:${local.account_id}:cluster/*",
          "arn:aws:eks:${var.aws_region}:${local.account_id}:nodegroup/*/*/*"
        ]
      },

      # --- IAM for EKS nodegroups / cluster roles (created by module) ---
      {
        "Sid" : "IamForEksRoles",
        "Effect" : "Allow",
        "Action" : [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:GetRole",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:PassRole"
        ],
        "Resource" : "arn:aws:iam::${local.account_id}:role/jimag-eks-*"
      },

      # --- Auto Scaling Groups for nodegroups ---
      {
        "Sid" : "AutoScalingForEks",
        "Effect" : "Allow",
        "Action" : [
          "autoscaling:CreateAutoScalingGroup",
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:DeleteAutoScalingGroup",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeScalingActivities",
          "autoscaling:PutScalingPolicy",
          "autoscaling:DeletePolicy",
          "autoscaling:DescribePolicies",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup"
        ],
        "Resource" : "*"
      },

      # --- RDS instances, subnet groups, parameter groups for inventory DB ---
      {
        "Sid" : "RdsManage",
        "Effect" : "Allow",
        "Action" : [
          "rds:CreateDBInstance",
          "rds:ModifyDBInstance",
          "rds:DeleteDBInstance",
          "rds:DescribeDBInstances",
          "rds:CreateDBSubnetGroup",
          "rds:ModifyDBSubnetGroup",
          "rds:DeleteDBSubnetGroup",
          "rds:DescribeDBSubnetGroups",
          "rds:CreateDBParameterGroup",
          "rds:ModifyDBParameterGroup",
          "rds:DeleteDBParameterGroup",
          "rds:DescribeDBParameterGroups",
          "rds:DescribeDBParameters",
          "rds:AddTagsToResource",
          "rds:ListTagsForResource"
        ],
        "Resource" : "*"
      },

      # --- S3 buckets for app data (images, logs, etc.) ---
      {
        "Sid" : "AppBuckets",
        "Effect" : "Allow",
        "Action" : [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:GetBucketLocation",
          "s3:PutBucketPolicy",
          "s3:GetBucketPolicy",
          "s3:PutBucketTagging",
          "s3:GetBucketTagging",
          "s3:PutBucketLifecycleConfiguration",
          "s3:GetBucketLifecycleConfiguration",
          "s3:PutEncryptionConfiguration",
          "s3:GetEncryptionConfiguration"
        ],
        "Resource" : [
          "arn:aws:s3:::jimag-autos-images-dev", # ⬅️ update names
          "arn:aws:s3:::jimag-autos-images-preprod",
          "arn:aws:s3:::jimag-autos-images-prod"
        ]
      },
      {
        "Sid" : "AppBucketObjects",
        "Effect" : "Allow",
        "Action" : [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ],
        "Resource" : [
          "arn:aws:s3:::jimag-autos-images-dev/*",
          "arn:aws:s3:::jimag-autos-images-preprod/*",
          "arn:aws:s3:::jimag-autos-images-prod/*"
        ]
      },

      # --- CloudWatch Logs (for EKS / RDS / app logs wired by modules) ---
      {
        "Sid" : "CloudWatchLogsManage",
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutRetentionPolicy",
          "logs:DeleteLogGroup",
          "logs:TagLogGroup",
          "logs:UntagLogGroup"
        ],
        "Resource" : "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_terraform_attach" {
  role       = aws_iam_role.github_terraform.name
  policy_arn = aws_iam_policy.github_terraform_policy.arn
}