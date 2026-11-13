# 9. CI/CD: GitHub Actions + self-hosted runner

Alur:

```
push ke main
  -> job build (ubuntu-latest): matrix backend+frontend -> buildx -> ghcr.io/<owner>/<app>-<svc>:<sha> + :latest
  -> job deploy (self-hosted, label app): kubectl set image -> rollout status -> smoke test
```

## 9.1 Kenapa self-hosted runner

k3s API di VPS ini hanya listen `127.0.0.1:6443`. Runner GitHub-hosted tidak bisa menjangkaunya. Runner self-hosted jalan **di VPS** sehingga `kubectl` lokal langsung bisa. Ini pola *pull-based deploy* — tidak perlu membuka API server ke internet.

## 9.2 Workflow

Workflow contoh: [examples/workflows/build-images.yml](../examples/workflows/build-images.yml).
**Copy ke repo aplikasi** (`.github/workflows/build-images.yml`) — bukan di repo tutorial ini, karena `context: backend` / `context: frontend` harus ada di repo yang sama.

Poin penting:

| Bagian | Alasan |
|---|---|
| `permissions: packages: write` | Push ke GHCR pakai `GITHUB_TOKEN`, tanpa PAT. |
| `docker/build-push-action@v6` + `docker/login-action@v3` | Build & push; `username: ${{ github.actor }}`. |
| tag `:${{ github.sha }}` **dan** `:latest` | Deploy pakai sha (immutable, rollback gampang); `latest` untuk debug manual. |
| `concurrency: group: deploy-main, cancel-in-progress: false` | Deploy tidak boleh saling menimpa. |
| `runs-on: [self-hosted, app]` | Label runner; harus cocok dengan label saat registrasi. |
| `kubectl set image ... :${{ github.sha }}` | Deploy = ganti tag, bukan `apply` ulang seluruh YAML. |
| `rollout status --timeout=300s` | Job gagal kalau pod tidak siap; mencegah "sukses" palsu. |
| smoke test dengan `--resolve` | VPS tidak bisa hairpin ke hostname publiknya sendiri. |

## 9.3 Daftarkan runner

Di GitHub: **Settings -> Actions -> Runners -> New self-hosted runner** (Linux x64). Ambil token, lalu:

```bash
bash scripts/install-runner.sh <OWNER>/<REPO> <TOKEN> app
```

Script membuat `~/actions-runner`, register dengan label, dan systemd **user** unit (`KUBECONFIG` di-set di unit — runner tidak mewarisi env shell).

Cek:

```bash
systemctl --user status gh-runner
systemctl --user enable --now gh-runner
loginctl show-user $USER | grep Linger     # harus Linger=yes
```

`Linger=yes` wajib, kalau tidak runner mati saat sesi SSH terputus.

## 9.4 Variable repo yang dipakai workflow

`build-images.yml` membaca 3 repo variable (Settings -> Secrets and variables -> Actions -> **Variables**), bukan secret — isinya bukan rahasia:

| Variable | Contoh | Dipakai |
|---|---|---|
| `PUBLIC_URL` | `https://app.example.com` | build-arg `NUXT_PUBLIC_API_BASE` |
| `PUBLIC_HOST` | `app.example.com` | smoke test `--resolve` |
| `NODE_IP` | `10.20.0.38` | IP node untuk `--resolve` |
| `SMOKE_PATH` | `/api/articles` | endpoint API yang dicek; **kosongkan** kalau belum punya |

```bash
gh variable set PUBLIC_URL  --body "https://app.example.com" -R <owner>/<repo>
gh variable set PUBLIC_HOST --body "app.example.com"          -R <owner>/<repo>
gh variable set NODE_IP     --body "10.20.0.38"               -R <owner>/<repo>
gh variable set SMOKE_PATH  --body "/api/articles"            -R <owner>/<repo>
```

`SMOKE_PATH` sengaja tidak di-hardcode di workflow: project Laravel yang baru di-scaffold belum punya `/api/articles`. Kalau kosong, step itu dilewati — `/up` dan `/` tetap dicek.

## 9.5 Secret & pull secret GHCR

Repo publik di GHCR tetap private by default. Dua hal:

1. **Pull dari cluster** — buat PAT classic scope `read:packages`, lalu:

```bash
kubectl -n app create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io \
  --docker-username=<github-user> \
  --docker-password=<PAT> \
  --docker-email=unused@example.com
```

Manifest aplikasi mereferensikannya: `imagePullSecrets: [{name: ghcr-pull}]`.

2. **Push dari Actions** — sudah otomatis via `GITHUB_TOKEN` (`packages: write`). Tidak perlu secret tambahan.

## 9.6 Smoke test yang benar

```bash
check() {
  for i in $(seq 1 24); do
    code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 25 \
             --resolve example.com:443:10.20.0.38 "https://example.com$1" || true)
    [ "$code" = "200" ] && return 0
    sleep 5
  done
  echo "$1 returned $code"; return 1
}
check /up
check /api/articles    # GANTI dengan route yang benar-benar ada di aplikasimu
```

**Sesuaikan `check /api/articles`** dengan endpoint nyata di aplikasimu. Kalau route itu tidak ada, job gagal 404 padahal deploy sukses — dan itu bukan bug CI, itu bug ekspektasi test.

Tiga jebakan yang sudah ditangani di snippet itu:
- **cold start SSR** bisa >10 s -> retry 24x5 s.
- `--resolve` untuk NAT hairpin.
- **jangan** pipe `curl` ke `head`: SIGPIPE membuat curl exit 23 dan job gagal padahal response OK. Simpan ke variabel, lalu `case` untuk cek prefix JSON.

## 9.7 Rollback

```bash
kubectl -n app rollout undo deploy/api
# atau pin ke sha tertentu
kubectl -n app set image deploy/api api=ghcr.io/<owner>/<app>-backend:<sha-lama>
```

## 9.8 Update manifest dari CI (opsional)

Kalau ingin `git` jadi sumber kebenaran tag image, tambahkan step `sed`/`yq` yang mengganti tag di `30-app.yaml` lalu commit balik. Untuk satu VPS, `kubectl set image` lebih sedikit moving parts — tidak ada commit loop.
