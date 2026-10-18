# Operations

## Acceptance после реального запуска

1. `terraform plan` после apply не показывает неожиданных изменений.
2. Две Ready CPU-ноды, system pods Running, `kubectl top nodes` работает.
3. Inference replicas Ready; pod не root, нет service-account token mount, image указан digest.
4. `scripts/smoke.sh` возвращает POSITIVE, invalid JSON/empty/too-long text → 422.
5. Prometheus Targets показывает inference UP; dashboard содержит трафик; restart pod восстанавливает API.
6. После контролируемой нагрузки HPA показывает CPU, меняет replicas в пределах capacity;
   после 180s и снижения нагрузки возвращается к minimum. Это требует реального load test.
7. Новое main изменение создаёт уникальный tag/digest; production gate ждёт review; rollout проходит.
8. Под deploy role проверьте `kubectl auth can-i get secrets -n inference` → no,
   `kubectl auth can-i patch deployment/inference -n inference` → yes.
9. Internal NLB (если включён) работает из VPC и не доступен из публичного интернета.

## Runner networking

Runner требует VPC DNS resolution, egress HTTPS через NAT и ingress TCP 443
от runner SG в cluster primary SG. Это scoped правило создайте отдельно после получения output
`cluster_security_group_id` (или Terraform ресурсы runner в отдельном stack).
EKS private endpoint DNS должен разрешаться в VPC IP. На runner сначала под человеческой role
проверьте connectivity, затем под OIDC deploy role — `aws eks describe-cluster`, update-kubeconfig,
`kubectl -n inference get deployment inference`. Таймаут означает сеть/DNS/SG, Unauthorized — IAM/access entry,
Forbidden — namespace RBAC. Нельзя решать network timeout выдачей cluster admin.
У runner должен быть доступ к GitHub, Actions artifacts, STS и AWS APIs.

## Диагностика

```bash
kubectl -n inference get pods -o wide
kubectl -n inference describe deployment inference
kubectl -n inference describe hpa inference
kubectl -n inference get events --sort-by=.lastTimestamp
kubectl -n inference logs deployment/inference --tail=100
kubectl -n kube-system get pods
kubectl -n monitoring get servicemonitor -A
```

ImagePullBackOff: проверьте repository region/digest и node ECR role.
Pending: запросы ресурсов и taints; HPA не увеличивает node group. Модуль EKS игнорирует
изменения desired_size после создания группы: ручное масштабирование выполняйте через
`aws eks update-nodegroup-config`, а min/max меняйте в Terraform.
CrashLoop/OOM: startup logs, memory limit, локальные веса; модель нельзя докачать в offline runtime.
HPA unknown: Metrics Server add-on, requests.cpu, `kubectl top pods -n inference`.
Grafana no data: Service labels, ServiceMonitor selector, `/metrics/`, Prometheus Targets и rate window.
CPU throttling/429: нагрузка выше capacity; сначала измерьте latency/requests и доступные ресурсы.

## Rollback

CI rollout failure оставляет job failed; автоматического rollback нет. Под администратором:

```bash
kubectl -n inference rollout history deployment/inference
kubectl -n inference rollout undo deployment/inference
kubectl -n inference rollout status deployment/inference --timeout=600s
```

Или запустите `IMAGE=ECR_URL@sha256:PREVIOUS_DIGEST bash scripts/deploy.sh` из runner/VPC.
Проверьте, что предыдущий image ещё существует в ECR; lifecycle хранит только 20 tagged images.
Затем smoke и Grafana errors/latency. Сохраните known-good digest отдельно; rollback нельзя доказать
одним успешным `rollout undo` без проверки prediction.

## Регистрация одноразового runner

В собственном repo откройте Settings → Actions → Runners → New self-hosted runner, Linux x64.
На отдельной VM в private subnet выполните показанные GitHub команды download/checksum/extract
под обычным пользователем; установите AWS CLI/kubectl/Git. Не используйте control-plane/node instance
или долгоживущий личный компьютер в качестве production runner.
Вместо обычной регистрации используйте one-job режим:

```bash
# В каталоге скачанного GitHub runner, под непривилегированным пользователем:
read -r -s -p 'Temporary runner registration token: ' RUNNER_REGISTRATION_TOKEN
./config.sh --url https://github.com/KostanPROFF/hf-eks-portfolio \
  --token "$RUNNER_REGISTRATION_TOKEN" --name hf-eks-ephemeral \
  --labels eks-vpc --ephemeral --unattended
unset RUNNER_REGISTRATION_TOKEN
./run.sh
```

Registration token берите из собственного GitHub UI при регистрации, не сохраняйте его в Terraform/Git.
После одного deploy job runner снимается с регистрации; удалите VM/диск и создайте новый для следующего запуска.
В командной эксплуатации автоматизируйте lifecycle через GitHub App/JIT runners в отдельном защищённом stack.
Network/VM cost, registration и teardown runner не включены в основной Terraform.
[Документация GitHub runners](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/adding-self-hosted-runners).
