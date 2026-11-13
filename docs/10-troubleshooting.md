# 10. Troubleshooting

Semua di bawah ini benar-benar terjadi saat membangun stack ini.

## Pod `Running` tapi aplikasi hang — seccomp memblokir `kill(2)`

**Gejala:** `postgres` tidak pernah ready; log berhenti setelah `PostgreSQL init process complete`; `gosu`/`su-exec` gagal; `Permission denied`; `kaniko`/build job hang.

**Sebab:** node dengan profil seccomp `RuntimeDefault` menolak syscall `kill(2)` untuk proses di dalam container. `gosu` (dipakai image postgres) memanggil `kill()` untuk memastikan child process.

**Repro minimal** (buktikan dulu, jangan menebak):

```bash
kubectl run sigtest --rm -it --image=busybox:1.36 -- sh -c 'sleep 30 & P=$!; kill $P && echo kill-ok'
```

`sh: can't kill pid N: Permission denied` = terkonfirmasi profil seccomp node.

**Fix** — Unconfined per pod:

```yaml
spec:
  template:
    spec:
      securityContext:
        seccompProfile: {type: Unconfined}
        appArmorProfile: {type: Unconfined}
```

Cek profil node:

```bash
kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.containerRuntimeVersion}'
```

Karena ini workaround, catat sebagai hutang teknis: sebaiknya perbaiki profil seccomp node dan kembalikan ke `RuntimeDefault`.

## `CreateContainerConfigError` — secret belum ada

```bash
kubectl -n app describe pod <pod> | tail -20
```

Biasanya `secret "pg-secrets" not found`. Urutan apply: secret dulu, baru Deployment.

## Ingress 404 / 503

```bash
kubectl -n app get ingress,endpoints
kubectl -n app describe ingress app
```

- `503` = service tanpa endpoint siap -> readiness probe gagal.
- `404` = path tidak cocok / hostname beda. Ingat `/sanctum` harus ke api.
- Cek juga `kubectl get svc -n kube-system traefik` punya EXTERNAL-IP.

## Sertifikat `False` / `Issuing` terus

```bash
kubectl -n app describe certificate app-tls
kubectl -n app get order,challenge
kubectl -n cert-manager logs deploy/cert-manager --tail=100
```

Penyebab umum: port 80 tertutup firewall, Cloudflare proxy aktif, atau hostname tidak resolve ke VPS.

## `curl` dari VPS ke hostname publik gagal — NAT hairpin

Pod/VM tidak bisa mengakses IP publik miliknya sendiri. Gejala: `Connection refused`/timeout dari dalam, normal dari luar.

- Untuk test: `curl -sk --resolve example.com:443:10.20.0.38 https://example.com/up`
- Untuk SSR Nuxt: `hostAliases` -> ClusterIP Traefik.
- Untuk cert-manager HTTP-01 self-check: `hostAliases` sama, kalau issuer gagal validasi dari dalam cluster:

```bash
kubectl patch deploy cert-manager -n cert-manager --type=merge \
  -p '{"spec":{"template":{"spec":{"hostAliases":[{"ip":"<node-ip>","hostnames":["<host>"]}]}}}}'
```

  **Hati-hati:** `--type=merge` **mengganti seluruh array** `hostAliases`. Baca dulu nilai sekarang
  (`-o jsonpath='{.spec.template.spec.hostAliases}'`) dan sertakan semua hostname lama + baru, kalau tidak
  sertifikat lain yang tadinya sehat ikut gagal self-check. Setelah patch, hapus `Challenge` → `Order` →
  `Certificate` (urutan itu) supaya penerbitan ulang. Sebelum menghapus `Certificate`, cek
  `kubectl get certificate -A`: kalau sertifikat lain juga macet, masalahnya di issuer/CRD, bukan di Ingress ini.

## SSR `fetch failed` padahal API sehat

Lihat bagian NAT hairpin di [07-frontend-nuxt](07-frontend-nuxt.md). Cek dari dalam pod:

```bash
kubectl -n app exec deploy/web -- wget -qO- http://api:8000/up
kubectl -n app exec deploy/web -- wget -qO- https://example.com/up
```

## Login SPA gagal 419 / cookie tidak tersimpan

- `SESSION_DOMAIN=.example.com` (pakai titik di depan).
- `SESSION_SECURE_COOKIE=true` **dan** akses lewat HTTPS.
- `SANCTUM_STATEFUL_DOMAINS` harus memuat hostname yang dipakai browser.
- `supports_credentials => true` di `config/cors.php` dan `credentials: 'include'` di frontend.
- `TRUSTED_PROXIES=*` supaya Laravel tahu request aslinya HTTPS.

## Migration gagal saat start

```bash
kubectl -n app logs deploy/api --previous
```

- `migrate --force` wajib di production.
- Postgres belum ready -> tambahkan `initContainer` wait-for-postgres atau biarkan CrashLoopBackOff sampai postgres siap (restart otomatis).
- `config:cache` yang dijalankan **saat build** membuat env runtime diabaikan. Jalankan di command runtime.

## OOMKilled

```bash
kubectl -n app describe pod <pod> | grep -A3 'Last State'
free -m; sudo swapon --show
```

Tambah swap, turunkan `limits.memory`, atau kurangi replika Rancher ke 1.

## `kubectl` permission denied ke k3s.yaml

```bash
export KUBECONFIG=~/.kube/config
```

Runner systemd unit juga butuh `Environment=KUBECONFIG=/home/<user>/.kube/config` — env shell tidak diwarisi.

## Image pull 401 dari GHCR

```bash
kubectl -n app get secret ghcr-pull -o jsonpath='{.data.\.dockerconfigjson}' | base64 -d
```

Pastikan PAT punya `read:packages` dan image memang sudah pernah di-push (cek tab **Packages** di GitHub).
