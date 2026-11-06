# Security design

- The human bootstrap IAM role gets cluster admin via an EKS access entry. Creator implicit admin is disabled.
- GitHub build role: ECR token (AWS requires Resource *) and repository-scoped upload/read.
- GitHub deploy role: DescribeCluster for exactly one cluster; EKS group → namespaced Role,
  with only get/list/patch/watch on a specific Deployment. No cluster admin, Secrets read, or RBAC writes.
- GitHub OIDC aud/sub exact matches. The production environment must restrict branches and reviewers.
- The pod service account token is not mounted, UID 10001, read-only root, dropped capabilities,
  IMDSv2 required/hop-limit 1. The application has no AWS API permissions; the ECR pull is done by the node role.
- Nodes are private; the API is public with restricted CIDRs + a private endpoint. No SSH key/port 22 is created.
- The EKS module enables at-rest envelope encryption by its own defaults; root EBS encryption is set explicitly.
- The optional LBC gets EKS Pod Identity; the upstream policy contains the necessary EC2 describe
  wildcard and tag conditions, lives in terraform/policies, and requires review when the chart is updated.
- Secrets: the Grafana admin password is generated at install time and stored in a Kubernetes Secret. It never lands
  in Terraform state or Git. For a real application, use Secrets Manager + Pod Identity + CSI/External Secrets;
  never put tokens in tfvars, images, workflow variables, or Docker build args.
- There is no NetworkPolicy enforcement in the base version; the internal Service is not an authentication boundary.
  Access from other namespaces is possible. For production, enable the VPC CNI network policy and verify
  DNS/metrics/client ingress + default deny against the actual traffic scheme.

## Remote state for a team

The backend is created separately from the main stack, so that destroying the lab does not delete the state.
Create a unique S3 bucket in your own account: Block Public Access, versioning, default SSE-KMS,
a TLS-only bucket policy, and restricted IAM for the state prefix and lockfile. Prepare the KMS key policy.
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

Run `terraform -chdir=terraform init -migrate-state` under the authorized role.
First check the backup and access to all state versions. The backend IAM must allow
s3 ListBucket on the prefix, GetObject/PutObject on the state, and GetObject/PutObject/DeleteObject on `.tflock`,
plus KMS Encrypt/Decrypt/GenerateDataKey. The GitHub deploy/build roles do not need the backend.
Do not store credentials in the backend config: Terraform caches its parameters on disk.

## Threat model and boundaries

Repository writers with access to main and the environment can run CI and change the application.
Restrict the runner group, branch protections, reviewers, workflow CODEOWNERS, and ephemeral runners — this is mandatory
before working with untrusted contributors. Never run fork PRs on a self-hosted runner.
The current Role restriction does not prevent a trusted CD from changing the pod spec — it is not a sandbox against a malicious main.
EKS/node/add-on dependency patches, the Python transitive lock, and runtime vulnerability remediation
remain the owner's responsibility. Pins are needed for reproducibility, but they do not guarantee security by themselves.
