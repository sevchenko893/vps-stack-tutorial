# 20. Analytics & Search Console di Nuxt (tanpa dependency)

Dipakai di kabarecing.com. Satu plugin, satu env var, tanpa `nuxt-gtag` / `@nuxtjs/google-analytics`. Bagian GSC ada di 20.8.

## 20.1 Property GA4 (langkah pemilik akun)

Analytics → **Admin** → **Create** → **Property** (nama, timezone, currency) → platform **Web** →
URL situs + nama stream → salin **Measurement ID** `G-XXXXXXXXXX` (bukan `GT-`/`AW-`).

ID ini publik — ikut terkirim di HTML — jadi aman masuk commit. Jangan pernah menaruh kredensial Google di repo/chat.

## 20.2 Config: ID dari env, default kosong

```ts
// nuxt.config.ts
runtimeConfig: {
  public: {
    apiBase: process.env.NUXT_PUBLIC_API_BASE || 'http://127.0.0.1:8000',
    // Kosong = plugin no-op: nol request ke Google.
    gaId: process.env.NUXT_PUBLIC_GA_ID || '',
  },
},
```

`runtimeConfig.public` bisa dioverride env **saat runtime** (`NUXT_PUBLIC_GA_ID`), jadi mengisi ID tidak
butuh rebuild image — cukup `kubectl set env` + rollout. Ini beda dengan `import.meta.env.VITE_*` yang
dibekukan saat build.

## 20.3 Plugin

```ts
// app/plugins/gtag.ts  (universal, BUKAN .client)
export default defineNuxtPlugin(() => {
  const id = useRuntimeConfig().public.gaId
  if (!id) return

  useHead({
    script: [
      { src: `https://www.googletagmanager.com/gtag/js?id=${id}`, async: true },
      {
        innerHTML: `window.dataLayer=window.dataLayer||[];function gtag(){dataLayer.push(arguments)}gtag('js',new Date());gtag('config','${id}');`,
        tagPriority: 'high',
      },
    ],
  })

  if (import.meta.server) return          // router & window hanya ada di client

  const router = useRouter()
  router.afterEach((to) => {
    if (typeof window !== 'undefined' && typeof window.gtag === 'function') {
      window.gtag('event', 'page_view', { page_path: to.fullPath })
    }
  })
})
```

Kenapa **universal**, bukan `.client`:

- `.client` membuat plugin hanya jalan di browser, sehingga `useHead` di dalamnya **tidak** ikut HTML SSR →
  `curl`/view-source tidak menunjukkan tag, dan bot/crawler tanpa JS tidak terdeteksi sama sekali.
- Universal + guard `import.meta.server` setelah `useHead`: script ter-render di SSR, hook router tetap
  client-only.

`gtag('config')` sudah mengirim `page_view` pertama. `router.afterEach` hanya untuk navigasi SPA berikutnya —
tanpa itu, semua halaman setelah klik pertama tidak terhitung.

## 20.4 Deploy

```bash
# isi ID tanpa rebuild image
kubectl -n app set env deploy/web NUXT_PUBLIC_GA_ID=G-XXXXXXXXXX
kubectl -n app rollout status deploy/web --timeout=240s
```

Atau permanen di manifest:

```yaml
- name: NUXT_PUBLIC_GA_ID
  value: "G-XXXXXXXXXX"
```

## 20.5 Verifikasi berurutan

```bash
# 1. build sukses (plugin dengan import salah menggagalkan build, bukan cuma browser)
cd frontend && npm run build

# 2. tag ada di HTML SSR
curl -s https://app.example.com/kategori/motor | grep -o 'gtag/js?id=[A-Z0-9-]*'
curl -s https://app.example.com/kategori/motor | grep -o "gtag('config','[A-Z0-9-]*')"

# 3. ID kosong = benar-benar no-op
curl -s https://app.example.com/ | grep -c googletagmanager     # harus 0
```

4. GA4 → **Reports → Realtime**: satu active user setelah halaman dibuka. Ini satu-satunya bukti data
   sampai ke property — tag ada di HTML belum membuktikan apa pun.
5. Klik menu (navigasi client-side) → `page_view` kedua muncul di Realtime / DebugView.
6. DevTools Network: `https://www.google-analytics.com/g/collect` balas `204`/`200`.

## 20.6 Jebakan

