# Performance Testing

Load tests use [k6](https://k6.io/) in `performance/k6-api-load.js`.

## Install k6

```bash
# Ubuntu/Debian
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | \
  sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update && sudo apt-get install k6
```

## Run

```bash
# Default (local)
k6 run performance/k6-api-load.js

# Custom target
BASE_URL=https://staging.example.com/api/v1 \
TEST_EMAIL_DOMAIN=staging.test \
k6 run performance/k6-api-load.js
```

## Thresholds (default)

| Metric | Target |
|--------|--------|
| `http_req_duration` p95 | < 500ms |
| `http_req_duration` p99 | < 1500ms |
| `errors` rate | < 1% |
| `auth_duration` p95 | < 300ms |
| `project_duration` p95 | < 500ms |
| `task_duration` p95 | < 500ms |

## Load profile

```
10s → 5 VUs
30s → 10 VUs (sustained)
10s → 20 VUs (peak)
10s → ramp down
```

## What it exercises

- Register + login per VU
- Workspace / project / section / column / task CRUD
- Board fetch
- Search endpoint

## Adapting

1. Update `registerAndLogin()` if your auth flow differs
2. Replace resource creation payloads with your schema
3. Adjust `stages` for your SLA environment
4. For token minting at scale, consider a setup script that pre-creates users instead of registering per iteration

## CI integration

```yaml
- name: k6 load test
  run: |
    k6 run performance/k6-api-load.js \
      --env BASE_URL=${{ secrets.STAGING_API_URL }}
```

Run against staging only — not production without approval.

## When to run

- Before major releases
- After performance-sensitive changes (N+1 queries, indexes)
- Not on every PR (too slow/noisy) — nightly is typical
