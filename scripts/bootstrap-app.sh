#!/usr/bin/env bash
set -euo pipefail
: "${IMAGE:?Set IMAGE to ECR URL@sha256:digest}"
[[ "$IMAGE" =~ @sha256:[a-f0-9]{64}$ ]] || { echo 'Use an immutable image digest' >&2; exit 1; }
root=$(cd "$(dirname "$0")/.." && pwd)
overlay=${OVERLAY:-base}
[[ "$overlay" == base || "$overlay" == overlays/internal-nlb ]] || exit 1
# Render in a temporary copy so deployment values never dirty the repository.
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
cp -R "$root/k8s" "$tmpdir/k8s"
cat >> "$tmpdir/k8s/$overlay/kustomization.yaml" <<EOF
images:
  - name: inference-image
    newName: ${IMAGE%@*}
    digest: ${IMAGE#*@}
EOF
kubectl apply -k "$tmpdir/k8s/$overlay"
kubectl apply -f "$root/k8s/bootstrap/deploy-rbac.yaml"
kubectl -n inference rollout status deployment/inference --timeout=600s
