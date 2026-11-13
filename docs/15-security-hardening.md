# 15. Security hardening

Checklist ini mengasumsikan VPS baru dengan IP publik. Kerjakan **sebelum** aplikasi menerima trafik nyata.

## 15.1 SSH

```bash
# di laptop: kirim public key
ssh-copy-id user@203.0.113.10

# di VPS
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart ssh
```

Uji login di sesi baru **sebelum** menutup sesi lama.

## 15.2 Firewall

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

Jangan buka `6443` (k3s API), `5432` (Postgres), `20128` (9Router). Semua lewat Traefik atau `kubectl port-forward`.

## 15.3 k3s API tidak terekspos

```bash
ss -tlnp | grep 6443     # harus 127.0.0.1:6443, bukan 0.0.0.0:6443
```

Kalau muncul `0.0.0.0`, tambahkan `--bind-address=127.0.0.1` (default k3s) — jangan diubah kecuali butuh remote kubectl.

## 15.4 Secret

- Jangan commit `.env`, `.secrets.env`, kubeconfig, token.
- `.gitignore`: `.env`, `.secrets.env`, `*.sqlite`, `*.sql.gz`, `*.pem`.
- Simpan salinan secret di luar VPS (password manager / vault):

```bash
kubectl -n app get secret app-secrets pg-secrets ghcr-pull -o yaml > secrets-backup.yaml
gpg -c secrets-backup.yaml && rm secrets-backup.yaml
```

- Secret K8s **tidak terenkripsi di etcd** secara default (base64 saja). Siapa pun dengan akses node bisa membacanya. Untuk data sangat sensitif: aktifkan `--secrets-encryption` di k3s atau pakai external secret manager.

## 15.5 RBAC minimum

```bash
# jangan pakai cluster-admin untuk otomasi harian
kubectl create role app-deployer -n app \
  --verb=get,list,watch,create,update,patch \
  --resource=deployments,services,ingresses,secrets
kubectl create rolebinding app-deployer -n app \
  --role=app-deployer --serviceaccount=app:deployer
```

`cluster-admin` hanya untuk user admin (mis. Hermes agent / kamu sendiri), bukan untuk runner atau CI.

## 15.6 Container

- Image pin versi eksplisit (`postgres:16`, `php:8.3-cli`, `node:22-alpine`) — bukan `:latest`.
- Jalankan sebagai non-root kalau image mendukung:

```yaml
securityContext:
  runAsNonRoot: true
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true      # hati-hati: Laravel butuh storage/ writable
```

- `postgres` di stack ini pakai `seccompProfile: Unconfined` sebagai workaround (docs/10). Catat sebagai hutang teknis — kembalikan ke `RuntimeDefault` setelah profil seccomp node diperbaiki.

## 15.7 Aplikasi

| Item | Setelan |
|---|---|
| `APP_DEBUG` | `false` (jangan pernah `true` di produksi — stack trace bocor) |
| `APP_ENV` | `production` |
| Sanctum | `SANCTUM_STATEFUL_DOMAINS` hanya domain sendiri |
| CORS | `FRONTEND_ORIGINS` eksplisit, jangan `*` dengan credentials |
| Rate limit | `throttle:` di route login/register (`throttle:6,1`) |
| Cookie | `SESSION_SECURE_COOKIE=true`, `SESSION_DOMAIN=.example.com` |
| 9Router | `AUTH_COOKIE_SECURE=true`, API key per aplikasi (jangan satu key untuk semua) |

## 15.8 Scan image

```bash
# tanpa install apa pun
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy:latest image --severity HIGH,CRITICAL \
  ghcr.io/<owner>/app-backend:latest
```

Di CI bisa ditambahkan sebagai step non-blocking dulu, blocking setelah bersih.

## 15.9 Update rutin

```bash
sudo apt update && sudo apt upgrade -y      # OS
kubectl get nodes -o wide                   # k3s version
helm list -A                                # chart versions
```

Patch CVE k3s: `curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=vX.Y.Z+k3s1 sh -` (in-place upgrade, downtime ~30 s).
