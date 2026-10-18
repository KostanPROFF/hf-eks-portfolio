output "cluster_name" { value = module.eks.cluster_name }
output "region" { value = var.region }
output "ecr_url" { value = aws_ecr_repository.app.repository_url }
output "build_role_arn" { value = aws_iam_role.build.arn }
output "deploy_role_arn" { value = aws_iam_role.deploy.arn }
output "vpc_id" { value = module.vpc.vpc_id }
output "private_subnet_ids" { value = module.vpc.private_subnets }
output "cluster_security_group_id" { value = module.eks.cluster_primary_security_group_id }
output "gpu_node_group_name" {
  value = var.enable_gpu ? split(":", module.eks.eks_managed_node_groups["gpu"].node_group_id)[1] : null
}
