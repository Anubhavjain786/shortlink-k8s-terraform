# Local environment: everything runs in a kind cluster on the developer machine.

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}

provider "helm" {
  kubernetes = {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context
  }
}

resource "kubernetes_namespace_v1" "shortlink" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# The HorizontalPodAutoscaler needs CPU metrics, which metrics-server provides.
# kind's kubelets use self-signed certificates, hence --kubelet-insecure-tls.
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  namespace  = "kube-system"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.13.0"

  values = [yamlencode({
    args = ["--kubelet-insecure-tls"]
  })]
}

module "redis" {
  source    = "../modules/redis"
  namespace = kubernetes_namespace_v1.shortlink.metadata[0].name
}

module "shortlink" {
  source = "../modules/shortlink"

  namespace        = kubernetes_namespace_v1.shortlink.metadata[0].name
  chart_path       = "${path.module}/../../deploy/helm/shortlink"
  image_repository = var.image_repository
  image_tag        = var.image_tag
  redis_url        = module.redis.url
  base_url         = "http://localhost:8080"
  service_type     = "NodePort"
  node_port        = var.node_port
}
