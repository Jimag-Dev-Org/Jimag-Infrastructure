# Root Argo CD Application for dev (app-of-apps)
# This tells Argo: "watch the JIMAG GitOps repo at envs/dev and sync it."

resource "kubernetes_manifest" "argocd_root_app_dev" {
  provider = kubernetes.eks
  count    = var.enable_argo_bootstrap ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "jimag-dev-root"
      namespace = "argocd"
    }
    spec = {
      project = "default"

      source = {
        repoURL        = "https://github.com/Jimag-Dev-Org/Jimag-GitOps.git"
        targetRevision = "main"
        path           = "envs/dev" # where your env kustomization lives
      }

      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }

      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true"
        ]
      }
    }
  }

  # ✅ Make sure Argo CD is installed (CRDs + controllers) before this runs
  depends_on = [
    helm_release.argocd
  ]
}
