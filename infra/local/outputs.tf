output "url" {
  description = "Where the app answers on the developer machine."
  value       = "http://localhost:8080"
}

output "namespace" {
  description = "Namespace holding the app and Redis."
  value       = kubernetes_namespace_v1.shortlink.metadata[0].name
}

output "helm_revision" {
  description = "Current Helm revision of the app release."
  value       = module.shortlink.revision
}
