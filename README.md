# VPS Stack Tutorial — Rancher + 9Router + Postgres + Laravel + Nuxt

Panduan lengkap membangun stack produksi di **satu VPS** dari nol:

```
Internet
   │  :80/:443
   ▼
Traefik (bawaan k3s, ingressClassName: traefik)
   ├── rancher.<IP>.sslip.io      -> cattle-system/rancher   (Rancher UI)
   ├── router.<IP>.sslip.io       -> ai-gateway/9router      (AI gateway)
   └── app.example.com            -> app/web        (Nuxt 3 SSR, :3000)
                                      └── /api, /sanctum, /up -> api (Laravel 12, :8000)
                                                                  └── postgres:16 (:5432, PVC)
```

Hasil akhir: 3 aplikasi jalan, TLS otomatis (Let's Encrypt), dan **CI/CD**: `git push` ke `main` -> GitHub Actions build image -> push GHCR -> self-hosted runner `kubectl set image` -> smoke test.

Referensi nyata: stack ini dipakai untuk [kabarecing.com](https://kabarecing.com).

## Mulai dari mana?

**Baca [docs/00-urutan-instalasi.md](docs/00-urutan-instalasi.md) dulu** (ringkasan satu halaman: [NOTES.md](NOTES.md)) — urutan langkah, alasannya, estimasi waktu, dan 12 catatan global. Kalau baru pertama kali, ikuti 01 → 09 berurutan. Jangan lompat.

## Daftar isi

| # | Dokumen | Isi |
|---|---------|-----|
| 0 | [00-urutan-instalasi](docs/00-urutan-instalasi.md) | **Urutan install 1-15 + alasan + 12 catatan global** |
| 1 | [01-vps-dan-k3s](docs/01-vps-dan-k3s.md) | VPS, swap, firewall, k3s, kubeconfig |
| 2 | [02-cert-manager](docs/02-cert-manager.md) | cert-manager + ClusterIssuer Let's Encrypt |
| 3 | [03-rancher](docs/03-rancher.md) | Rancher (Helm), login, tuning resource |
| 4 | [04-9router](docs/04-9router.md) | 9Router: PVC, secret, API key, pakai dari cluster |
| 5 | [05-postgres](docs/05-postgres.md) | Postgres 16: PVC, Recreate, PGDATA, probe |
| 6 | [06-backend-laravel](docs/06-backend-laravel.md) | Laravel 12: scaffold, Dockerfile, env, migrate saat start |
| 7 | [07-frontend-nuxt](docs/07-frontend-nuxt.md) | Nuxt 3 SSR: scaffold, Dockerfile, runtime config |
| 8 | [08-ingress-tls](docs/08-ingress-tls.md) | Path-split, TLS, redirect http->https & www |
| 9 | [09-cicd](docs/09-cicd.md) | GitHub Actions + runner self-hosted + GHCR + smoke test |
| 10 | [10-troubleshooting](docs/10-troubleshooting.md) | seccomp/kill(2), NAT hairpin, SIGPIPE, 419, OOM |
| 11 | [11-cheatsheet](docs/11-cheatsheet.md) | Perintah harian: logs, rollout, backup, rollback |
| 12 | [12-domain-dns](docs/12-domain-dns.md) | Domain sendiri, DNS record, Cloudflare, pindah dari sslip.io |
| 13 | [13-github-setup](docs/13-github-setup.md) | Repo, GHCR, PAT, repo variables, branch protection |
| 14 | [14-monitoring](docs/14-monitoring.md) | metrics-server, health script, uptime, log |
| 15 | [15-security-hardening](docs/15-security-hardening.md) | SSH, ufw, RBAC, secret, scan image |
| 16 | [16-backup-restore](docs/16-backup-restore.md) | Backup harian, drill restore, rencana bencana |
| 17 | [17-local-dev](docs/17-local-dev.md) | Ngoding di laptop, beda env lokal vs cluster |
| 18 | [18-skalabilitas](docs/18-skalabilitas.md) | Replika, Redis, multi-node, kapan pindah managed |
| 19 | [19-verifikasi](docs/19-verifikasi.md) | **Checklist "tahap ini berhasil" + 8 titik gagal tersering** |
| 20 | [20-analytics](docs/20-analytics.md) | GA4 + Search Console di Nuxt: plugin, env runtime, robots, sitemap |

## Batas jujur repo ini

Ini panduan infrastruktur yang sudah terbukti di satu VPS, **bukan template aplikasi siap pakai**. Yang kamu isi sendiri: kode Laravel, kode Nuxt, route API, domain, akun GitHub, dan repo aplikasi. Semua langkah + cara verifikasinya ada di docs.

## Prasyarat

- VPS Ubuntu 22.04/24.04, **minimal 4 vCPU / 8 GB RAM / 80 GB disk** (Rancher + cert-manager + Traefik makan ~3 GB).
- IP publik, port **80, 443, 6443** bisa diakses (6443 hanya kalau mau kubectl dari luar).
- Domain (opsional). Tanpa domain? pakai `sslip.io`: `rancher.203.0.113.10.sslip.io` otomatis resolve ke `203.0.113.10`. Cukup untuk TLS Let's Encrypt.
- Akun GitHub + repo aplikasi.

> Semua contoh memakai variabel. Isi sekali di shell:
> ```bash
> export VPS_IP="203.0.113.10"        # ganti IP VPS kamu
> export APP_HOST="app.${VPS_IP}.sslip.io"
> export ACME_EMAIL="you@example.com"
> ```

## Struktur repo

```
docs/                     panduan per tahap
manifests/                YAML siap `kubectl apply -f`
  9router.yaml
  clusterissuer-letsencrypt.yaml
  app/10-postgres.yaml
  app/30-app.yaml
examples/workflows/       build-images.yml — copy ke repo aplikasi kamu
scripts/                  helper idempoten
```

## Jalur cepat (kalau sudah paham)

```bash
export VPS_IP="203.0.113.10"
export APP_HOST="app.example.com"          # atau app.${VPS_IP}.sslip.io
export APP_HOST_DOTTED='app\.example\.com'
export ACME_EMAIL="you@example.com"
export GHCR_OWNER="username-github-kamu"   # huruf kecil

bash scripts/install-k3s.sh
bash scripts/install-cert-manager.sh
VPS_IP=$VPS_IP bash scripts/install-rancher.sh
export ACME_EMAIL="you@example.com"
envsubst < manifests/clusterissuer-letsencrypt.yaml | kubectl apply -f -
envsubst < manifests/9router.yaml | kubectl apply -f -
kubectl create ns app
envsubst < manifests/app/10-postgres.yaml | kubectl apply -f -
envsubst < manifests/app/30-app.yaml | kubectl apply -f -
```

`envsubst` (paket `gettext`) mengganti `${VPS_IP}`, `${APP_HOST}`, `${APP_HOST_DOTTED}`, `${ACME_EMAIL}`, `${GHCR_OWNER}` di manifest. `GHCR_OWNER` = username GitHub pemilik package (huruf kecil).

Sisanya (secret, image, CI/CD) ada di docs — jangan dilewat, urutannya penting.
