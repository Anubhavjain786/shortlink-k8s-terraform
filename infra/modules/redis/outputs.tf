output "url" {
  description = "Redis connection string for clients in the same namespace."
  value       = "redis://${kubernetes_service_v1.redis.metadata[0].name}:6379/0"
}
