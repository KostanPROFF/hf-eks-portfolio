# Опциональный GPU-эксперимент

CPU-модели DistilBERT GPU обычно не нужен. Этот пример показывает отдельный tainted node group,
CUDA-образ и GPU resource scheduling. Он не участвует в основном pipeline и не проверен на AWS.

1. В `terraform.tfvars` включите `enable_gpu = true`, затем выполните plan/apply.
   По умолчанию desired=0: EC2 GPU пока не запущен. Проверьте квоту G/VT On-Demand vCPU.
2. Включите одну GPU-ноду под административной AWS role:

```bash
GPU_NODE_GROUP=$(terraform -chdir=terraform output -raw gpu_node_group_name)
aws eks update-nodegroup-config --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name "$GPU_NODE_GROUP" --region "$AWS_REGION" \
  --scaling-config minSize=0,maxSize=1,desiredSize=1
aws eks wait nodegroup-active --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name "$GPU_NODE_GROUP" --region "$AWS_REGION"
```

   Модуль игнорирует последующие изменения desired_size; используйте AWS API для ручной capacity.
   Cluster Autoscaler не установлен.
3. Установите NVIDIA device plugin (драйвер уже входит в EKS NVIDIA AMI):

```bash
helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
helm repo update
helm upgrade --install nvdp nvdp/nvidia-device-plugin --version 0.17.1   --namespace gpu-system --create-namespace   --set nodeSelector.workload=gpu --wait
kubectl get nodes -l workload=gpu -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu
```

Plugin DaemonSet использует привилегии/host mounts по своим системным требованиям;
namespace `gpu-system` не должен иметь restricted Pod Security policy. Приложение остаётся restricted.
Plugin chart по умолчанию tolerates `nvidia.com/gpu`; проверьте `helm get values nvdp -n gpu-system -a`.

4. Соберите образ из корня репозитория, опубликуйте в ECR под отдельным уникальным тегом и
   замените `GPU_IMAGE_REPLACE_WITH_DIGEST` в deployment.yaml на полный `ECR_URL@sha256:...`:

```bash
docker build --platform linux/amd64 -f examples/gpu/Dockerfile -t hf-gpu .
# docker tag / docker push — аналогично основному README, но отдельный тег sha-gpu-...
kubectl apply -f examples/gpu/deployment.yaml
kubectl -n inference rollout status deployment/inference-gpu --timeout=600s
kubectl -n inference port-forward deployment/inference-gpu 8001:8000
bash scripts/smoke.sh http://127.0.0.1:8001
```

Не направляйте CPU Service на GPU Deployment: у них разные labels. Проверяйте CUDA/driver compatibility,
`nvidia-smi` на ноде и наличие `nvidia.com/gpu` перед запуском. CUDA image значительно больше CPU.
Для cleanup сначала удалите Deployment, затем Helm plugin, установите enable_gpu=false
и выполните Terraform plan/apply — GPU-группа удалится вместе с нодой. Не оставляйте g4dn включённым после демонстрации.
