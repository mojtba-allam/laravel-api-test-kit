# Laravel API Test Kit

Portable, production-style test suite for Laravel REST APIs. Covers **every endpoint action** with real HTTP requests, multi-step **A→B→C workflow** tests, **policy/authorization** matrices, **Playwright E2E** flows, and **k6** performance checks.

Originally built for [Finolo](https://github.com/mojtba-allam/finolo); structured so you can point it at any Laravel + Sanctum project.

## What's included

| Layer | Location | Purpose |
|-------|----------|---------|
| **API (curl)** | `api/` | 40+ shell suites — CRUD, validation, multipart, policies |
| **Helpers** | `api/api-test-helpers.sh` | Auth, HTTP, JSON assertions, DB checks, fixtures |
| **Workflow / chain** | `api/test-*-flow*.sh`, `api/test-integration-api.sh` | Multi-phase A→B→C scenarios |
| **Policy matrix** | `api/test-policy-authorization-api.sh` | Role × resource × action coverage |
| **E2E (Playwright)** | `e2e/` | UI + API hybrid, invite flows, permissions |
| **Performance** | `performance/k6-api-load.js` | Latency & throughput thresholds |
| **Adapters** | `scripts/adapters/` | Project-specific token minting |

## Quick start

```bash
git clone https://github.com/mojtba-allam/laravel-api-test-kit.git
cd laravel-api-test-kit

# 1. Configure
cp config/test.env.example config/test.env
# Edit PROJECT_ROOT=/path/to/your/laravel-app

# 2. Prepare the app
cd $PROJECT_ROOT
php artisan migrate --seed
php artisan serve --host=127.0.0.1 --port=8000

# 3. Run API tests (from test-kit root)
cd /path/to/laravel-api-test-kit
./scripts/setup-project.sh
./api/run-all-api-tests.sh

# 4. Run E2E (optional)
npm install
npx playwright install chromium
npx playwright test
```

Or use the Finolo preset:

```bash
cp config/finolo.env.example config/test.env
# Adjust PROJECT_ROOT if needed
```

## Documentation

- [Getting Started](docs/GETTING_STARTED.md) — install, configure, first run
- [Customization Guide](docs/CUSTOMIZATION.md) — adapt suites to your API routes & models
- [Helpers Reference](docs/HELPERS.md) — `api-test-helpers.sh` functions
- [Workflow Tests (A→B→C)](docs/WORKFLOWS.md) — multi-step chain patterns
- [E2E Testing](docs/E2E.md) — Playwright setup & auth strategies
- [Performance](docs/PERFORMANCE.md) — k6 load tests
- [Best Practices](docs/BEST_PRACTICES.md) — speed, seeders, real data, CI

## Design principles

1. **No mocks** — hit the real API and database
2. **Fast auth** — mint Sanctum tokens via adapter scripts (skip fragile email flows in API suites)
3. **Isolated data** — unique timestamps/emails per run; cleanup helpers
4. **Configurable** — `config/test.env` drives URLs, paths, adapters, seeded users
5. **Portable** — test kit lives in its own repo; `PROJECT_ROOT` points at your app

## Repository layout

```
laravel-api-test-kit/
├── api/                    # curl-based API test suites
│   ├── api-test-helpers.sh # shared library (source this)
│   ├── run-all-api-tests.sh
│   └── test-*.sh
├── config/
│   ├── bootstrap.sh        # loads test.env
│   ├── test.env.example
│   └── finolo.env.example
├── e2e/                    # Playwright specs + support/
├── performance/            # k6 scripts
├── scripts/
│   ├── setup-project.sh
│   └── adapters/           # mint-token per project
└── docs/
```

## CI

See `.github/workflows/api-tests.yml` for a GitHub Actions template.

## License

MIT — see [LICENSE](LICENSE).
