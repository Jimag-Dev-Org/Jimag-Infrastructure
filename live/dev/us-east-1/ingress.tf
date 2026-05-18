resource "kubernetes_namespace_v1" "ingress_nginx" {
  provider = kubernetes.eks

  metadata {
    name = "ingress-nginx"
  }

  depends_on = [
    aws_eks_access_policy_association.github_infra_role_admin,
    module.eks
  ]
}

resource "helm_release" "ingress_nginx" {

  name       = "ingress-nginx"
  namespace  = kubernetes_namespace_v1.ingress_nginx.metadata[0].name
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.11.3"

  values = [
    yamlencode({
      controller = {
        replicaCount = 2

        service = {
          type = "LoadBalancer"

          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
            "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
          }
        }

        metrics = {
          enabled = true

          serviceMonitor = {
            enabled = false
          }
        }

        admissionWebhooks = {
          enabled = true
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace_v1.ingress_nginx
  ]
}