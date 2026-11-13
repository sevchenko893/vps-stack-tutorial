# 18. Kalau traffic naik

Tanda sudah tidak cukup satu VPS:

- RAM > 90% terus-menerus walau swap aktif.
- `php artisan serve` (single-threaded) jadi bottleneck — request mengantre.
- Butuh zero-downtime deploy; `Recreate` di Postgres dan 1 replika membuat deploy = downtime singkat.
- Butuh > 1 aplikasi dengan isolasi lebih kuat.

## 18.1 Naikkan dulu di VPS yang sama (murah)

**a. Laravel: php-fpm + nginx** — `php artisan serve` adalah dev server, satu proses. Ganti:

```dockerfile
FROM php:8.3-fpm-alpine
RUN apk add --no-cache nginx supervisor libpq libzip
# ... copy nginx.conf ke /etc/nginx/http.d/default.conf
CMD ["supervisord", "-c", "/etc/supervisord.conf"]
```

Naik throughput 5–10x pada CPU yang sama.

**b. Replika horizontal untuk web/api** (stateless, aman):

```bash
kubectl -n app scale deploy/web --replicas=3
kubectl -n app scale deploy/api --replicas=2
```

Syarat: session/cache di `database` (sudah), tidak ada file upload ke filesystem lokal pod (kalau ada → object storage).

**c. Tambah swap / resize disk** — PVC `local-path` tidak bisa di-expand. Resize = bikin PVC baru + copy data, atau resize VPS disk lalu recreate.

**d. Redis** untuk cache/queue/session — hilangkan beban tulis ke Postgres:

```bash
helm install redis bitnami/redis -n app --set architecture=standalone --set auth.enabled=false
# lalu: CACHE_STORE=redis, SESSION_DRIVER=redis, REDIS_HOST=redis-master
```

## 18.2 Multi-node

k3s agent di VPS kedua, join ke server:

```bash
# di server (VPS 1)
cat /var/lib/rancher/k3s/server/node-token
# di VPS 2
curl -sfL https://get.k3s.io | K3S_URL=https://<ip-vps1>:6443 K3S_TOKEN=<token> sh -
```

Yang **harus** berubah setelah multi-node:

| Masalah | Solusi |
|---|---|
| `local-path` PVC terikat ke satu node | Longhorn / NFS / Rook-Ceph |
| Traefik LoadBalancer hanya di satu node | MetalLB atau keep single ingress node |
| Postgres `Recreate` + RWO | operator (CloudNativePG) atau managed DB |
| Rancher 1 replika | `replicas: 3` + replicated PVC |
| Ingress tidak tahu IP publik | pastikan LB mengarah ke node ingress |

## 18.3 Titik pindah ke managed service

| Komponen | Kapan ditinggalkan |
|---|---|
| Postgres di cluster | Butuh PITR, read replica, HA, atau backup otomatis dengan SLA |
| 9Router self-host | Butuh audit log, quota per tim, SSO |
| Rancher | > 3 cluster atau butuh RBAC multi-tenant |
| Self-hosted runner | Butuh build paralel banyak / build ARM |

## 18.4 Yang tidak perlu dilakukan sekarang

- Service mesh (Istio/Linkerd) — 3 service tidak butuh mTLS antar-pod.
- Kubernetes multi-cluster + Fleet — satu cluster cukup.
- Autoscaling (HPA) — tanpa metrics-server + beban terukur, HPA hanya menambah variabel.
- GitOps (ArgoCD/Flux) — `kubectl set image` dari CI sudah cukup untuk 2 deployment.

Aturan: tambah komponen hanya setelah ada metrik yang membuktikan kebutuhan, bukan setelah membaca artikel.
