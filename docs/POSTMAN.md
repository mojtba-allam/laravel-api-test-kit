# Postman collections in this test kit

Use Postman for **interactive** API regression (happy path + negatives + multi-step flows). Keep curl suites in `api/` for **CI**. Both layers should assert the same JSON contract ([POSTMAN_JSON_CONTRACT.md](POSTMAN_JSON_CONTRACT.md)).

## Generate

```bash
cd /path/to/laravel-api-test-kit
cp postman/config.example.php postman/config.php   # first time only
# edit postman/config.php for your routes & payloads

npm run postman:generate
# equivalent:
php postman/generate-collections.php
```

| Output | Use |
|--------|-----|
| `postman/collections/api.json` | Full nested collection |
| `postman/environments/local.environment.json` | Env vars for local `artisan serve` |
| `postman/flows/*.json` | One collection per multi-step flow |

Regenerate after every route/payload/test change — treat generated JSON as **build artifacts** (optional to commit; prefer committing `config.php` + scripts).

## Collection layout

```
Laravel API (name from config)
├── Public / <Module> / Happy Path | Negative Tests
├── Setup                          ← mint token / fixtures (optional)
├── Protected / <Module> / Happy Path | Negative Tests
└── Flows / <flow name>            ← run one folder in Collection Runner
```

**Rules**

- One HTTP action per request
- Description explains purpose + expected status
- Per-request tests assert status (and optional JSON keys)
- Collection-level script enforces JSON error envelope (unless `X-Skip-Contract: 1`)

## Documenting requests

In `postman/config.php`, every request should include:

```php
[
    'name' => 'POST resources',
    'method' => 'POST',
    'path' => '/resources',
    'description' => "Create a resource.\n\n**Expect:** 201 + `id`.",
    'body' => ['name' => 'Resource-{{unique_suffix}}'],
    'auth' => true,
    'status' => 201,
    'expect_keys' => 'id,name',       // optional
    'save' => ['id' => 'resource_id'], // optional → env
    'folder' => 'Happy Path',          // or 'Negative Tests'
],
```

### Happy vs negative coverage

| Folder | Cover |
|--------|--------|
| **Happy Path** | 2xx, correct shape, persist IDs into env for later steps |
| **Negative Tests** | 401/403/404/422, validation messages, auth boundaries |

Minimum for each write endpoint: **1 happy + 1 validation (422) + 1 auth (401/403)**.

## Running flows

**Preferred for localhost:** Collection Runner

1. Import collection + environment
2. Select **Local** env; set `base_url` / `access_token`
3. Open **Flows → \<name\>** (or a `flows/*.json` collection)
4. **Run** — failures show per-request status and test name

**Postman Flows (visual canvas):** cloud execution cannot call `localhost`. Use desktop Collection Runner, or expose the API with a tunnel and change `base_url`.

## Newman (optional CI)

```bash
npx --yes newman run postman/collections/api.json \
  -e postman/environments/local.environment.json \
  --folder "Flows"
```

Point `base_url` at a running app. Prefer shell `api/` suites for primary CI; Newman is optional parity.

## Related

- [POSTMAN_CUSTOMIZATION.md](POSTMAN_CUSTOMIZATION.md) — new project checklist
- [POSTMAN_MCP.md](POSTMAN_MCP.md) — sync workspace via MCP
- [POSTMAN_JSON_CONTRACT.md](POSTMAN_JSON_CONTRACT.md) — assertable JSON shapes
- [CUSTOMIZATION.md](CUSTOMIZATION.md) — curl adapter / routes
