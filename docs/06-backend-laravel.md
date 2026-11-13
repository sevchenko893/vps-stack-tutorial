# 6. Backend Laravel 12 (API)

Struktur repo aplikasi:

```
backend/            Laravel 12 (API-only, Sanctum token)
frontend/           Nuxt 3
.github/workflows/  CI/CD
```

## 6.0 Scaffold dari nol

```bash
composer create-project laravel/laravel backend
cd backend
composer require laravel/sanctum
php artisan install:api            # bikin routes/api.php + config sanctum
```

`php artisan install:api` menambahkan middleware `auth:sanctum`, migration token pribadi, dan `routes/api.php`. Setelah itu:

```bash
php artisan migrate            # butuh DB lokal dulu, atau isi .env ke Postgres di cluster
php artisan key:generate --show
```

Untuk pengembangan lokal tanpa cluster:

```bash
php artisan serve --host=0.0.0.0 --port=8000
```

## 6.1 Dockerfile

[backend/Dockerfile](../manifests/Dockerfile.backend) — dua stage:

```dockerfile
FROM composer:2 AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader --no-scripts

FROM php:8.3-cli
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends libpq-dev libzip-dev unzip \
    && docker-php-ext-install pdo_pgsql && rm -rf /var/lib/apt/lists/*
COPY --from=vendor /app/vendor ./vendor
COPY . .
RUN mkdir -p storage/framework/cache storage/framework/sessions storage/framework/views storage/logs bootstrap/cache \
    && chown -R www-data:www-data storage bootstrap/cache
EXPOSE 8000
CMD ["php", "artisan", "serve", "--host=0.0.0.0", "--port=8000"]
```

Catatan:
- `--no-scripts` di stage vendor karena `.env` belum ada saat build.
- `pdo_pgsql` wajib — image `php:cli` tidak membawanya.
- `php artisan serve` cukup untuk traffic kecil. Naik ke `php-fpm` + nginx kalau butuh throughput.

## 6.2 Secret aplikasi

```bash
cd backend && php artisan key:generate --show   # base64:...
cd ..

kubectl -n app create secret generic app-secrets \
  --from-literal=APP_KEY='base64:...' \
  --from-literal=DB_PASSWORD="$DB_PASS"
```

## 6.3 Deploy

```bash
# GHCR_OWNER = username GitHub (huruf kecil), dipakai di nama image
export GHCR_OWNER="username-github-kamu"
export APP_HOST="app.example.com" APP_HOST_DOTTED='app\.example\.com'

envsubst < manifests/app/30-app.yaml | kubectl apply -f -
kubectl -n app rollout status deploy/api
```

Tanpa `envsubst`, YAML akan berisi `${GHCR_OWNER}` literal dan pod berakhir `ImagePullBackOff`.

Migrasi dijalankan saat container start, bukan saat build:

```yaml
command:
  - sh
  - -c
  - |
    set -e
    php artisan migrate --force
    php artisan db:seed --force || true
    php artisan config:cache
    php artisan route:cache
    exec php artisan serve --host=0.0.0.0 --port=8000
```

- `migrate --force` — wajib di `APP_ENV=production`, kalau tidak artisan minta konfirmasi interaktif lalu gagal.
- `db:seed || true` — seed idempoten; kegagalan seed tidak boleh menahan pod.
- `config:cache` **setelah** env tersedia — kalau di-cache saat build, env runtime diabaikan.
- `exec` supaya php jadi PID 1 dan menerima SIGTERM dari kubelet (graceful shutdown).

## 6.4 Env penting

| Var | Nilai | Kenapa |
|---|---|---|
| `LOG_CHANNEL` | `stderr` | Log masuk `kubectl logs`, bukan file di dalam container. |
| `SESSION_DRIVER`, `CACHE_STORE`, `QUEUE_CONNECTION` | `database` | Tanpa Redis; tabel dibuat oleh migration. |
| `SESSION_DOMAIN` | `.example.com` | Cookie Sanctum dipakai bersama web + api. |
| `SESSION_SECURE_COOKIE` | `true` | Hanya HTTPS. |
| `SANCTUM_STATEFUL_DOMAINS` | `example.com,www.example.com` | Domain frontend yang boleh SPA-auth. |
| `FRONTEND_ORIGINS` | `https://example.com,...` | Dipakai `config/cors.php` (`allowed_origins`). |
| `TRUSTED_PROXIES` | `*` | Di belakang Traefik; tanpa ini Laravel melihat IP internal dan `https` salah terdeteksi. |

`config/cors.php`:

```php
'paths' => ['api/*', 'sanctum/csrf-cookie'],
'allowed_origins' => array_filter(explode(',', env('FRONTEND_ORIGINS', 'http://127.0.0.1:3001'))),
'supports_credentials' => true,
```

## 6.5 Health check

Laravel 11+ sudah punya route `/up` (bootstrap/app.php `health: '/up'`). Readiness probe memakai itu:

```yaml
readinessProbe:
  httpGet: {path: /up, port: 8000}
  initialDelaySeconds: 10
  periodSeconds: 10
```

Ingress juga harus me-route `/up` ke api, bukan ke frontend.

## 6.6 Cek cepat

```bash
kubectl -n app logs deploy/api --tail=50
kubectl -n app exec deploy/api -- php artisan migrate:status

# /api/articles hanya contoh — ganti dengan route yang benar-benar kamu buat.
# Laravel baru dari `composer create-project` belum punya route ini.
curl -s https://$APP_HOST/up -o /dev/null -w '%{http_code}\n'
curl -s https://$APP_HOST/api/articles | head -c 200
```
