# 11. Cheatsheet operasional

```bash
export KUBECONFIG=~/.kube/config
```

## Status

```bash
kubectl get nodes -o wide
kubectl get pods -A | grep -vE 'kube-system|cattle-|cert-manager|fleet'
kubectl -n app get deploy,pod,svc,ingress,certificate
kubectl top pods -A 2>/dev/null | sort -k3 -h | tail -10
```

## Logs

```bash
kubectl -n app logs deploy/api -f --tail=100
kubectl -n app logs deploy/web -f --tail=100
kubectl -n ai-gateway logs deploy/9router -f --tail=100
kubectl -n app logs <pod> --previous      # container yang crash
```

## Deploy & rollback

```bash
kubectl -n app rollout status deploy/api --timeout=300s
kubectl -n app rollout restart deploy/api
kubectl -n app rollout undo deploy/api
kubectl -n app rollout history deploy/api
```

## Masuk ke container

```bash
kubectl -n app exec -it deploy/api -- bash
kubectl -n app exec deploy/api -- php artisan tinker
kubectl -n app exec deploy/postgres -- psql -U app -d app
```

## Resource & disk

```bash
kubectl -n app get pvc
df -h /var/lib/rancher/k3s/storage      # data PVC ada di sini (local-path)
du -sh /var/lib/rancher/k3s/storage/*
```

## Update komponen

```bash
# k3s
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.32.x+k3s1" sh -

# cert-manager
helm upgrade cert-manager jetstack/cert-manager -n cert-manager --reuse-values --version v1.17.x

# rancher
helm repo update && helm upgrade rancher rancher-latest/rancher -n cattle-system --reuse-values

# 9router: ganti tag image di manifests/9router.yaml, lalu
kubectl -n ai-gateway apply -f manifests/9router.yaml
```

## Backup rutin (cron harian)

```bash
#!/usr/bin/env bash
# /usr/local/bin/backup-stack.sh
set -euo pipefail
export KUBECONFIG=/home/$USER/.kube/config
D=/var/backups/stack; mkdir -p "$D"; T=$(date +%F)

kubectl -n app exec deploy/postgres -- pg_dump -U app app | gzip > "$D/pg-$T.sql.gz"
kubectl -n ai-gateway cp deploy/9router:/app/data/db/data.sqlite "$D/9router-$T.sqlite" -c 9router
kubectl -n app get secret app-secrets pg-secrets -o yaml > "$D/secrets-$T.yaml"
find "$D" -type f -mtime +14 -delete
```

```bash
sudo install -m 755 backup-stack.sh /usr/local/bin/backup-stack.sh
echo '15 3 * * * root /usr/local/bin/backup-stack.sh' | sudo tee /etc/cron.d/stack-backup
```

## Uninstall (hati-hati)

```bash
helm -n cattle-system uninstall rancher
helm -n cert-manager uninstall cert-manager
kubectl delete ns ai-gateway app
/usr/local/bin/k3s-uninstall.sh        # hapus k3s + semua data PVC
```
