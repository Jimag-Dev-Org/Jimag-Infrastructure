resource "kubernetes_namespace_v1" "cert_manager" {
  provider = kubernetes.eks

  metadata {
    name = "cert-manager"
  }

  depends_on = [
    aws_eks_access_policy_association.github_infra_role_admin,
    module.eks
  ]
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  namespace  = kubernetes_namespace_v1.cert_manager.metadata[0].name
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.16.2"

  set = [
    {
      name  = "crds.enabled"
      value = "true"
    }
  ]

  depends_on = [
    kubernetes_namespace_v1.cert_manager
  ]
}