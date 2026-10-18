# Проверки поставки

Дата: 18 октября 2026. Среда: macOS arm64, Python 3.12.13, Terraform 1.12.2,
kubectl 1.35.0, Helm 3.17.3, kubeconform 0.7.0, actionlint 1.7.7.

## Выполнено

| Проверка | Результат |
|---|---|
| pytest, Python 3.12 | 7 passed |
| Ruff: app, tests, model downloader | Passed |
| Реальный CPU inference через FastAPI TestClient, без подмены модели | Passed |
| Offline загрузка model/tokenizer из локально сохранённых safetensors | Passed |
| Positive: `This product is excellent` | POSITIVE, score 0.9998741 |
| Negative: `This is terrible and disappointing` | NEGATIVE, score 0.9997938 |
| Readiness и Prometheus histogram на настоящей модели | Passed |
| Terraform init -backend=false | Passed, без обращения к AWS account |
| Terraform fmt -check + validate | Passed |
| Provider lock для darwin_arm64 и linux_amd64 | Получены подписанные HashiCorp checksums |
| Kustomize base + internal-NLB overlay | Rendered |
| kubeconform: base, NLB overlay, GPU Deployment | 13 valid, 0 invalid |
| kubeconform: deploy Role/RoleBinding | 2 valid, 0 invalid |
| Helm template: kube-prometheus-stack 75.15.0 и LBC chart 1.13.3 | Rendered |
| kubeconform: rendered monitoring/LBC + inference monitoring CRs | 74 valid, 42 CR/CRD schemas skipped, 0 invalid |
| Helm template NVIDIA plugin 0.17.1 + kubeconform | Rendered, 2 valid |
| GitHub workflow actionlint | Passed; custom eks-vpc runner label зарегистрирован в config |
| Shell scripts bash -n; JSON/YAML parse | Passed |
| Linux cp312 CPU/CUDA wheels выбранных torch версий | Наличие проверено в официальных PyTorch indexes |

Реальный smoke выполнен с torch 2.14.1, transformers 5.20.1, fastapi 0.146.0.
Использована закреплённая модель revision `714eb0fa89d2f80546fda750413ed43d93601a13`.
Для host smoke модель сохранена в рабочем каталоге и MODEL_PATH переопределён;
приложение работало с HF_HUB_OFFLINE=1 / TRANSFORMERS_OFFLINE=1.
Веса не включены в архив: они скачиваются на стадии Docker build.

## Не выполнено

- Docker build/run на Linux: Docker отсутствует в среде подготовки.
  Workflow содержит настоящий Docker smoke до ECR push, но GitHub run не запускался.
- Terraform plan/apply/destroy против AWS account; EKS creation, addon compatibility и доступность capacity.
- Live cluster smoke, runner registration/networking, GitHub OIDC assumption, ECR push и CD rollout.
- Реальный Prometheus scrape/Grafana UI/HPA scale/rollback/load test на EKS.
- GPU build, NVIDIA driver/runtime integration и inference на CUDA.
- Запрос актуального account-specific pricing, billing verification и измерение производительности.

Terraform validate не доказывает успешный AWS deploy. Helm rendering не проверяет runtime admission,
CRD compatibility, webhook доступность или наличие AWS permissions. Пропущенные CR schemas указаны явно.
Actionlint запускался без ShellCheck; shell syntax отдельно проверен bash -n.
Перед заявлением о завершённом AWS deployment пройдите checklist в OPERATIONS.md.

## Повторить основные проверки

```bash
python -m pytest -q
ruff check app tests scripts/download_model.py
terraform -chdir=terraform init -backend=false
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
kubectl kustomize k8s/base > /tmp/hf-base.yaml
kubectl kustomize k8s/overlays/internal-nlb > /tmp/hf-nlb.yaml
kubeconform -strict -summary -kubernetes-version 1.35.0 \
  /tmp/hf-base.yaml /tmp/hf-nlb.yaml k8s/bootstrap/deploy-rbac.yaml examples/gpu/deployment.yaml
actionlint -config-file .github/actionlint.yaml .github/workflows/ci-cd.yaml
# Затем Docker build/run и scripts/smoke.sh из README.
```
