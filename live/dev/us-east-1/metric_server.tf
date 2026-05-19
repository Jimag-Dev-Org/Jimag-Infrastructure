resource "helm_release" "metrics_server" {

  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.13.0"

  values = [
    yamlencode({
      args = [
        "--kubelet-preferred-address-types=InternalIP",
        "--kubelet-use-node-status-port"
      ]
    })
  ]

  depends_on = [
    module.eks
  ]
}