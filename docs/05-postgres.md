# 5. Postgres 16 di cluster

Satu instance, satu PVC, tanpa operator. Untuk satu aplikasi ini sudah cukup.

## 5.1 Secret

```bash
export DB_PASS="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"

kubectl -n app create secret generic pg-secrets \
  --from-literal=POSTGRES_DB=app \
  --from-literal=POSTGRES_USER=app \
  --from-literal=POSTGRES_PASSWORD="$DB_PASS"
```

Gunakan namespace yang sama dengan aplikasi (`app` di contoh ini).

## 5.2 Deploy

```bash
kubectl -n app apply -f manifests/app/10-postgres.yaml
kubectl -n app rollout status deploy/postgres
kubectl -n app exec deploy/postgres -- pg_isready -U app -d app
```

## 5.3 Keputusan desain di manifest

| Setting | Alasan |
|---|---|
| `strategy: Recreate` | PVC `ReadWriteOnce` — dua pod tidak bisa mount volume yang sama, rollout harus mati dulu. |
| `PGDATA=/var/lib/postgresql/data/pgdata-v2` | Subdirektori supaya `lost+found` di root volume tidak bikin initdb gagal. Ganti nama kalau mau re-init. |
| `seccompProfile: Unconfined` | **Penting.** Node dengan seccomp `RuntimeDefault` memblokir `kill(2)`; `gosu`/`postgres` hang atau `Permission denied`. Detail: [10-troubleshooting](10-troubleshooting.md). |
| `readinessProbe: pg_isready -h 127.0.0.1` | Force TCP; pakai socket saja bisa lolos walau listener belum siap untuk koneksi jaringan. |
| `limits.memory: 1Gi` | Cegah Postgres menghabiskan RAM node. |

## 5.4 Akses dari luar cluster (debug)

```bash
kubectl -n app port-forward svc/postgres 5432:5432
psql "postgresql://app:$DB_PASS@127.0.0.1:5432/app"
```

Jangan expose Postgres lewat Ingress. Kalau butuh akses remote permanen, pakai `kubectl port-forward` di tunnel SSH.

## 5.5 Backup

```bash
kubectl -n app exec deploy/postgres -- \
  pg_dump -U app app | gzip > app-$(date +%F).sql.gz
```

Restore:

```bash
gunzip -c app-2026-01-01.sql.gz | kubectl -n app exec -i deploy/postgres -- psql -U app app
```
