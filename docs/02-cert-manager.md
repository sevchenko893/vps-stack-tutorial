# 2. cert-manager + Let's Encrypt

cert-manager mengurus sertifikat TLS otomatis dari Ingress annotation.

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.2/cert-manager.crds.yaml

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version v1.16.2

kubectl -n cert-manager rollout status deploy/cert-manager-webhook
```

## ClusterIssuer

Cluster-scoped, sekali pakai untuk semua namespace:

```bash
export ACME_EMAIL="you@example.com"
envsubst < manifests/clusterissuer-letsencrypt.yaml | kubectl apply -f -
kubectl get clusterissuer letsencrypt-prod
```

Isi file: [manifests/clusterissuer-letsencrypt.yaml](../manifests/clusterissuer-letsencrypt.yaml) — solver `http01` via `ingressClassName: traefik`.

## Verifikasi

```bash
kubectl get clusterissuer letsencrypt-prod -o jsonpath='{.status.conditions[0]}'
# {"type":"Ready","status":"True","reason":"ACMEAccountRegistered",...}
```

Status `False` + `reason: ErrRegisterACMEAccount`? Biasanya email invalid atau port 80 tidak terbuka. Cek `kubectl -n cert-manager logs deploy/cert-manager`.

## Catatan penting

- HTTP-01 challenge butuh port **80** reachable dari internet. Kalau Cloudflare proxy aktif (orange cloud), challenge akan gagal — set DNS-only dulu saat penerbitan pertama.
- ClusterIssuer butuh izin cluster-level. Kalau pakai Rancher, pastikan user punya role `Cluster Owner`, bukan cuma project member.
