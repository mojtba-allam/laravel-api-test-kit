# Postman customization for a new Laravel API

Checklist to retarget the Postman kit without forking the generator.

## 1. Copy config

```bash
cp postman/config.example.php postman/config.php
```

`config.php` is gitignored by default so secrets (mint passwords) stay local. Commit a **sanitized** project template if your team shares routes (e.g. `config.myapp.example.php`).

## 2. Map your API surface

Edit these keys in `config.php`:

| Key | Based on |
|-----|----------|
| `base_url` / env `base_url` | `php artisan serve` host:port |
| `api_prefix` | Your route prefix (`/api/v1`, `/api`, …) |
| `auth_mode` | `bearer` (Sanctum/Passport), `none`, or `custom` + `auth_headers` |
| `modules[]` | One entry per domain area (mirrors `api/test-*-api.sh` modules) |
| `setup_requests[]` | How Postman obtains `access_token` (login/mint endpoint) |
| `flows[]` | Critical A→B→C paths you also cover in shell workflow tests |

**Source of truth for paths/fields:** Laravel route list + Form Requests + API Resources — not guesses from UI copy.

```bash
cd "$PROJECT_ROOT"
php artisan route:list --path=api
```

## 3. Align with curl helpers

| Curl kit | Postman kit |
|----------|-------------|
| `BASE_URL` in `config/test.env` | `base_url` + `api_prefix` |
| `JSON_ID_PATH=data.id` | `expect_keys` / `save` with dotted paths (`data.id`) |
| `MINT_TOKEN_SCRIPT` | Setup request or paste token into env |
| `api/test-<module>-api.sh` | `modules[]` entry with same routes |

Keep status codes and error shapes identical so Newman and `./api/run-all-api-tests.sh` fail for the same regressions.

## 4. Add requests (happy + bad)

For each endpoint:

1. Happy request with realistic body (use `{{unique_suffix}}` / env vars)
2. `status` + `expect_keys` for success
3. `save` IDs needed by later steps
4. Negative: missing field → 422; no token → 401; wrong user → 403; missing id → 404

Group with `'folder' => 'Happy Path'` or `'Negative Tests'`.

## 5. Define flows

```php
'flows' => [
    [
        'slug' => 'flow-order-checkout',
        'name' => 'Flow — create order then pay',
        'description' => 'A→B chain used in QA smoke.',
        'steps' => [
            'ref:Orders/POST orders',
            'ref:Payments/POST payments',
        ],
    ],
],
```

`ref:ModuleName/Request name` must match `modules[].name` + `requests[].name` exactly.

## 6. Regenerate and verify

```bash
npm run postman:generate
# Import or MCP putCollection
# Collection Runner → Flows → one folder
```

## 7. What to edit vs leave alone

| Edit for each project | Rarely edit |
|-----------------------|-------------|
| `postman/config.php` | `generate-collections.php` |
| Env variable list | Collection schema version |
| `scripts/collection-test.js` if error envelope differs | Folder nesting algorithm |

## 8. Auth strategies

| Strategy | Setup |
|----------|--------|
| Paste Sanctum token | Set `access_token` in environment; leave `setup_requests` empty |
| HTTP login | Add Setup `POST /login` (or `/token`) with `save` → `access_token` |
| Custom header (DPoP, API key) | `auth_mode` => `custom` + `auth_headers` |

Prefer the same mint approach as `scripts/adapters/*/mint-token.php` so Postman and curl see identical permissions.