| Gejala | Sebab |
|---|---|
| Tag tidak ada di `curl`/view-source | plugin `.client` saja, atau ID kosong |
| Realtime kosong padahal tag ada | CSP memblokir `script-src https://www.googletagmanager.com` / `connect-src https://*.google-analytics.com` |
| Halaman setelah klik pertama tidak terhitung | tidak ada `router.afterEach` |
| `page_view` dobel | `gtag('config')` **dan** hook terpasang saat initial load; kirim manual hanya untuk navigasi berikutnya |
| Traffic ~30% lebih rendah dari log server | ad blocker memblokir `googletagmanager.com` — normal, bukan instrumentasi rusak |

## 20.7 Alternatif tanpa Google

Kalau tidak mau data ke Google: Plausible / Umami (self-host, ~100 MB RAM di namespace yang sama).
Polanya identik: satu plugin, ID dari env, guard kosong. Untuk satu VPS yang sudah menjalankan Rancher,
Umami + Postgres yang sudah ada lebih hemat daripada menambah layanan analytics berbayar.

## 20.8 Google Search Console

Tiga hal yang dibutuhkan GSC: **verifikasi kepemilikan**, **robots.txt**, dan **sitemap.xml**. Dua terakhir
juga dipakai mesin pencari lain, jadi jangan skip.

### a. Meta verification dari env

```ts
// nuxt.config.ts — runtimeConfig.public
gscVerification: process.env.NUXT_PUBLIC_GSC_VERIFICATION || '',
siteUrl: process.env.NUXT_PUBLIC_SITE_URL || 'https://example.com',
```

```vue
<!-- app/app.vue -->
<script setup lang="ts">
const { public: { gscVerification } } = useRuntimeConfig()
useHead({
  meta: gscVerification ? [{ name: 'google-site-verification', content: gscVerification }] : [],
})
</script>
```

Token kosong = meta tidak dirender (tidak ada tag sampah di HTML). Isi token lewat
`kubectl set env deploy/web NUXT_PUBLIC_GSC_VERIFICATION=<token>` — tanpa rebuild image.

### b. robots.txt dinamis

```ts
// app/server/routes/robots.txt.ts
export default defineEventHandler((event) => {
  const { public: { siteUrl } } = useRuntimeConfig(event)
  setHeader(event, 'Content-Type', 'text/plain; charset=utf-8')
  return ['User-agent: *', 'Allow: /', 'Disallow: /akun/', 'Disallow: /api/', '', `Sitemap: ${siteUrl}/sitemap.xml`, ''].join('\n')
})
```

### c. sitemap.xml dari API

`app/server/routes/sitemap.xml.ts` — route statis + kategori + artikel dari API. Kalau API gagal, tetap
kirim sitemap statis (jangan 500; GSC menandainya error dan berhenti crawl).

**Penting:** file server route harus di `app/server/routes/` karena `srcDir: 'app/'`. Kalau ditaruh di
`server/routes/` di root project, Nuxt tidak menemukannya dan rute 404 — sudah kejadian.

### d. Verifikasi

```bash
curl -s https://example.com/robots.txt              # 200, ada baris Sitemap:
curl -s https://example.com/sitemap.xml | grep -c '<loc>'
curl -s https://example.com/ | grep -o 'google-site-verification[^>]*'
```

Di GSC: **Add property** → **Domain** (butuh DNS TXT) atau **URL prefix** (meta tag / file HTML).
Untuk cara meta tag: pilih URL prefix → tab **HTML tag** → salin token `content="..."` → isi env → verifikasi.

Property **Domain** lebih kuat (mencakup semua subdomain) tapi butuh akses DNS TXT. Property **URL prefix**
lebih mudah dan cukup untuk satu hostname.

### e. Setelah terverifikasi

1. **Sitemaps** → submit `https://example.com/sitemap.xml`.
2. **URL Inspection** → tempel satu artikel → **Request indexing**.
3. Tunggu 2-3 hari untuk data **Performance** pertama.
4. **Page indexing** → lihat kalau ada halaman "Crawled - currently not indexed" (biasanya konten tipis).

### f. Jebakan

| Gejala | Sebab |
|---|---|
| Verifikasi gagal "tag not found" | meta hanya dirender di client, atau token belum masuk env, atau rollout belum selesai |
| robots.txt 404 | file di `server/routes/` bukan `app/server/routes/` (srcDir `app/`) |
| sitemap berisi URL lokal | `NUXT_PUBLIC_SITE_URL` tidak di-set, jatuh ke default |
| sitemap kosong artikelnya | API tidak bisa dijangkau dari pod (NAT hairpin / baseURL salah) |
| GSC bilang "Couldn't fetch" | port 80 diblokir, atau `robots.txt` balas 404 |
