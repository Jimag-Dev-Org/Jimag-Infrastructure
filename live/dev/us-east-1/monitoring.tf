resource "kubernetes_namespace_v1" "monitoring" {
  provider = kubernetes.eks

  metadata {
    name = "monitoring"
  }

  depends_on = [
    aws_eks_access_policy_association.github_infra_role_admin,
    module.eks
  ]
}

resource "helm_release" "kube_prometheus_stack" {

  name       = "kube-prometheus-stack"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "65.5.1"

  values = [
    yamlencode({
      grafana = {
        enabled = true
        service = {
          type = "ClusterIP"
        }
        adminPassword = "admin-dev-change-me"
      }

      prometheus = {
        prometheusSpec = {
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
          ruleSelectorNilUsesHelmValues           = false
          retention                               = "7d"
        }
      }

      alertmanager = {
        enabled = true
      }

      kubeStateMetrics = {
        enabled = true
      }

      nodeExporter = {
        enabled = true
      }
    })
  ]

  depends_on = [
    kubernetes_namespace_v1.monitoring
  ]
}