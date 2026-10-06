variable "namespace" {
  description = "Namespace to deploy Redis into."
  type        = string
}

variable "name" {
  description = "Name of the Redis StatefulSet and Service."
  type        = string
  default     = "redis"
}

variable "image" {
  description = "Redis container image."
  type        = string
  default     = "redis:7.4-alpine"
}

variable "storage_size" {
  description = "Size of the persistent volume that holds the append-only file."
  type        = string
  default     = "1Gi"
}

variable "storage_class_name" {
  description = "StorageClass for the volume. Null uses the cluster default."
  type        = string
  default     = null
}
