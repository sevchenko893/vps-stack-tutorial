# NOTES — setup global stack ini

Satu halaman. Detail di [docs/](docs/), perintah harian di [docs/11-cheatsheet.md](docs/11-cheatsheet.md).

## Fakta stack (yang benar-benar jalan)

| Komponen | Versi | Namespace | Akses |
|---|---|---|---|
| k3s | v1.31.2+k3s1 | — | API `127.0.0.1:6443` (lokal saja) |
| Traefik | bawaan k3s | kube-system | port 80/443, satu-satunya pintu masuk |
| cert-manager | v1.16.2 | cert-manager | ClusterIssuer `letsencrypt-prod` |
| Rancher | v2.15.3 | cattle-system | `rancher.<ip>.sslip.io` |
| 9Router | decolua/9router:0.5.112 | ai-gateway | `router.<ip>.sslip.io`, port 20128 |
| Postgres | postgres:16 | app | ClusterIP `postgres:5432`, PVC 5Gi |
| Laravel API | php:8.3-cli | app | `/api`, `/sanctum`, `/up` |
| Nuxt SSR | node:22-alpine | app | `/` |
| CI/CD | GitHub Actions + runner self-hosted | — | push `main` → deploy |

VPS: 8 vCPU / 8 GB / 116 GB, swap 4 GB. Idle ~4.3 GB terpakai.

## Urutan install (ringkas)

1. OS, swap 4 GB, ufw 22/80/443
2. k3s + kubeconfig user
3. cert-manager + CRDs
4. ClusterIssuer LE
5. Rancher (Helm, 1 replika)
6. Namespace + Secret (SELALU sebelum Deployment)
7. 9Router
8. Postgres
9. Backend Laravel image
10. Frontend Nuxt image
11. Ingress + TLS
12. GHCR pull secret
13. Self-hosted runner
14. Workflow CI/CD

Detail alasan urutan: [docs/00-urutan-instalasi.md](docs/00-urutan-instalasi.md).

## 12 catatan global

1. Satu VPS, satu node, semua `replicas: 1`. Tidak ada HA — trade-off biaya.
2. Namespace = batas: `ai-gateway`, `app`, `cattle-system`, `cert-manager`.
3. Rahasia hanya di Secret / `.secrets.env` (chmod 600). Repo cuma placeholder `${...}`.
4. Manifest pakai `envsubst`: `${VPS_IP}`, `${APP_HOST}`, `${APP_HOST_DOTTED}`, `${ACME_EMAIL}`.
5. Tanpa domain → `sslip.io` (`app.<ip>.sslip.io`), LE tetap bisa.
6. Traefik satu-satunya ingress; tidak ada nginx di host.
7. `kubectl` dijalankan di VPS. Dari laptop: `ssh -L 6443:127.0.0.1:6443`.
8. NAT hairpin tidak ada → `curl --resolve`, pod pakai `hostAliases`.
9. Deploy = `kubectl set image` + tag sha. Rollback = `rollout undo`.
10. State ada di PVC `local-path` = `/var/lib/rancher/k3s/storage`. Jangan `kubectl delete pvc`.
11. Versi di-pin semua. Upgrade = keputusan sadar.
12. Node seccomp `RuntimeDefault` blokir `kill(2)` → postgres butuh `seccompProfile: Unconfined`.

## Env wajib per komponen

| Komponen | Secret | Env kunci |
|---|---|---|
| Laravel | `app-secrets` (APP_KEY, DB_PASSWORD) | `DB_HOST=postgres`, `LOG_CHANNEL=stderr`, `TRUSTED_PROXIES=*`, `SESSION_DOMAIN=.example.com` |
| Postgres | `pg-secrets` (DB/USER/PASSWORD) | `PGDATA=/var/lib/postgresql/data/pgdata-v2` |
| 9Router | `9router-credentials` (initial-password, jwt-secret, api-key-secret) | `DATA_DIR=/app/data`, `AUTH_COOKIE_SECURE=true` |
| Cluster | `ghcr-pull` (PAT read:packages) | dipakai `imagePullSecrets` |
| CI | repo variables `PUBLIC_URL`, `PUBLIC_HOST`, `NODE_IP` | build arg `NUXT_PUBLIC_API_BASE` |

## Jebakan yang sudah termakan

| Gejala | Sebab | Fix |
|---|---|---|
| postgres hang, `Permission denied` | seccomp blokir kill(2) | `seccompProfile: Unconfined` |
| `CreateContainerConfigError` | secret belum ada | apply secret dulu |
| login SPA 419 | cookie secure + http, atau `SESSION_DOMAIN` salah | pakai HTTPS, `SESSION_DOMAIN=.domain` |
| SSR `fetch failed` | NAT hairpin | `hostAliases` ke ClusterIP Traefik |
| CI smoke test gagal padahal app OK | `curl \| head` → SIGPIPE exit 23 | simpan body ke variabel |
| `config:cache` tidak baca env | cache dibuat saat build | cache saat runtime |
| `kubectl` permission denied | KUBECONFIG belum di-set | `export KUBECONFIG=~/.kube/config` |
| runner mati saat SSH putus | tanpa linger | `loginctl enable-linger` |

## Biaya & batas

- 1 VPS ≈ biaya bulanan VPS 8 GB. Tidak ada layanan managed.
- Batas realistis: ratusan ribu request/hari untuk SSR + API ringan. `php artisan serve` single-threaded jadi bottleneck lebih dulu — ganti php-fpm (docs/18).
- Tidak ada backup off-site otomatis sampai docs/16 dijalankan.
