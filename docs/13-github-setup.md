# 13. Setup GitHub (repo, GHCR, PAT, runner)

## 13.1 Struktur repo yang dipakai CI

Satu repo, dua folder build context:

```
<repo>/
  backend/            Laravel 12
  frontend/           Nuxt 3
  .github/workflows/build-images.yml
```

`docker/build-push-action` memakai `context: backend` / `context: frontend`, jadi kedua folder **harus** di repo yang sama dengan workflow.

## 13.2 Buat repo + push pertama

```bash
cd <repo>
git init
git add -A && git commit -m "init"
gh repo create <owner>/<repo> --private --source=. --push
```

Tanpa `gh`:

```bash
git remote add origin https://github.com/<owner>/<repo>.git
git push -u origin main
```

## 13.3 PAT: dua kebutuhan berbeda

| Keperluan | Scope minimum | Dipakai di |
|---|---|---|
| Pull image GHCR dari cluster | `read:packages` (classic) atau Packages: Read (fine-grained) | Secret `ghcr-pull` |
| Push image dari CI | tidak perlu PAT — `GITHUB_TOKEN` + `permissions: packages: write` | workflow |
| Daftar runner | tidak perlu PAT — token registrasi dari UI | `install-runner.sh` |
| `gh` CLI lokal | `repo`, `workflow` | mesin developer |

Buat PAT classic: Settings → Developer settings → Tokens (classic) → Generate, centang `read:packages`.

## 13.4 Secret pull image

```bash
kubectl -n app create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io \
  --docker-username=<github-user> \
  --docker-password=<PAT-read-packages> \
  --docker-email=unused@example.com
```

Manifest Deployment wajib menyebutnya:

```yaml
spec:
  template:
    spec:
      imagePullSecrets: [{name: ghcr-pull}]
```

## 13.5 Visibilitas package

Package GHCR **private by default**, walaupun repo publik. Ubah di: repo → Packages → pilih package → Package settings → Change visibility.

Kalau dibuat publik, `imagePullSecrets` tidak lagi wajib (tapi aman dibiarkan).

## 13.6 Repo variables untuk workflow

| Variable | Contoh |
|---|---|
| `PUBLIC_URL` | `https://app.example.com` |
| `PUBLIC_HOST` | `app.example.com` |
| `NODE_IP` | `10.20.0.38` |

```bash
gh variable set PUBLIC_URL  --body "https://app.example.com" -R <owner>/<repo>
gh variable set PUBLIC_HOST --body "app.example.com"          -R <owner>/<repo>
gh variable set NODE_IP     --body "10.20.0.38"               -R <owner>/<repo>
```

## 13.7 Branch protection (disarankan)

Settings → Branches → Add rule untuk `main`:
- Require a pull request before merging.
- Require status checks: job `build` harus lulus.

Tanpa ini, `git push --force` ke `main` langsung men-deploy ke produksi.

## 13.8 Deploy manual tanpa commit

```bash
gh workflow run build-images.yml -R <owner>/<repo>
```
