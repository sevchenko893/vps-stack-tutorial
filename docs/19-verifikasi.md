# 19. Checklist verifikasi (buktikan tiap tahap berhasil)

Jalankan blok ini **setelah** tiap tahap. Kalau satu gagal, jangan lanjut — error sesudahnya menyesatkan.

```bash
export KUBECONFIG=~/.kube/config
```

## Tahap 1 — k3s

```bash
kubectl get nodes -o wide
kubectl get sc
kubectl get pods -n kube-system | grep -E 'traefik|coredns|local-path'
ss -tlnp | grep -E ':80|:443|:6443'
```

Harus: node `Ready` versi `v1.31.2+k3s1`; storageclass `local-path (default)`; Traefik `Running`; port 6443 **hanya** di `127.0.0.1`.

## Tahap 2 — cert-manager

```bash
kubectl -n cert-manager get pods
kubectl get clusterissuer letsencrypt-prod -o jsonpath='{.status.conditions[0].type}={.status.conditions[0].status}'; echo
```

Harus: 3 pod `Running`; `Ready=True`.

## Tahap 3 — Rancher

```bash
kubectl -n cattle-system rollout status deploy/rancher --timeout=10m
kubectl -n cattle-system get certificate
```

Harus: rollout sukses; certificate `Ready=True`. Buka `https://rancher.<ip>.sslip.io`, login password bootstrap.

## Tahap 4 — 9Router

```bash
kubectl -n ai-gateway get deploy,pod,svc,pvc
kubectl -n ai-gateway get certificate
curl -s https://router.<ip>.sslip.io/v1/models -H "Authorization: Bearer $ROUTER_KEY" | head -c 200
```

Harus: pod `1/1 Running`; PVC `Bound`; certificate `Ready=True`; JSON berisi `"data":[{"id":...`.

## Tahap 5 — Postgres

```bash
kubectl -n app get pvc,deploy,pod
kubectl -n app exec deploy/postgres -- pg_isready -U app -d app
kubectl -n app exec deploy/postgres -- psql -U app -d app -c '\dt'
```

Harus: PVC `Bound`; pod `1/1 Running`; `accepting connections`; daftar tabel (kosong sebelum migrate, terisi setelah).

Kalau pod `Running` tapi `pg_isready` tidak pernah sukses → seccomp, lihat [10](10-troubleshooting.md).

## Tahap 6 — Backend Laravel

```bash
kubectl -n app logs deploy/api --tail=50
kubectl -n app exec deploy/api -- php artisan migrate:status
kubectl -n app exec deploy/api -- php -m | grep -i pgsql
curl -sk --resolve app.example.com:443:<node-ip> https://app.example.com/up -o /dev/null -w '%{http_code}\n'
```

Harus: log tanpa `could not find driver` / `SQLSTATE`; migrate `Ran`; `pdo_pgsql` + `pgsql` ada; `/up` = `200`.

## Tahap 7 — Frontend Nuxt

```bash
kubectl -n app logs deploy/web --tail=30
kubectl -n app exec deploy/web -- wget -qO- http://api:8000/up
curl -sk --resolve app.example.com:443:<node-ip> https://app.example.com/ -o /dev/null -w '%{http_code}\n'
```

Harus: Nitro listen di 3000; internal API `200`; halaman `200`.

Halaman `500` + log `fetch failed` → NAT hairpin, pasang `hostAliases` ([07](07-frontend-nuxt.md)).

## Tahap 8 — Ingress & TLS

```bash
kubectl -n app get ingress,certificate
kubectl -n app describe certificate app-tls | sed -n '/Events/,$p'
curl -sI http://app.example.com/ | grep -i '^location'
curl -sI https://www.app.example.com/ | grep -i '^location'
openssl s_client -connect <node-ip>:443 -servername app.example.com </dev/null 2>/dev/null | grep -E 'subject=|issuer='
```

Harus: certificate `Ready=True` + event `Certificate issued`; `301` ke https; issuer `Let's Encrypt`.

## Tahap 9 — CI/CD

```bash
systemctl --user status gh-runner --no-pager | head -5
kubectl -n app get deploy -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.template.spec.containers[0].image}{"\n"}{end}'
```

Harus: runner `active (running)`; tag image = sha commit terbaru (bukan `latest`).

Di GitHub: Actions → run terbaru → `build` hijau, `deploy` hijau, `Smoke test` hijau.

Uji rollback sekali, supaya tahu caranya sebelum panik:

```bash
kubectl -n app rollout undo deploy/api
kubectl -n app rollout status deploy/api
```

## Yang tidak disediakan repo ini (kamu isi sendiri)

Repo ini **panduan infrastruktur**, bukan template aplikasi.

| Hal | Kamu harus |
|---|---|
| Kode Laravel | `composer create-project` + model/controller sendiri ([06](06-backend-laravel.md)) |
| Kode Nuxt | `npx nuxi init` + halaman sendiri ([07](07-frontend-nuxt.md)) |
| Route `/api/...` | bikin sendiri; sesuaikan `check /api/articles` di workflow |
| Domain | beli, atau pakai `sslip.io` ([12](12-domain-dns.md)) |
| Akun GitHub + PAT | bikin sendiri ([13](13-github-setup.md)) |
| Repo aplikasi | bikin sendiri; copy `examples/workflows/build-images.yml` ke sana |

Sudah disediakan: manifest K8s, 2 Dockerfile, workflow contoh, 4 script installer, dan langkah + verifikasinya.

## 8 titik gagal paling sering

1. Secret belum ada → `CreateContainerConfigError`. Apply secret dulu.
2. `envsubst` belum terpasang → manifest berisi `${VPS_IP}` literal. `apt install gettext`.
3. `GHCR_OWNER` salah / bukan huruf kecil → `ImagePullBackOff`.
4. Image belum pernah di-push → `ImagePullBackOff` walau secret benar. Cek tab Packages.
5. Port 80 tertutup atau Cloudflare proxy aktif → certificate `False`.
6. `APP_HOST_DOTTED` tidak di-escape → redirect www tidak match.
7. Runner belum online → job `deploy` menggantung di `Waiting for a runner`.
8. `kubectl` tanpa KUBECONFIG → `permission denied /etc/rancher/k3s/k3s.yaml`.

## Kalau ganti nama namespace

Semua manifest memakai namespace `app`. Kalau diganti, ubah di 3 tempat:

```bash
grep -rl 'namespace: app' manifests/ | xargs sed -i 's/namespace: app/namespace: NAMAMU/'
sed -i 's/-n app /-n NAMAMU /g' examples/workflows/build-images.yml
```
