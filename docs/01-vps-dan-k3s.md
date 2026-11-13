# 1. VPS + k3s

## 1.1 Dasar OS

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl ca-certificates ufw
```

## 1.2 Swap (wajib kalau RAM 8 GB)

Rancher + Traefik + cert-manager + 3 workload bisa menyentuh 5 GB. Tanpa swap, pod ke-`OOMKilled`.

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
sudo swapon --show
```

## 1.3 Firewall

```bash
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status
```

Port 6443 (k3s API) **jangan** dibuka ke publik. Semua `kubectl` di tutorial ini jalan di VPS itu sendiri.

## 1.4 Install k3s

Pin versi supaya reproducible:

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode=644" \
  INSTALL_K3S_VERSION="v1.31.2+k3s1" sh -
```

k3s sudah membawa **Traefik** (ingress) dan **local-path** provisioner — tidak perlu install ingress controller sendiri.

## 1.5 kubeconfig untuk user non-root

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
chmod 600 ~/.kube/config
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
source ~/.bashrc
```

Tanpa `KUBECONFIG` eksplisit, `kubectl` mencoba `/etc/rancher/k3s/k3s.yaml` dan gagal dengan `permission denied`.

## 1.6 Verifikasi

```bash
kubectl get nodes -o wide
kubectl get sc              # local-path (default)
kubectl get pods -n kube-system | grep -E 'traefik|coredns'
kubectl get svc -n kube-system traefik   # LoadBalancer, EXTERNAL-IP = IP VPS
```

Catat dua hal, dipakai nanti:

```bash
kubectl get nodes -o jsonpath='{.items[0].status.addresses[0].address}'   # IP internal node, mis. 10.20.0.38
kubectl get svc -n kube-system traefik -o jsonpath='{.spec.clusterIP}'    # mis. 10.43.4.137
```
