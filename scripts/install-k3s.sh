#!/usr/bin/env bash
# k3s + kubeconfig user. Idempoten: aman dijalankan ulang.
set -euo pipefail

K3S_VERSION="${K3S_VERSION:-v1.31.2+k3s1}"

if command -v k3s >/dev/null 2>&1; then
  echo "k3s sudah terpasang: $(k3s --version | head -1)"
else
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode=644" \
    INSTALL_K3S_VERSION="$K3S_VERSION" sh -
fi

mkdir -p "$HOME/.kube"
sudo cp /etc/rancher/k3s/k3s.yaml "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
chmod 600 "$HOME/.kube/config"
grep -q 'KUBECONFIG=~/.kube/config' "$HOME/.bashrc" \
  || echo 'export KUBECONFIG=~/.kube/config' >> "$HOME/.bashrc"

export KUBECONFIG="$HOME/.kube/config"
kubectl get nodes -o wide
kubectl get svc -n kube-system traefik
