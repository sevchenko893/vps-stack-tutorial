#!/usr/bin/env bash
# Pakai: VPS_IP=203.0.113.10 bash scripts/install-rancher.sh
set -euo pipefail
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
: "${VPS_IP:?set VPS_IP}"
RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-rancher.${VPS_IP}.sslip.io}"
BOOTSTRAP_PASSWORD="${BOOTSTRAP_PASSWORD:-admin}"

helm repo add rancher-latest https://releases.rancher.com/server-charts/latest --force-update
helm repo update

helm upgrade --install rancher rancher-latest/rancher \
  --namespace cattle-system --create-namespace \
  --set hostname="$RANCHER_HOSTNAME" \
  --set bootstrapPassword="$BOOTSTRAP_PASSWORD" \
  --set replicas=1 \
  --set ingress.ingressClassName=traefik \
  --set resources.requests.memory=1Gi \
  --set resources.limits.memory=2Gi \
  --wait --timeout=10m

echo "Rancher: https://$RANCHER_HOSTNAME  (password awal: $BOOTSTRAP_PASSWORD)"
