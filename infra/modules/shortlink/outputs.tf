output "release_name" {
  description = "Helm release name."
  value       = helm_release.shortlink.name
}

output "revision" {
  description = "Helm release revision. It increases on every change."
  value       = helm_release.shortlink.metadata.revision
}
