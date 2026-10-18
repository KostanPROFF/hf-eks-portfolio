#!/usr/bin/env bash
set -euo pipefail
: "${CLUSTER_NAME:?}" "${AWS_REGION:?}" "${VPC_ID:?}"
helm repo add eks https://aws.github.io/eks-charts
helm repo update
# Requires enable_load_balancer_controller=true and terraform apply first.
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller  --version 1.13.3 --namespace kube-system  --set "clusterName=$CLUSTER_NAME" --set "region=$AWS_REGION" --set "vpcId=$VPC_ID"  --set serviceAccount.name=aws-load-balancer-controller  --wait --timeout 5m
