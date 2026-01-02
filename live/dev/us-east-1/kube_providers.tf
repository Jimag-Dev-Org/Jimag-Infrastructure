#  Read EKS cluster details from AWS
data "aws_eks_cluster" "this" {
  name = module.eks.cluster_name
}

#  Get an auth token for the same IAM role Terraform is using
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

# Kubernetes provider - talks directly to the EKS API server
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

# Helm provider - uses that Kubernetes connection
provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}