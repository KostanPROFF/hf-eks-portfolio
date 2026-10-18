variable "region" { default = "us-west-2" }
variable "name" { default = "hf-eks-demo" }
variable "kubernetes_version" { default = "1.35" }
variable "github_repository" {
  type        = string
  description = "Exact owner/repo, case sensitive"
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Expected owner/repo."
  }
}
variable "admin_role_arn" {
  type        = string
  description = "Existing IAM role ARN for human bootstrap; never an STS session ARN"
}
variable "admin_cidrs" {
  type        = list(string)
  description = "Explicit public API access CIDRs; use your current public IP/32"
  validation {
    condition     = length(var.admin_cidrs) > 0 && alltrue([for c in var.admin_cidrs : can(cidrnetmask(c)) && !endswith(c, "/0")])
    error_message = "Supply restricted IPv4 CIDRs, never /0."
  }
}
variable "github_oidc_provider_arn" {
  type        = string
  default     = null
  description = "Existing GitHub OIDC provider ARN if already present in this AWS account"
}
variable "enable_gpu" { default = false }
variable "enable_load_balancer_controller" { default = false }
