# 4. 9Router (AI gateway)

9Router = proxy OpenAI-compatible ke banyak provider, dengan UI web, API key management, dan penyimpanan SQLite di dalam container.

## 4.1 Namespace + secret

```bash
kubectl create namespace ai-gateway

kubectl -n ai-gateway create secret generic 9router-credentials \
  --from-literal=initial-password="$(openssl rand -base64 24)" \
  --from-literal=jwt-secret="$(openssl rand -base64 32)" \
  --from-literal=api-key-secret="$(openssl rand -base64 32)"
```

Secret harus ada **sebelum** Deployment, kalau tidak pod `CreateContainerConfigError`.

## 4.2 Deploy

```bash
export VPS_IP="203.0.113.10"
envsubst < manifests/9router.yaml | kubectl apply -f -
kubectl -n ai-gateway rollout status deploy/9router
```

Isi manifest: PVC 2Gi (`local-path`), image `decolua/9router:0.5.112`, port **20128**, `DATA_DIR=/app/data`, probe ke `/`.

Kenapa PVC wajib: database SQLite (`/app/data/db/data.sqlite`) menyimpan API key dan provider credential. Tanpa volume, semua hilang tiap restart.

## 4.3 Ambil password & buka UI

```bash
kubectl -n ai-gateway get secret 9router-credentials \
  -o jsonpath='{.data.initial-password}' | base64 -d; echo
```

Buka `https://router.${VPS_IP}.sslip.io`, login dengan password itu. Di UI: tambah provider (OpenAI/Anthropic/Groq/…), lalu buat API key.

## 4.4 Pakai dari luar

Ambil API key dari UI (menu API Keys) atau SQLite di 4.5, simpan ke shell:

```bash
export ROUTER_KEY="sk-9router-..."
```

```bash
curl https://router.${VPS_IP}.sslip.io/v1/models \
  -H "Authorization: Bearer ${ROUTER_KEY}"

curl https://router.${VPS_IP}.sslip.io/v1/chat/completions \
  -H "Authorization: Bearer ${ROUTER_KEY}" \
  -H 'Content-Type: application/json' \
  -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"halo"}]}'
```

## 4.5 Baca API key langsung dari SQLite

Berguna untuk otomasi / migrasi:

```bash
kubectl -n ai-gateway exec deploy/9router -- \
  sqlite3 /app/data/db/data.sqlite "select name, key from apiKeys;"
```

Kalau `sqlite3` tidak ada di image:

```bash
kubectl -n ai-gateway cp deploy/9router:/app/data/db/data.sqlite /tmp/9r.sqlite -c 9router
sqlite3 /tmp/9r.sqlite "select name, key from apiKeys;"
```

## 4.6 Pakai dari dalam cluster (Laravel / Nuxt)

Service internal: `http://router-service.ai-gateway.svc.cluster.local:20128`. API key disimpan di secret, bukan di env polos:

```bash
kubectl -n app create secret generic router-key --from-literal=key='sk-9router-xxxx'
```

```yaml
- name: AI_GATEWAY_URL
  value: http://router-service.ai-gateway.svc.cluster.local:20128
- name: AI_GATEWAY_KEY
  valueFrom: {secretKeyRef: {name: router-key, key: key}}
```

Test dari pod aplikasi (tanpa keluar VPS):

```bash
kubectl -n app exec deploy/api -- \
  curl -s $AI_GATEWAY_URL/v1/models -H "Authorization: Bearer $AI_GATEWAY_KEY"
```

## 4.7 Backup

```bash
kubectl -n ai-gateway cp deploy/9router:/app/data/db/data.sqlite \
  ./9router-$(date +%F).sqlite -c 9router
```

`AUTH_COOKIE_SECURE=true` di manifest — cookie login hanya dikirim lewat HTTPS, jadi akses via `http://` akan gagal login. Ini disengaja.
