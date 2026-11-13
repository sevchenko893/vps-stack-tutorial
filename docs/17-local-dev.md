# 17. Development di laptop

Cluster dipakai untuk produksi. Ngoding tetap lokal.

## 17.1 Prasyarat laptop

| Tool | Versi | Untuk |
|---|---|---|
| PHP | 8.3 | Laravel |
| Composer | 2.x | dependency PHP |
| Node | 22 | Nuxt |
| Docker | opsional | Postgres lokal |
| `psql` | 16 | inspeksi DB |

## 17.2 Postgres lokal

```bash
docker run -d --name pg-dev -p 5432:5432 \
  -e POSTGRES_DB=app -e POSTGRES_USER=app -e POSTGRES_PASSWORD=secret \
  postgres:16
```

Atau langsung ke Postgres di cluster (butuh tunnel):

```bash
ssh -L 5432:127.0.0.1:5432 user@vps &
kubectl -n app port-forward svc/postgres 5432:5432 &
```

## 17.3 Backend

```bash
cd backend
cp .env.example .env
php artisan key:generate
php artisan migrate --seed
php artisan serve --port=8000
curl -s http://127.0.0.1:8000/api/articles
```

`.env` lokal:

```dotenv
APP_ENV=local
APP_DEBUG=true
APP_URL=http://127.0.0.1:8000
DB_CONNECTION=pgsql
DB_HOST=127.0.0.1
DB_DATABASE=app
DB_USERNAME=app
DB_PASSWORD=secret
FRONTEND_ORIGINS=http://127.0.0.1:3000
SESSION_DOMAIN=127.0.0.1
SESSION_SECURE_COOKIE=false
SANCTUM_STATEFUL_DOMAINS=127.0.0.1:3000
```

`SESSION_SECURE_COOKIE=false` wajib di lokal — kalau tidak, cookie tidak dikirim lewat `http://` dan login SPA gagal 419.

## 17.4 Frontend

```bash
cd frontend
npm install
NUXT_PUBLIC_API_BASE=http://127.0.0.1:8000 npm run dev
# http://127.0.0.1:3000
```

## 17.5 Bedanya lokal vs cluster

| Hal | Lokal | Cluster |
|---|---|---|
| URL API | `http://127.0.0.1:8000` | `https://app.example.com` |
| `APP_DEBUG` | `true` | `false` |
| Session cookie | non-secure | secure |
| Cache driver | `file` | `database` |
| Migrasi | manual `php artisan migrate` | otomatis saat container start |
| Log | `storage/logs/laravel.log` | stdout (`kubectl logs`) |

Jangan pernah copy `.env` cluster ke laptop: `APP_KEY` sama, `DB_PASSWORD` produksi, `SESSION_SECURE_COOKIE=true` → semua bikin bingung.

## 17.6 Test sebelum push

```bash
cd backend  && php artisan test
cd frontend && npm run build      # tangkap error SSR yang tidak muncul di dev
```

`npm run build` penting: banyak error Nuxt (import server-only, akses `window`) hanya muncul saat build/SSR, bukan di `npm run dev`.

## 17.7 Deploy dari branch

```bash
git checkout -b feat/xxx
git push -u origin feat/xxx
gh pr create --fill
```

Merge ke `main` = deploy. Kalau butuh preview per-branch, itu butuh workflow terpisah + namespace per-branch — belum ada di stack ini.
