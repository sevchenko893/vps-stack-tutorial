# 20. Google Analytics 4 di Nuxt (tanpa dependency)

Dipakai di kabarecing.com. Satu plugin, satu env var, tanpa `nuxt-gtag` / `@nuxtjs/google-analytics`.

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
