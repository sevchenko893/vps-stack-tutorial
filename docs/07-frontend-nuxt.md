# 7. Frontend Nuxt 3 (SSR)

## 7.1 Dockerfile

[manifests/Dockerfile.frontend](../manifests/Dockerfile.frontend):

```dockerfile
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
ARG NUXT_PUBLIC_API_BASE
ENV NUXT_PUBLIC_API_BASE=$NUXT_PUBLIC_API_BASE
RUN npm run build

FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/.output ./.output
EXPOSE 3000
CMD ["node", ".output/server/index.mjs"]
```

- Output SSR = `.output/`, bukan `dist/`.
- `NUXT_PUBLIC_API_BASE` adalah **build arg**: nilai `runtimeConfig.public` di-inline saat build. Ganti domain = rebuild image.
- Image runtime cuma butuh node + `.output` (~150 MB).

## 7.2 nuxt.config.ts

```ts
export default defineNuxtConfig({
  compatibilityDate: '2025-05-15',
  modules: ['@nuxtjs/tailwindcss'],
  runtimeConfig: {
    public: { apiBase: process.env.NUXT_PUBLIC_API_BASE || 'http://127.0.0.1:8000' },
  },
  routeRules: {
    '/akun/**': { ssr: false },   // halaman butuh token -> CSR saja
  },
})
```

## 7.3 Deploy

```bash
kubectl -n app apply -f manifests/app/30-app.yaml
kubectl -n app rollout status deploy/web
kubectl -n app logs deploy/web --tail=30
```

## 7.4 Jebakan: SSR tidak bisa fetch domain publiknya sendiri

Pod `web` melakukan SSR fetch ke `https://example.com/api/...`. Di banyak VPS, **NAT hairpin** tidak aktif: paket keluar ke IP publik VPS tidak bisa balik ke Traefik. Gejala: SSR timeout / `fetch failed`, tapi dari browser normal.

Solusi di manifest — arahkan hostname ke ClusterIP Traefik:

```yaml
hostAliases:
  - ip: 10.43.4.137          # kubectl get svc -n kube-system traefik -o jsonpath='{.spec.clusterIP}'
    hostnames: [example.com, www.example.com]
```

Dengan begitu TLS tetap valid (SNI tetap `example.com`), tapi trafik tidak keluar VPS.

Alternatif: pakai URL internal `http://api.app.svc.cluster.local:8000` untuk server-side, dan URL publik untuk client-side (`useRequestURL()` / dua runtime config key).

## 7.5 Cek

```bash
curl -s https://$APP_HOST/ | head -c 300
kubectl -n app exec deploy/web -- wget -qO- http://api:8000/up
```
