module "vpc" {
  source               = "terraform-aws-modules/vpc/aws"
  version              = "6.0.1"
  name                 = var.name
  cidr                 = "10.42.0.0/16"
  azs                  = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets      = ["10.42.0.0/20", "10.42.16.0/20"]
  public_subnets       = ["10.42.128.0/24", "10.42.129.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  public_subnet_tags   = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags  = { "kubernetes.io/role/internal-elb" = "1" }
}
module "eks" {
  source                                   = "terraform-aws-modules/eks/aws"
  version                                  = "21.26.0"
  name                                     = var.name
  kubernetes_version                       = var.kubernetes_version
  endpoint_private_access                  = true
  endpoint_public_access                   = true
  endpoint_public_access_cidrs             = var.admin_cidrs
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  enabled_log_types                        = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days   = 7
  vpc_id                                   = module.vpc.vpc_id
  subnet_ids                               = module.vpc.private_subnets
  addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
    metrics-server         = {}
  }
  access_entries = {
    admin = {
      principal_arn = var.admin_role_arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
    deploy = {
      principal_arn     = aws_iam_role.deploy.arn
      kubernetes_groups = ["hf-deployers"]
    }
  }
  eks_managed_node_groups = merge({
    cpu = {
      instance_types        = ["t3.large"]
      ami_type              = "AL2023_x86_64_STANDARD"
      min_size              = 2
      max_size              = 3
      desired_size          = 2
      block_device_mappings = { root = { device_name = "/dev/xvda", ebs = { volume_size = 30, volume_type = "gp3", encrypted = true, delete_on_termination = true } } }
      metadata_options      = { http_tokens = "required", http_put_response_hop_limit = 1 }
      labels                = { workload = "cpu" }
    }
    }, var.enable_gpu ? {
    gpu = {
      instance_types        = ["g4dn.xlarge"]
      ami_type              = "AL2023_x86_64_NVIDIA"
      min_size              = 0
      max_size              = 1
      desired_size          = 0
      block_device_mappings = { root = { device_name = "/dev/xvda", ebs = { volume_size = 50, volume_type = "gp3", encrypted = true, delete_on_termination = true } } }
      metadata_options      = { http_tokens = "required", http_put_response_hop_limit = 1 }
      labels                = { workload = "gpu" }
      taints                = { gpu = { key = "nvidia.com/gpu", value = "true", effect = "NO_SCHEDULE" } }
    }
  } : {})
}
resource "aws_ecr_repository" "app" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false
  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
}
resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name
  policy     = jsonencode({ rules = [{ rulePriority = 1, description = "Keep 20 tagged images", selection = { tagStatus = "tagged", tagPrefixList = ["sha-"], countType = "imageCountMoreThan", countNumber = 20 }, action = { type = "expire" } }] })
}
