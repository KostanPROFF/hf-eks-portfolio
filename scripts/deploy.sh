#!/usr/bin/env bash
set -euo pipefail
: "${IMAGE:?Set IMAGE to ECR URL@sha256:digest}"
[[ "$IMAGE" =~ @sha256:[a-f0-9]{64}$ ]] || { echo 'Use an immutable image digest' >&2; exit 1; }
# Structural changes are bootstrapped by an administrator. CI changes only the image.
kubectl -n inference set image deployment/inference "api=$IMAGE"
kubectl -n inference rollout status deployment/inference --timeout=600s
