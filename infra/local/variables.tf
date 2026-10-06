variable "kubeconfig_path" {
  description = "Path to the kubeconfig for the kind cluster."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubeconfig context to use."
  type        = string
  default     = "kind-shortlink"
}

variable "namespace" {
  description = "Namespace for the app and Redis."
  type        = string
  default     = "shortlink"
}

variable "image_repository" {
  description = "Image repository. Locally this is the name loaded into kind."
  type        = string
  default     = "shortlink"
}

variable "image_tag" {
  description = "Image tag to deploy."
  type        = string
  default     = "dev"
}

variable "node_port" {
  description = "NodePort for the app. kind maps it to localhost:8080."
  type        = number
  default     = 30080
}
