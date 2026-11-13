# 8. Ingress, TLS, redirect

Satu hostname, dua service — dipisah per path:

```yaml
spec:
  ingressClassName: traefik
  rules:
    - host: example.com
      http:
        paths:
          - {path: /api,     pathType: Prefix, backend: {service: {name: api, port: {number: 8000}}}}
          - {path: /sanctum, pathType: Prefix, backend: {service: {name: api, port: {number: 8000}}}}
          - {path: /up,      pathType: Prefix, backend: {service: {name: api, port: {number: 8000}}}}
          - {path: /,        pathType: Prefix, backend: {service: {name: web, port: {number: 3000}}}}
  tls:
    - hosts: [example.com, www.example.com]
      secretName: app-tls
```

`/sanctum` wajib masuk api — kalau tidak, `sanctum/csrf-cookie` ditangkap Nuxt dan SPA login gagal 404.

TLS: cukup annotation `cert-manager.io/cluster-issuer: letsencrypt-prod`, cert-manager membuat secret `app-tls` sendiri.

## Redirect http -> https

Traefik di k3s hanya listen `web` (80) + `websecure` (443). Middleware redirect dipasang di Ingress **terpisah** untuk entrypoint web:

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata: {name: redirect-https, namespace: app}
spec: {redirectScheme: {scheme: https, permanent: true}}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-http
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web
    traefik.ingress.kubernetes.io/router.middlewares: app-redirect-https@kubernetescrd
spec: { ... }
```

Format annotation middleware: `<namespace>-<nama>@kubernetescrd`.

## Redirect www -> apex

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata: {name: redirect-www, namespace: app}
spec:
  redirectRegex:
    regex: ^https?://www\.example\.com/(.*)
    replacement: https://example.com/$1
    permanent: true
```

Dipasang sebagai Ingress terpisah untuk `www.example.com` + TLS secret yang sama.

## Verifikasi

```bash
kubectl -n app get ingress,certificate
kubectl -n app describe certificate app-tls        # Events: Certificate issued
curl -sI http://example.com/ | grep -i location    # 301 -> https
curl -sI https://www.example.com/ | grep -i location
curl -s https://example.com/up -o /dev/null -w '%{http_code}\n'
```

Dari VPS sendiri, hostname publik sering **tidak** resolve balik (NAT hairpin). Pakai:

```bash
curl -sk --resolve example.com:443:10.20.0.38 https://example.com/up
```
