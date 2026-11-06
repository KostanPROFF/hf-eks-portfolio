# Optional GPU experiment

The DistilBERT CPU model usually does not need a GPU. This example shows a separate tainted node group,
a CUDA image and GPU resource scheduling. It is not part of the main pipeline and has not been tested on AWS.

1. In `terraform.tfvars` set `enable_gpu = true`, then run plan/apply.
   By default desired=0: no GPU EC2 instance is started yet. Check your G/VT On-Demand vCPU quota.
2. Bring up one GPU node under the administrative AWS role:

```bash
GPU_NODE_GROUP=$(terraform -chdir=terraform output -raw gpu_node_group_name)
aws eks update-nodegroup-config --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name "$GPU_NODE_GROUP" --region "$AWS_REGION" \
  --scaling-config minSize=0,maxSize=1,desiredSize=1
aws eks wait nodegroup-active --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name "$GPU_NODE_GROUP" --region "$AWS_REGION"
```

   The module ignores subsequent desired_size changes; use the AWS API for manual capacity.
   Cluster Autoscaler is not installed.
3. Install the NVIDIA device plugin (the driver is already included in the EKS NVIDIA AMI):

```bash
helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
helm repo update
helm upgrade --install nvdp nvdp/nvidia-device-plugin --version 0.17.1   --namespace gpu-system --create-namespace   --set nodeSelector.workload=gpu --wait
kubectl get nodes -l workload=gpu -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\.com/gpu
```

The plugin DaemonSet uses privileges/host mounts per its system requirements;
the `gpu-system` namespace must not have a restricted Pod Security policy. The application stays restricted.
The plugin chart tolerates `nvidia.com/gpu` by default; verify with `helm get values nvdp -n gpu-system -a`.

4. Build the image from the repository root, push it to ECR under a separate unique tag, and
   replace `GPU_IMAGE_REPLACE_WITH_DIGEST` in deployment.yaml with the full `ECR_URL@sha256:...`:

```bash
docker build --platform linux/amd64 -f examples/gpu/Dockerfile -t hf-gpu .
# docker tag / docker push — same as in the main README, but with a separate sha-gpu-... tag
kubectl apply -f examples/gpu/deployment.yaml
kubectl -n inference rollout status deployment/inference-gpu --timeout=600s
kubectl -n inference port-forward deployment/inference-gpu 8001:8000
bash scripts/smoke.sh http://127.0.0.1:8001
```

Do not point the CPU Service at the GPU Deployment: they have different labels. Check CUDA/driver compatibility,
`nvidia-smi` on the node and the presence of `nvidia.com/gpu` before running. The CUDA image is much larger than the CPU one.
For cleanup, delete the Deployment first, then the Helm plugin, set enable_gpu=false
and run Terraform plan/apply — the GPU group is removed along with its node. Do not leave g4dn running after the demo.
