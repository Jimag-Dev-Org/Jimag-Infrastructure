data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# Give the GitHub Actions role cluster-admin rights in this EKS cluster
resource "aws_eks_access_entry" "github_infra_role" {
  cluster_name  = module.eks.cluster_name
  principal_arn = "arn:aws:iam::${local.account_id}:role/Githubrole-forinfra"

  type = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_infra_role_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_eks_access_entry.github_infra_role.principal_arn

  policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}