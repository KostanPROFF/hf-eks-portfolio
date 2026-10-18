# Security design

- Human bootstrap IAM role получает cluster admin через EKS access entry. Creator implicit admin выключен.
- GitHub build role: ECR token (AWS требует Resource *) и repository-scoped upload/read.
- GitHub deploy role: DescribeCluster ровно одного кластера; EKS group → namespaced Role,
  только get/list/patch/watch конкретного Deployment. Нет cluster admin, Secrets read или RBAC writes.
- GitHub OIDC aud/sub exact matches. Environment production должен ограничивать branches и reviewers.
- Pod service account token не монтируется, UID 10001, read-only root, dropped capabilities,
  IMDSv2 required/hop-limit 1. У приложения нет AWS API permissions; ECR pull делает node role.
- Nodes private; API public restricted CIDRs + private endpoint. SSH key/порт 22 не создаются.
- EKS module включает at-rest envelope encryption по своим defaults; root EBS encryption задаётся явно.
- Optional LBC получает EKS Pod Identity; upstream policy содержит необходимые EC2 describe
  wildcard и tag conditions, находится в terraform/policies и требует review при обновлении chart.
- Secrets: Grafana admin генерируется при install, хранится в Kubernetes Secret. В Terraform state и Git
  пароль не попадает. Для реального приложения используйте Secrets Manager + Pod Identity + CSI/External Secrets,
  не кладите токены в tfvars, image, workflow variables или Docker build args.
- Нет NetworkPolicy enforcement в базовом варианте; внутренний Service не является authentication boundary.
  Доступ из других namespaces возможен. Для production включите VPC CNI network policy и проверьте
  DNS/metrics/client ingress + default deny по фактической схеме трафика.

## Remote state для команды

Backend создаётся отдельно от основного stack, чтобы destroy стенда не удалил state.
Создайте уникальный S3 bucket в своём аккаунте: Block Public Access, versioning, default SSE-KMS,
TLS-only bucket policy, restricted IAM для state prefix и lockfile. Подготовьте KMS key policy.
В отдельном `terraform/backend.tf` (без credentials):

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

Выполните `terraform -chdir=terraform init -migrate-state` под уполномоченной role.
Сначала проверьте backup и доступ ко всем версиям state. IAM backend должен разрешать
s3 ListBucket prefix, GetObject/PutObject на state и GetObject/PutObject/DeleteObject на `.tflock`,
KMS Encrypt/Decrypt/GenerateDataKey. GitHub deploy/build backend не нужен.
Не сохраняйте credentials в backend config: Terraform кеширует его параметры на диске.

## Threat model и границы

Repository writers с доступом к main и environment могут исполнять CI и менять приложение.
Restrict runner group, branch protections, reviewers, workflow CODEOWNERS и ephemeral runners обязательны
перед использованием с недоверенными contributors. Не запускайте fork PR на self-hosted runner.
Текущее ограничение Role не запрещает доверенному CD менять pod spec — это не sandbox от злонамеренного main.
EKS/node/addon dependency patches, Python transitive lock и runtime vulnerability remediation
остаются обязанностью владельца. Pins нужны для повторяемости, но сами по себе не гарантируют безопасность.
