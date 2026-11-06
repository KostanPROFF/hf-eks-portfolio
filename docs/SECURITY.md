# Security design

- The human bootstrap IAM role gets cluster admin via an EKS access entry. Implicit creator admin is disabled.
- GitHub build role: ECR token (AWS requires Resource *) and repository-scoped upload/read.
- GitHub deploy role: DescribeCluster on exactly one cluster; EKS group → namespaced Role,
  only get/list/patch/watch on a specific Deployment. No cluster admin, Secrets read or RBAC writes.
- GitHub OIDC aud/sub are exact matches. The production environment must restrict branches and reviewers.
- The pod service account token is not mounted, UID 10001, read-only root, dropped capabilities,
  IMDSv2 required/hop-limit 1. The application has no AWS API permissions; ECR pulls are done by the node role.
- Nodes are private; the API is public with restricted CIDRs + a private endpoint. No SSH key/port 22 is created.
- The EKS module enables at-rest envelope encryption by its defaults; root EBS encryption is set explicitly.
- The optional LBC gets EKS Pod Identity; the upstream policy contains the required EC2 describe
  wildcards and tag conditions, lives in terraform/policies and needs review when the chart is updated.
- Secrets: the Grafana admin password is generated at install and stored in a Kubernetes Secret. It does not end up
  in Terraform state or Git. For a real application use Secrets Manager + Pod Identity + CSI/External Secrets;
  do not put tokens in tfvars, the image, workflow variables or Docker build args.
- No NetworkPolicy enforcement in the base setup; the internal Service is not an authentication boundary.
  Access from other namespaces is possible. For production, enable VPC CNI network policy and verify
  DNS/metrics/client ingress + default deny against the actual traffic flows.

## Remote state for a team

The backend is created separately from the main stack so that destroying the environment does not delete the state.
Create a unique S3 bucket in your account: Block Public Access, versioning, default SSE-KMS,
a TLS-only bucket policy, restricted IAM for the state prefix and lockfile. Prepare the KMS key policy.
In a separate `terraform/backend.tf` (without credentials):

```hcl
terraform {
  backend "s3" {
    bucket       = "YOUR-UNIQUE-STATE-BUCKET"
    key          = "hf-eks/demo.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true
    kms_key_id   = "YOUR-KMS-KEY-ARN"
  }
}
```

Run `terraform -chdir=terraform init -migrate-state` under an authorized role.
First verify the backup and access to all state versions. Backend IAM must allow
s3 ListBucket on the prefix, GetObject/PutObject on the state and GetObject/PutObject/DeleteObject on `.tflock`,
plus KMS Encrypt/Decrypt/GenerateDataKey. The GitHub deploy/build roles do not need the backend.
Do not store credentials in the backend config: Terraform caches its parameters on disk.

## Threat model and boundaries

Repository writers with access to main and the environment can run CI and change the application.
Restricted runner groups, branch protections, reviewers, workflow CODEOWNERS and ephemeral runners are mandatory
before use with untrusted contributors. Do not run fork PRs on a self-hosted runner.
The current Role restriction does not prevent the trusted CD from changing the pod spec — it is not a sandbox against a malicious main.
EKS/node/add-on dependency patches, the Python transitive lock and runtime vulnerability remediation
remain the owner's responsibility. Pins provide reproducibility but do not by themselves guarantee security.
