terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.35, < 4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }

  # Remote state with locking. Uncomment and point at your own bucket before
  # using this with a team; local state is fine for a first solo run.
  #
  # backend "s3" {
  #   bucket       = "my-terraform-state"
  #   key          = "shortlink/aws/terraform.tfstate"
  #   region       = "ap-south-1"
  #   use_lockfile = true
  # }
}
