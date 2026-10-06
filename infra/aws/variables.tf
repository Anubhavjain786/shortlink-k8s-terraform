variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "name" {
  description = "Name prefix for the VPC, cluster and repository."
  type        = string
  default     = "shortlink"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
  default     = "1.33"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 4
}

variable "image_tag" {
  description = "Image tag to deploy from the ECR repository."
  type        = string
  default     = "latest"
}
