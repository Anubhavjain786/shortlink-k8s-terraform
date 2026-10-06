variable "namespace" {
  description = "Namespace to deploy the app into."
  type        = string
}

variable "release_name" {
  description = "Helm release name."
  type        = string
  default     = "shortlink"
}

variable "chart_path" {
  description = "Path to the shortlink Helm chart."
  type        = string
}

variable "image_repository" {
  description = "Container image repository."
  type        = string
}

variable "image_tag" {
  description = "Container image tag."
  type        = string
}

variable "redis_url" {
  description = "Redis connection string."
  type        = string
}

variable "base_url" {
  description = "Public base URL used in generated short links."
  type        = string
  default     = ""
}

variable "service_type" {
  description = "Kubernetes Service type."
  type        = string
  default     = "ClusterIP"

  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer"], var.service_type)
    error_message = "service_type must be ClusterIP, NodePort or LoadBalancer."
  }
}

variable "node_port" {
  description = "NodePort to expose when service_type is NodePort."
  type        = number
  default     = null
}

variable "min_replicas" {
  description = "Minimum replicas kept by the HorizontalPodAutoscaler."
  type        = number
  default     = 2
}

variable "max_replicas" {
  description = "Maximum replicas allowed by the HorizontalPodAutoscaler."
  type        = number
  default     = 5
}
