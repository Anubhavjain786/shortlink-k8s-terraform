# Single-replica Redis with persistence, managed with the Kubernetes provider.
# A StatefulSet gives the pod a stable name and its own PersistentVolumeClaim,
# so data survives pod restarts and rescheduling.

locals {
  labels = {
    "app.kubernetes.io/name"       = var.name
    "app.kubernetes.io/managed-by" = "terraform"
  }
}

resource "kubernetes_service_v1" "redis" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    cluster_ip = "None" # headless: DNS resolves straight to the pod
    selector   = local.labels

    port {
      name        = "redis"
      port        = 6379
      target_port = "redis"
    }
  }
}

resource "kubernetes_stateful_set_v1" "redis" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    service_name = kubernetes_service_v1.redis.metadata[0].name
    replicas     = 1

    selector {
      match_labels = local.labels
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        security_context {
          run_as_non_root = true
          run_as_user     = 999
          fs_group        = 999
        }

        container {
          name  = "redis"
          image = var.image
          args  = ["--appendonly", "yes", "--dir", "/data"]

          port {
            name           = "redis"
            container_port = 6379
          }

          readiness_probe {
            exec {
              command = ["redis-cli", "ping"]
            }
            period_seconds = 5
          }

          liveness_probe {
            tcp_socket {
              port = "redis"
            }
            period_seconds = 10
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "128Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "data"
      }

      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = var.storage_class_name

        resources {
          requests = {
            storage = var.storage_size
          }
        }
      }
    }
  }
}
