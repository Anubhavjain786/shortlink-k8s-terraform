# Deploys the app's Helm chart. Terraform owns the release, so image tag,
# replica bounds and service exposure are all changed through a plan.

# With a local chart path, the Helm provider only notices changes to the chart
# version and to the values. Hashing every chart file into the values makes any
# template or default change show up in `terraform plan`.
locals {
  chart_checksum = sha1(join("", [
    for f in sort(fileset(var.chart_path, "**")) : filesha1("${var.chart_path}/${f}")
  ]))
}

resource "helm_release" "shortlink" {
  name      = var.release_name
  namespace = var.namespace
  chart     = var.chart_path

  # Wait until the Deployment is rolled out and pods are Ready, and roll back
  # automatically if that does not happen in time.
  wait    = true
  atomic  = true
  timeout = 300

  values = [yamlencode({
    chartChecksum = local.chart_checksum
    image = {
      repository = var.image_repository
      tag        = var.image_tag
    }
    redisUrl = var.redis_url
    baseUrl  = var.base_url
    service = {
      type     = var.service_type
      nodePort = var.node_port
    }
    autoscaling = {
      enabled     = true
      minReplicas = var.min_replicas
      maxReplicas = var.max_replicas
    }
  })]
}
