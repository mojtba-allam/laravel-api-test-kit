# Getting Started

## Prerequisites

| Tool | Version | Used for |
|------|---------|----------|
| bash | 4+ | API shell suites |
| curl | any | HTTP requests |
| php | 8.2+ | Laravel artisan, mint-token adapters |
| node | 18+ | Playwright E2E (optional) |
| k6 | latest | Performance tests (optional) |

Your Laravel app must be running and reachable at `BASE_URL`.

## 1. Clone and configure

```bash
git clone <repo-url> laravel-api-test-kit
cd laravel-api-test-kit
cp config/test.env.example config/test.env
```

Edit `config/test.env`:

```bash
PROJECT_ROOT=/absolute/path/to/your/laravel-app
BASE_URL=http://127.0.0.1:8000/api/v1
TEST_EMAIL_DOMAIN=test.yourapp.local
MINT_TOKEN_SCRIPT=scripts/adapters/generic/mint-token.php
```

## 2. Prepare the Laravel application

```bash
cd "$PROJECT_ROOT"
composer install
cp .env.example .env
php artisan key:generate
php artisan migrate
php artisan db:seed    # required for policy suites with seeded users
```

Start the server:

```bash
php artisan serve --host=127.0.0.1 --port=8000
```

## 3. Verify setup

```bash
cd /path/to/laravel-api-test-kit
chmod +x scripts/setup-project.sh api/*.sh
./scripts/setup-project.sh
```

## 4. Run tests

**Full API suite:**

```bash
./api/run-all-api-tests.sh
```

**Single module:**

```bash
./api/test-workspace-api.sh
./api/test-task-api.sh
```

**Policy / authorization matrix:**

```bash
./api/test-policy-authorization-api.sh
```

**E2E (Playwright):**

```bash
npm install
npx playwright install chromium
export PROJECT_ROOT=/path/to/your/laravel-app   # or set in config/test.env
npx playwright test
```

**Performance:**

```bash
k6 run performance/k6-api-load.js
```

## Environment variables reference

All values can live in `config/test.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| `PROJECT_ROOT` | *(required)* | Laravel app path |
| `BASE_URL` | `http://127.0.0.1:8000/api/v1` | API base including version |
| `APP_URL` | derived | Public app URL |
| `TEST_EMAIL_DOMAIN` | `test.example.com` | Domain for generated emails |
| `AUTH_STRATEGY` | `mint_token` | `mint_token` or `http_login` |
| `MINT_TOKEN_SCRIPT` | generic adapter | Path to token minting script |
| `JSON_ID_PATH` | `data.id` | Dot path for resource IDs in JSON |
| `SEED_COMMAND` | `db:seed` | Artisan seed command |
| `CURL_INSECURE` | `1` | Use `curl -k` for local TLS |

## Troubleshooting

**`PROJECT_ROOT is not set`** — create `config/test.env` from the example.

**`mint_token_for: adapter not found`** — check `MINT_TOKEN_SCRIPT` path relative to test-kit root.

**401 on all requests** — verify Sanctum is configured; test adapter manually:

```bash
PROJECT_ROOT=/path/to/app php scripts/adapters/generic/mint-token.php --email=qa@test.local --json
```

**Policy tests fail** — ensure seeders created users listed in `SEED_*_EMAIL` variables.

**E2E cannot find Laravel** — `PROJECT_ROOT` must be set; Playwright `webServer.cwd` uses it.
