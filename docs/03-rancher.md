# 3. Rancher (UI manajemen cluster)

```bash
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update

export VPS_IP="203.0.113.10"
export RANCHER_HOSTNAME="rancher.${VPS_IP}.sslip.io"

helm install rancher rancher-latest/rancher \
  --namespace cattle-system --create-namespace \
  --set hostname=$RANCHER_HOSTNAME \
  --set bootstrapPassword=admin \
  --set replicas=1 \
  --set ingress.ingressClassName=traefik

kubectl -n cattle-system rollout status deploy/rancher
```

Rancher memakai cert-manager yang sudah ada (tidak install sendiri) dan membuat Issuer `rancher` + Ingress TLS sendiri.

## Tuning resource (penting di VPS kecil)

Default chart memberi request kecil tapi bisa OOM saat UI dipakai. Naikkan limit:

```bash
helm upgrade rancher rancher-latest/rancher -n cattle-system --reuse-values \
  --set resources.requests.memory=1Gi \
  --set resources.limits.memory=2Gi
```

## Login pertama

1. Buka `https://$RANCHER_HOSTNAME` (sertifikat LE, tunggu ~1 menit sampai `kubectl -n cattle-system get certificate` = `True`).
2. Password awal: `admin` (dari `bootstrapPassword`). Rancher minta ganti password.
3. Simpan URL-nya — itu satu-satunya akses UI.

Ambil password bootstrap dari secret kalau lupa:

```bash
kubectl -n cattle-system get secret bootstrap-secret \
  -o jsonpath='{.data.bootstrapPassword}' | base64 -d
```

## Yang didapat

Rancher meng-install otomatis: `fleet`, `fleet-crd`, `fleet-agent-local`, `rancher-webhook`, `rancher-turtles`, `system-upgrade-controller` di namespace `cattle-*`. Itu ~1.5 GB RAM. Karena itu swap wajib.

Semua resource aplikasi tetap bisa dibuat lewat `kubectl` biasa — Rancher hanya lapisan UI/manajemen. Tutorial ini memakai `kubectl` + YAML di repo supaya bisa di-CI.
