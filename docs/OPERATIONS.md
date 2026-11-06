# Operations

## Acceptance after a real run

1. `terraform plan` after apply shows no unexpected changes.
2. Two Ready CPU nodes, system pods Running, `kubectl top nodes` works.
3. Inference replicas are Ready; the pod is not root, has no service-account token mount, and the image is referenced by digest.
4. `scripts/smoke.sh` returns POSITIVE; invalid JSON/empty/too-long text → 422.
5. Prometheus Targets shows inference UP; the dashboard shows traffic; restarting a pod restores the API.
6. Under controlled load, HPA shows CPU and changes replicas within capacity;
   after 180s and reduced load it returns to the minimum. This requires a real load test.
7. A new change on main produces a unique tag/digest; the production gate waits for review; rollout succeeds.
8. Under the deploy role, check `kubectl auth can-i get secrets -n inference` → no,
   `kubectl auth can-i patch deployment/inference -n inference` → yes.
9. The internal NLB (if enabled) works from the VPC and is not reachable from the public internet.

## Runner networking

The runner needs VPC DNS resolution, HTTPS egress via NAT, and ingress TCP 443
from the runner SG to the cluster primary SG. Create this scoped rule separately after getting the
`cluster_security_group_id` output (or keep the runner's Terraform resources in a separate stack).
The EKS private endpoint DNS must resolve to a VPC IP. On the runner, first check connectivity under a human role,
then under the OIDC deploy role — `aws eks describe-cluster`, update-kubeconfig,
`kubectl -n inference get deployment inference`. A timeout means network/DNS/SG, Unauthorized means IAM/access entry,
Forbidden means namespace RBAC. Never fix a network timeout by granting cluster admin.
The runner must have access to GitHub, Actions artifacts, STS and AWS APIs.

## Troubleshooting

```bash
kubectl -n inference get pods -o wide
kubectl -n inference describe deployment inference
kubectl -n inference describe hpa inference
kubectl -n inference get events --sort-by=.lastTimestamp
kubectl -n inference logs deployment/inference --tail=100
kubectl -n kube-system get pods
kubectl -n monitoring get servicemonitor -A
```

ImagePullBackOff: check the repository region/digest and the node ECR role.
Pending: resource requests and taints; HPA does not grow the node group. The EKS module ignores
desired_size changes after the group is created: scale manually via
`aws eks update-nodegroup-config`, and change min/max in Terraform.
CrashLoop/OOM: startup logs, memory limit, local weights; the model cannot be downloaded in the offline runtime.
HPA unknown: Metrics Server add-on, requests.cpu, `kubectl top pods -n inference`.
Grafana no data: Service labels, ServiceMonitor selector, `/metrics/`, Prometheus Targets and the rate window.
CPU throttling/429: load exceeds capacity; first measure latency/requests and available resources.

## Rollback

A CI rollout failure leaves the job failed; there is no automatic rollback. As an administrator:

```bash
kubectl -n inference rollout history deployment/inference
kubectl -n inference rollout undo deployment/inference
kubectl -n inference rollout status deployment/inference --timeout=600s
```

Or run `IMAGE=ECR_URL@sha256:PREVIOUS_DIGEST bash scripts/deploy.sh` from the runner/VPC.
Make sure the previous image still exists in ECR; the lifecycle policy keeps only 20 tagged images.
Then run smoke and check Grafana errors/latency. Keep a known-good digest on record; a rollback is not proven
by a successful `rollout undo` alone without checking predictions.

## Registering a single-use runner

In your own repo, open Settings → Actions → Runners → New self-hosted runner, Linux x64.
On a separate VM in a private subnet, run the download/checksum/extract commands shown by GitHub
as a regular user; install AWS CLI/kubectl/Git. Do not use a control-plane/node instance
or a long-lived personal computer as a production runner.
Instead of a regular registration, use one-job mode:

```bash
# In the downloaded GitHub runner directory, as an unprivileged user:
read -r -s -p 'Temporary runner registration token: ' RUNNER_REGISTRATION_TOKEN
./config.sh --url https://github.com/KostanPROFF/hf-eks-portfolio \
  --token "$RUNNER_REGISTRATION_TOKEN" --name hf-eks-ephemeral \
  --labels eks-vpc --ephemeral --unattended
unset RUNNER_REGISTRATION_TOKEN
./run.sh
```

Get the registration token from your own GitHub UI during registration; do not store it in Terraform/Git.
After one deploy job the runner is unregistered; delete the VM/disk and create a new one for the next run.
For team operations, automate the lifecycle with GitHub App/JIT runners in a separate protected stack.
Runner network/VM cost, registration and teardown are not included in the main Terraform.
[GitHub runners documentation](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/adding-self-hosted-runners).
