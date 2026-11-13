# 16. Backup & restore

Backup tanpa drill restore = belum punya backup.

## 16.1 Apa yang harus di-backup

| Data | Lokasi | Cara |
|---|---|---|
| Database Postgres | PVC `pg-data` | `pg_dump` |
| 9Router (API key, provider) | PVC `router-pvc`, `/app/data/db/data.sqlite` | copy file |
| Secret K8s | etcd | `kubectl get secret -o yaml` |
| Manifest & workflow | git | sudah di repo |
| k3s etcd snapshot | `/var/lib/rancher/k3s/server/db/snapshots` | otomatis (default) |

Yang **tidak** perlu: image (ada di GHCR), container filesystem, log.

## 16.2 Script backup harian

```bash
#!/usr/bin/env bash
# /usr/local/bin/stack-backup.sh
set -euo pipefail
export KUBECONFIG=/home/$USER/.kube/config
D=/var/backups/stack; mkdir -p "$D"; T=$(date +%F-%H%M)

kubectl -n app exec deploy/postgres -- pg_dump -U app app | gzip > "$D/pg-$T.sql.gz"
kubectl -n ai-gateway cp deploy/9router:/app/data/db/data.sqlite "$D/9router-$T.sqlite" -c 9router
kubectl -n app get secret app-secrets pg-secrets ghcr-pull -o yaml > "$D/secrets-$T.yaml"
chmod 600 "$D"/*

# retensi 14 hari
find "$D" -type f -mtime +14 -delete
ls -lh "$D" | tail -5
```

```bash
sudo install -m 700 stack-backup.sh /usr/local/bin/stack-backup.sh
echo '15 3 * * * root /usr/local/bin/stack-backup.sh >> /var/log/stack-backup.log 2>&1' | sudo tee /etc/cron.d/stack-backup
```

## 16.3 Kirim ke luar VPS

Backup di VPS yang sama hilang bersama VPS. Minimal salin ke mesin lain:

```bash
rsync -avz --delete /var/backups/stack/ user@laptop:/backup/vps-stack/
```

Atau object storage (S3/R2/B2):

```bash
rclone copy /var/backups/stack remote:vps-stack --max-age 48h
```

## 16.4 Restore Postgres (drill)

Simulasi: DB rusak, restore dari dump.

```bash
# 1. hentikan penulis
kubectl -n app scale deploy/api --replicas=0

# 2. drop + recreate (DATA HILANG — pastikan dump valid dulu)
kubectl -n app exec deploy/postgres -- psql -U app -d postgres -c 'DROP DATABASE app;'
kubectl -n app exec deploy/postgres -- psql -U app -d postgres -c 'CREATE DATABASE app OWNER app;'

# 3. restore
gunzip -c /var/backups/stack/pg-2026-01-01-0300.sql.gz | \
  kubectl -n app exec -i deploy/postgres -- psql -U app -d app

# 4. verifikasi jumlah baris kunci
kubectl -n app exec deploy/postgres -- psql -U app -d app -c 'select count(*) from articles;'

# 5. naikkan lagi
kubectl -n app scale deploy/api --replicas=1
```

Catat waktu restore aktual — itu RTO kamu.

## 16.5 Restore 9Router

```bash
kubectl -n ai-gateway scale deploy/9router --replicas=0
kubectl -n ai-gateway cp /var/backups/stack/9router-2026-01-01-0300.sqlite \
  deploy/9router:/app/data/db/data.sqlite -c 9router   # butuh pod hidup -> lihat catatan
kubectl -n ai-gateway scale deploy/9router --replicas=1
```

`kubectl cp` butuh pod jalan. Kalau data rusak sampai pod tidak bisa start, pakai pod bantu:

```bash
kubectl -n ai-gateway run restore --rm -it --image=alpine \
  --overrides='{"spec":{"volumes":[{"name":"d","persistentVolumeClaim":{"claimName":"router-pvc"}}],"containers":[{"name":"restore","image":"alpine","command":["sh"],"stdin":true,"tty":true,"volumeMounts":[{"name":"d","mountPath":"/data"}]}]}}'
# di dalam pod: apk add sqlite && cp /data/db/data.sqlite /data/db/data.sqlite.bak
```

## 16.6 Restore secret

```bash
kubectl apply -f /var/backups/stack/secrets-2026-01-01-0300.yaml
kubectl -n app rollout restart deploy/api deploy/web
```

## 16.7 Kesiapan bencana (VPS hilang total)

1. VPS baru, IP baru (atau DNS diarahkan ulang).
2. `bash scripts/install-k3s.sh` + cert-manager + Rancher.
3. `kubectl create ns app ai-gateway` + apply secret backup.
4. Apply manifest dari git, image sudah ada di GHCR.
5. Restore `pg_dump` + `data.sqlite`.
6. Update `APP_HOST` / `NUXT_PUBLIC_API_BASE` kalau domain berubah → push → CI deploy.

Waktu realistis: **45–60 menit** kalau backup ada dan drill pernah dilakukan.
