#!/usr/bin/env bash
set -euo pipefail
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
CM_VERSION="${CM_VERSION:-v1.16.2}"

helm repo add jetstack https://charts.jetstack.io --force-update
helm repo update

kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CM_VERSION}/cert-manager.crds.yaml"

if helm -n cert-manager status cert-manager >/dev/null 2>&1; then
  echo "cert-manager sudah ada, skip install"
else
  helm install cert-manager jetstack/cert-manager \
    --namespace cert-manager --create-namespace --version "$CM_VERSION"
fi

kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=300s
