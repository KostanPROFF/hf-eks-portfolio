resource "aws_iam_openid_connect_provider" "github" {
  count          = var.github_oidc_provider_arn == null ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
locals {
  oidc_arn = var.github_oidc_provider_arn != null ? var.github_oidc_provider_arn : aws_iam_openid_connect_provider.github[0].arn
  roles = {
    build  = "repo:${var.github_repository}:ref:refs/heads/main"
    deploy = "repo:${var.github_repository}:environment:production"
  }
}
data "aws_iam_policy_document" "github_trust" {
  for_each = local.roles
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [each.value]
    }
  }
}
resource "aws_iam_role" "build" {
  name               = "${var.name}-github-build"
  assume_role_policy = data.aws_iam_policy_document.github_trust["build"].json
}
resource "aws_iam_role" "deploy" {
  name               = "${var.name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_trust["deploy"].json
}
resource "aws_iam_role_policy" "build" {
  role = aws_iam_role.build.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
    { Effect = "Allow", Action = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:DescribeImages"], Resource = aws_ecr_repository.app.arn }
  ] })
}
resource "aws_iam_role_policy" "deploy" {
  role = aws_iam_role.deploy.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["eks:DescribeCluster"], Resource = module.eks.cluster_arn }
  ] })
}
# Pods do not inherit the GitHub roles. Optional controller uses EKS Pod Identity.
resource "aws_iam_role" "lb_controller" {
  count = var.enable_load_balancer_controller ? 1 : 0
  name  = "${var.name}-lb-controller"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Principal = { Service = "pods.eks.amazonaws.com" },
    Action    = ["sts:AssumeRole", "sts:TagSession"],
    Condition = { StringEquals = { "aws:RequestTag/eks-cluster-arn" = module.eks.cluster_arn, "aws:RequestTag/kubernetes-namespace" = "kube-system", "aws:RequestTag/kubernetes-service-account" = "aws-load-balancer-controller" } }
  }] })
}
resource "aws_iam_role_policy" "lb_controller" {
  count  = var.enable_load_balancer_controller ? 1 : 0
  role   = aws_iam_role.lb_controller[0].id
  policy = file("${path.module}/policies/lb-controller.json")
}
resource "aws_eks_pod_identity_association" "lb_controller" {
  count           = var.enable_load_balancer_controller ? 1 : 0
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lb_controller[0].arn
}
