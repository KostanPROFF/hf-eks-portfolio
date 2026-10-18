#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
# Avoid password in argv, shell history, repository, or Terraform state.
if ! kubectl -n monitoring get secret grafana-admin >/dev/null 2>&1; then
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  chmod 700 "$tmpdir"
  printf admin > "$tmpdir/admin-user"
  openssl rand -base64 32 > "$tmpdir/admin-password"
  kubectl -n monitoring create secret generic grafana-admin     --from-file=admin-user="$tmpdir/admin-user" --from-file=admin-password="$tmpdir/admin-password"
fi
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack   --version 75.15.0 --namespace monitoring -f "$root/monitoring/values.yaml" --wait --timeout 15m
kubectl apply -f "$root/monitoring/inference.yaml"
kubectl -n monitoring create configmap inference-dashboard   --from-file=inference.json="$root/monitoring/dashboard.json" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring label configmap inference-dashboard grafana_dashboard=1 --overwrite
