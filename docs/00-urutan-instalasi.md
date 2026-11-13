# 0. Urutan instalasi (baca ini dulu)

Ini ringkasan **apa yang dipasang lebih dulu dan kenapa**. Urutan ini bukan selera — tiap langkah bergantung pada langkah sebelumnya.

```
 1. OS + swap + firewall          (dasar, 10 menit)
 2. k3s                           (butuh port 80/443 bebas)
 3. kubeconfig user               (supaya kubectl jalan tanpa sudo)
 4. cert-manager + CRDs           (butuh cluster)
 5. ClusterIssuer letsencrypt     (butuh cert-manager)
 6. Rancher                       (butuh cert-manager + issuer/ingress)
 7. Namespace + Secret tiap app    (butuh cluster; SELALU sebelum Deployment)
 8. 9Router                        (butuh namespace + secret + issuer)
 9. Postgres                       (butuh namespace + secret + PVC/local-path)
10. Backend Laravel (image)        (butuh Postgres ready)
11. Frontend Nuxt (image)          (butuh backend + hostname)
12. Ingress + TLS                  (butuh kedua service + issuer)
13. GHCR pull secret               (butuh image sudah pernah di-push)
14. Self-hosted runner             (butuh kubeconfig + label)
15. GitHub Actions workflow        (butuh runner + repo variables)
```

## Kenapa urutan ini

| Langkah | Kalau dilompat/dibalik |
|---|---|
| swap sebelum k3s | pod ke-`OOMKilled` saat Rancher naik |
| cert-manager sebelum Rancher | Rancher gagal bikin Certificate, Ingress TLS tidak pernah `Ready` |
| ClusterIssuer sebelum app | Ingress `cert-manager.io/cluster-issuer` diabaikan, browser dapat sertifikat self-signed |
| Secret sebelum Deployment | `CreateContainerConfigError` loop, pod tidak pernah start |
| Postgres sebelum backend | `php artisan migrate` gagal, pod api CrashLoopBackOff (akhirnya jalan sendiri setelah PG siap, tapi berisik) |
| Image sebelum Deployment | `ImagePullBackOff` — tidak ada image `latest` di GHCR |
| Runner sebelum workflow | job `deploy` menggantung di `Waiting for a runner to pick up this job` |

## Estimasi waktu & resource

| Tahap | Waktu | RAM terpakai |
|---|---|---|
| OS + k3s | ~10 menit | 600 MB |
| cert-manager | ~3 menit | 150 MB |
| Rancher | ~8 menit (image besar) | +1.5 GB |
| 9Router | ~2 menit | +150 MB |
| Postgres | ~1 menit | +100 MB |
| Laravel + Nuxt | ~5 menit | +400 MB |
| **Total** | **~30 menit** | **~2.9 GB idle, ~5 GB saat build/traffic** |

## Satu kali jalan (copy-paste)

```bash
export VPS_IP="203.0.113.10"
export APP_HOST="app.example.com"          # atau app.${VPS_IP}.sslip.io
export APP_HOST_DOTTED='app\.example\.com'
export ACME_EMAIL="you@example.com"
export GHCR_OWNER="username-github-kamu"   # huruf kecil, pemilik package GHCR
export DB_PASS="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
export ROUTER_KEY="sk-9router-..."

bash scripts/install-k3s.sh
bash scripts/install-cert-manager.sh
VPS_IP=$VPS_IP bash scripts/install-rancher.sh
envsubst < manifests/clusterissuer-letsencrypt.yaml | kubectl apply -f -
envsubst < manifests/9router.yaml | kubectl apply -f -
kubectl create ns app
kubectl -n app create secret generic pg-secrets \
  --from-literal=POSTGRES_DB=app --from-literal=POSTGRES_USER=app \
  --from-literal=POSTGRES_PASSWORD="$DB_PASS"
kubectl -n app create secret generic app-secrets \
  --from-literal=APP_KEY="base64:$(openssl rand -base64 32)" \
  --from-literal=DB_PASSWORD="$DB_PASS"
envsubst < manifests/app/10-postgres.yaml | kubectl apply -f -
kubectl -n app rollout status deploy/postgres
# push image dulu (docs/09), lalu:
envsubst < manifests/app/30-app.yaml | kubectl apply -f -
```

## Catatan global (berlaku di semua langkah)

1. **Satu VPS, satu node.** Tidak ada HA. Semua `replicas: 1` — kalau node mati, semua mati. Itu trade-off yang disengaja untuk biaya.
2. **Namespace = batas keamanan.** `ai-gateway` (gateway), `app` (aplikasi), `cattle-system`/`cert-manager` (platform). Jangan campur. Kalau ganti nama `app`, ubah di **semua** manifest (`grep -rl 'namespace: app' manifests/`) **dan** di workflow (`-n app`). Nama lain = deploy CI masuk ke namespace kosong, rollout gagal.
3. **Semua rahasia di Secret, tidak ada di YAML repo.** `.secrets.env` lokal (chmod 600) atau password manager. Repo publik hanya berisi placeholder `${...}`.
4. **`envsubst` untuk placeholder.** Manifest memakai `${VPS_IP}`, `${APP_HOST}`, `${APP_HOST_DOTTED}`, `${ACME_EMAIL}`, `${GHCR_OWNER}`. Paket: `gettext` (`apt install gettext`). `APP_HOST_DOTTED` = `APP_HOST` dengan `.` di-escape (`app\.example\.com`) — dipakai regex redirect www; kalau lupa, middleware `redirect-www` tidak match.
5. **`sslip.io` untuk tanpa domain.** `app.203.0.113.10.sslip.io` resolve ke IP itu. Let's Encrypt tetap bisa menerbitkan sertifikat.
6. **Traefik adalah satu-satunya pintu masuk.** Tidak ada nginx di host. Semua expose lewat Ingress.
7. **`kubectl` dijalankan di VPS.** k3s API hanya `127.0.0.1:6443`; dari laptop pakai SSH tunnel:
   `ssh -L 6443:127.0.0.1:6443 user@vps` lalu `kubectl --server=https://127.0.0.1:6443`.
8. **NAT hairpin tidak ada.** Dari dalam VPS/pod, hostname publik sering tidak resolve balik. Pakai `--resolve` (curl) atau `hostAliases` (pod).
9. **Deploy = ganti tag image.** `kubectl set image`, bukan `apply` ulang seluruh YAML. Rollback = `rollout undo`.
10. **Semua state di PVC `local-path`.** Ada di `/var/lib/rancher/k3s/storage`. Backup = copy file itu atau `pg_dump` + copy SQLite.
11. **Jangan `kubectl delete pvc`** untuk Postgres — data hilang permanen, tidak ada replika.
12. **Versi di-pin** (k3s, cert-manager, Rancher, 9router, postgres:16, php:8.3, node:22). Upgrade = keputusan sadar, bukan `:latest`.

## Peta dokumen

| Butuh | Baca |
|---|---|
| Urutan & catatan global | dokumen ini |
| Pasang dari nol | 01 → 09 berurutan |
| Domain / DNS sendiri | [12](12-domain-dns.md) |
| Setup repo GitHub + GHCR + PAT | [13](13-github-setup.md) |
| Pantau setelah jalan | [14](14-monitoring.md) |
| Kerasankan | [15](15-security-hardening.md) |
| Backup & restore (dengan drill) | [16](16-backup-restore.md) |
| Ngoding di laptop | [17](17-local-dev.md) |
| Kalau traffic naik | [18](18-skalabilitas.md) |
| Error aneh | [10](10-troubleshooting.md), [11](11-cheatsheet.md) |
