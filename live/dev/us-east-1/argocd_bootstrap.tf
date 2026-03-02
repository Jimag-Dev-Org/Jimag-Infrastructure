resource "kubernetes_namespace_v1" "argocd" {
  provider = kubernetes.eks
  metadata {
    name = "argocd"
    labels = {
      "app.kubernetes.io/name"       = "argocd"
      "app.kubernetes.io/part-of"    = "argocd"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  depends_on = [aws_eks_access_policy_association.github_infra_role_admin]
}


resource "helm_release" "argocd" {

  name      = "argo-cd"
  namespace = kubernetes_namespace_v1.argocd.metadata[0].name

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.52.1" # example - pick a stable chart version


  values = [
    file("${path.module}/values-argocd-dev.yaml")
  ]
  depends_on = [aws_eks_access_policy_association.github_infra_role_admin]
}