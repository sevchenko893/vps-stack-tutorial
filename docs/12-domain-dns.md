# 12. Domain & DNS

## 12.1 Tanpa domain: sslip.io

`<apa-saja>.<IP>.sslip.io` otomatis resolve ke `<IP>`. Cocok untuk staging / percobaan.

```
rancher.203.0.113.10.sslip.io   -> 203.0.113.10
router.203.0.113.10.sslip.io    -> 203.0.113.10
```

Let's Encrypt menerbitkan sertifikat untuk hostname ini karena validasi HTTP-01 hanya butuh kontrol atas hostname, bukan domain.

Kekurangan: tidak bisa dipakai produksi serius (nama jelek, tidak ada kontrol DNS, bergantung pada layanan pihak ketiga).

## 12.2 Dengan domain sendiri

Catatan DNS minimum:

| Type | Name | Value | TTL |
|---|---|---|---|
| A | `@` | `203.0.113.10` | 300 |
| A | `www` | `203.0.113.10` | 300 |
| A | `app` | `203.0.113.10` | 300 |
| A | `rancher` | `203.0.113.10` | 300 |
| A | `router` | `203.0.113.10` | 300 |

Satu A record per hostname Ingress. Traefik membedakan lewat header `Host`, bukan port.

## 12.3 Cloudflare

Dua hal yang sering bikin gagal:

1. **Proxy (orange cloud) memblokir HTTP-01** pada penerbitan pertama — request challenge datang dari IP Cloudflare, bukan Let's Encrypt. Set **DNS only (grey cloud)** dulu sampai `kubectl -n app get certificate` = `True`. Setelah itu proxy boleh dinyalakan.
2. **SSL mode** harus `Full (strict)` kalau proxy aktif, karena Traefik sudah punya sertifikat LE valid. Mode `Flexible` menyebabkan redirect loop (Cloudflare bicara HTTP ke origin, Traefik redirect ke HTTPS).

## 12.4 Update hostname setelah deploy

Kalau pindah dari `sslip.io` ke domain asli:

```bash
export APP_HOST="app.example.com"
export APP_HOST_DOTTED='app\.example\.com'

# 1. update env aplikasi + Ingress
envsubst < manifests/app/30-app.yaml | kubectl apply -f -

# 2. frontend di-rebuild: NUXT_PUBLIC_API_BASE adalah build arg
git commit -am "chore: ganti domain" && git push    # CI build image baru

# 3. hapus sertifikat lama supaya LE menerbitkan ulang
kubectl -n app delete secret app-tls
kubectl -n app delete certificate --all
```

Jangan lupa update repo variable `PUBLIC_URL` / `PUBLIC_HOST` di GitHub (docs/09).

## 12.5 Wildcard certificate (opsional)

Kalau punya banyak subdomain, wildcard lebih hemat rate limit LE. Butuh DNS-01 (token API provider), bukan HTTP-01:

```yaml
spec:
  acme:
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef: {name: cloudflare-api-token, key: api-token}
```

Sekretariat token disimpan sebagai Secret di namespace `cert-manager`. Untuk 3 hostname, HTTP-01 lebih sederhana — jangan tambah kompleksitas tanpa perlu.
