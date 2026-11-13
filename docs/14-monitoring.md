# 14. Monitoring & logging

Target: tahu ada masalah **sebelum** user melapor, tanpa memasang Prometheus/Grafana (belum perlu untuk satu VPS).

## 14.1 metrics-server (kubectl top)

k3s tidak memasang metrics-server default. Pasang:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# k3s pakai sertifikat self-signed -> perlu --kubelet-insecure-tls
kubectl -n kube-system patch deploy metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl -n kube-system rollout status deploy/metrics-server

kubectl top nodes
kubectl top pods -A --sort-by=memory | head -15
```

## 14.2 Cek kesehatan cepat (script)

```bash
#!/usr/bin/env bash
# /usr/local/bin/stack-health.sh
set -uo pipefail
export KUBECONFIG=/home/$USER/.kube/config
fail=0
chk() { # nama, perintah...
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "OK   $name"; else echo "FAIL $name"; fail=1; fi
}
chk "node ready"    kubectl wait --for=condition=Ready node --all --timeout=5s
chk "api rollout"   kubectl -n app rollout status deploy/api --timeout=5s
chk "web rollout"   kubectl -n app rollout status deploy/web --timeout=5s
chk "postgres"      kubectl -n app rollout status deploy/postgres --timeout=5s
chk "9router"       kubectl -n ai-gateway rollout status deploy/9router --timeout=5s
chk "cert app"      kubectl -n app wait --for=condition=Ready certificate/app-tls --timeout=5s
chk "https app"     curl -sf --max-time 10 --resolve app.example.com:443:10.20.0.38 https://app.example.com/up
chk "https router"  curl -sf --max-time 10 https://router.203.0.113.10.sslip.io/ -o /dev/null
echo; kubectl get pods -A | grep -vE 'Running|Completed' || true
exit $fail
```

```bash
sudo install -m 755 stack-health.sh /usr/local/bin/stack-health.sh
stack-health.sh
```

Cron tiap 5 menit, kirim notifikasi kalau gagal:

```bash
*/5 * * * * root /usr/local/bin/stack-health.sh >/tmp/stack-health.log 2>&1 || \
  curl -fsS -m 10 "https://ntfy.sh/<topik-rahasia-kamu>" -d "VPS stack FAIL: $(tail -3 /tmp/stack-health.log)"
```

## 14.3 Uptime eksternal

Internal check tidak mendeteksi VPS mati. Pakai monitor eksternal gratis (UptimeRobot / BetterStack / healthchecks.io) ke:

- `https://app.example.com/up` (Laravel health route)
- `https://router.<ip>.sslip.io/`
- `https://rancher.<ip>.sslip.io/ping` (Rancher punya endpoint `/ping`)

## 14.4 Log

Semua container log ke stdout → `kubectl logs`. Tidak ada file log yang perlu dirotasi.

```bash
kubectl -n app logs deploy/api -f --tail=100
kubectl -n app logs -l app=api --since=30m
kubectl -n app logs <pod> --previous            # container yang restart
kubectl get events -A --sort-by=.lastTimestamp | tail -30
```

Log hilang saat pod restart (container runtime menyimpan terbatas). Kalau butuh retensi, kirim ke luar:

```bash
kubectl -n app logs deploy/api -f --tail=0 | logger -t app-api -n <log-host> -P 514
```

## 14.5 Yang perlu dipantau (angka nyata dari stack ini)

| Metrik | Ambang | Aksi |
|---|---|---|
| RAM node | > 85% | tambah swap / turunkan limit / matikan Rancher |
| Disk `/var/lib/rancher/k3s/storage` | > 80% | `pg_dump` + hapus data lama / resize VPS |
| `restartCount` pod | > 3 dalam 1 jam | `kubectl describe pod` + `logs --previous` |
| Certificate `Ready` | `False` | cek port 80, Cloudflare proxy, rate limit LE |
| `kubectl get pods -A` non-Running | ada | lihat docs/10 |

## 14.6 Yang sengaja tidak dipasang

Prometheus + Grafana + Loki ≈ +1.5 GB RAM dan 20 GB disk. Di VPS 8 GB yang sudah menjalankan Rancher, itu menghabiskan sisa kapasitas. Untuk satu aplikasi, `stack-health.sh` + uptime eksternal + `kubectl logs` sudah cukup. Tambah stack observability hanya kalau ada > 3 layanan atau butuh SLO.
