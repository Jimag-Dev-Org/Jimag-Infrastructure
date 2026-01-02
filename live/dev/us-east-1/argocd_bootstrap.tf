resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}


resource "helm_release" "argocd" {
  name      = "argo-cd"
  namespace = kubernetes_namespace_v1.argocd.metadata[0].name

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.52.1" # example - pick a stable chart version

  # For now we keep values minimal; we'll tune ingress, RBAC, etc. later
  values = [
    file("${path.module}/values-argocd-dev.yaml")
  ]
}