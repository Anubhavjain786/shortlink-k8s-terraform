# AWS environment: VPC, EKS and ECR, then the same Redis and app modules that
# the local environment uses. Only the cluster underneath changes.

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.name
      ManagedBy = "terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

# ---------- network ----------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.name
  cidr = var.vpc_cidr
  azs  = local.azs

  # Nodes live in private subnets. Load balancers live in public subnets.
  private_subnets = [for i in range(3) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 8, 48 + i)]

  enable_nat_gateway = true
  single_nat_gateway = true # one NAT keeps cost down; use one per AZ in production

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

# ---------- cluster ----------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true

  addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
    metrics-server     = {} # CPU metrics for the HorizontalPodAutoscaler
    aws-ebs-csi-driver = {} # persistent volumes for Redis
  }

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types
      min_size       = 2
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size

      iam_role_additional_policies = {
        ebs = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
      }
    }
  }
}

# ---------- image registry ----------
resource "aws_ecr_repository" "shortlink" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "shortlink" {
  repository = aws_ecr_repository.shortlink.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 20 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}

# ---------- workloads ----------
# Both providers authenticate with a short-lived token from the AWS CLI,
# so no kubeconfig file or long-lived credential is stored.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.region]
    }
  }
}

resource "kubernetes_namespace_v1" "shortlink" {
  metadata {
    name = var.name
  }

  depends_on = [module.eks]
}

module "redis" {
  source = "../modules/redis"

  namespace    = kubernetes_namespace_v1.shortlink.metadata[0].name
  storage_size = "5Gi"
}

module "shortlink" {
  source = "../modules/shortlink"

  namespace        = kubernetes_namespace_v1.shortlink.metadata[0].name
  chart_path       = "${path.module}/../../deploy/helm/shortlink"
  image_repository = aws_ecr_repository.shortlink.repository_url
  image_tag        = var.image_tag
  redis_url        = module.redis.url
  service_type     = "LoadBalancer"
  min_replicas     = 2
  max_replicas     = 10
}
