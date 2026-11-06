# Delivery checks

Date: October 18, 2026. Environment: macOS arm64, Python 3.12.13, Terraform 1.12.2,
kubectl 1.35.0, Helm 3.17.3, kubeconform 0.7.0, actionlint 1.7.7.

## Done

| Check | Result |
|---|---|
| pytest, Python 3.12 | 7 passed |
| Ruff: app, tests, model downloader | Passed |
| Real CPU inference via FastAPI TestClient, no model mocking | Passed |
| Offline loading of model/tokenizer from locally saved safetensors | Passed |
| Positive: `This product is excellent` | POSITIVE, score 0.9998741 |
| Negative: `This is terrible and disappointing` | NEGATIVE, score 0.9997938 |
| Readiness and Prometheus histogram with the real model | Passed |
| Terraform init -backend=false | Passed, without contacting an AWS account |
| Terraform fmt -check + validate | Passed |
| Provider lock for darwin_arm64 and linux_amd64 | Signed HashiCorp checksums obtained |
| Kustomize base + internal-NLB overlay | Rendered |
| kubeconform: base, NLB overlay, GPU Deployment | 13 valid, 0 invalid |
| kubeconform: deploy Role/RoleBinding | 2 valid, 0 invalid |
| Helm template: kube-prometheus-stack 75.15.0 and LBC chart 1.13.3 | Rendered |
| kubeconform: rendered monitoring/LBC + inference monitoring CRs | 74 valid, 42 CR/CRD schemas skipped, 0 invalid |
| Helm template NVIDIA plugin 0.17.1 + kubeconform | Rendered, 2 valid |
| GitHub workflow actionlint | Passed; custom eks-vpc runner label registered in config |
| Shell scripts bash -n; JSON/YAML parse | Passed |
| Linux cp312 CPU/CUDA wheels for the selected torch versions | Availability verified in official PyTorch indexes |

The real smoke test was run with torch 2.14.1, transformers 5.20.1, fastapi 0.146.0.
The pinned model revision `714eb0fa89d2f80546fda750413ed43d93601a13` was used.
For the host smoke test the model was saved in the working directory and MODEL_PATH was overridden;
the application ran with HF_HUB_OFFLINE=1 / TRANSFORMERS_OFFLINE=1.
Weights are not included in the archive: they are downloaded during the Docker build stage.

## Not done

- Docker build/run on Linux: Docker was not available in the preparation environment.
  The workflow contains a real Docker smoke test before ECR push, but no GitHub run has been executed.
- Terraform plan/apply/destroy against an AWS account; EKS creation, add-on compatibility and capacity availability.
- Live cluster smoke, runner registration/networking, GitHub OIDC assumption, ECR push and CD rollout.
- Real Prometheus scrape/Grafana UI/HPA scaling/rollback/load test on EKS.
- GPU build, NVIDIA driver/runtime integration and inference on CUDA.
- Fetching current account-specific pricing, billing verification and performance measurement.

Terraform validate does not prove a successful AWS deploy. Helm rendering does not check runtime admission,
CRD compatibility, webhook availability or AWS permissions. Skipped CR schemas are listed explicitly.
Actionlint was run without ShellCheck; shell syntax was checked separately with bash -n.
Before claiming a completed AWS deployment, go through the checklist in OPERATIONS.md.

## Re-run the main checks

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
# Then Docker build/run and scripts/smoke.sh from the README.
```
