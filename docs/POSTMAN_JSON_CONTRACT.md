# API JSON contract (for Postman + curl assertions)

Agree on response shapes so Postman collection tests and `api/api-test-helpers.sh` assert the same contract. Adjust your Laravel `Exception` handler / API Resources to match, **or** edit `postman/scripts/collection-test.js` and helper parsers to match your existing API.

## Success responses

### Flat resource (recommended default for this kit)

```json
{
  "id": "uuid-or-int",
  "name": "Example",
  "created_at": "2026-01-01T00:00:00+00:00"
}
```

Postman: `expect_keys` => `id,name`  
Curl: `JSON_ID_PATH=id`

### Wrapped resource

```json
{
  "data": {
    "id": 1,
    "name": "Example"
  }
}
```

Postman: `expect_keys` => `data.id,data.name` and `save` => `['data.id' => 'resource_id']`  
Curl: `JSON_ID_PATH=data.id`

### Lists

```json
{
  "data": [ { "id": 1 }, { "id": 2 } ],
  "meta": { "current_page": 1, "total": 2 }
}
```

Assert `data` is an array; don’t require full pagination meta unless the product guarantees it.

### Empty success

- `204 No Content` — no body (collection test skips JSON parse)
- `200` with `[]` or `{ "data": [] }` — document which you use

## Error responses

### Validation (422)

Laravel default:

```json
{
  "message": "The name field is required.",
  "errors": {
    "name": ["The name field is required."]
  }
}
```

### Domain / auth errors (401, 403, 404, 409, 500)

Prefer a stable envelope:

```json
{
  "error": "not_found",
  "message": "Resource not found."
}
```

Optional extras: `code` (int), `details` (object). Keep **`message`** always present so clients and tests can display something.

Collection-level script accepts either `error` **or** `errors` plus `message`. Skip the contract with header `X-Skip-Contract: 1` for non-JSON responses.

## Headers

| Header | Purpose |
|--------|---------|
| `Accept: application/json` | Force JSON errors from Laravel |
| `Content-Type: application/json` | JSON bodies |
| `Authorization: Bearer {{access_token}}` | Default protected auth |
| `X-Skip-Contract: 1` | Skip collection JSON contract tests |

## Status code conventions

| Code | Use |
|------|-----|
| 200 | Read / update success with body |
| 201 | Create success with body |
| 204 | Delete / action success without body |
| 401 | Missing/invalid credentials |
| 403 | Authenticated but not allowed |
| 404 | Unknown id |
| 422 | Validation / semantic input errors |
| 429 | Rate limit |

Postman negative folders should assert the **exact** status your API returns (don’t use broad `status < 500` in happy paths).

## Idempotency & uniqueness in tests

- Use `{{unique_suffix}}` (set in collection prerequest) in create bodies
- Don’t hard-code emails/slugs that collide across runs
- Persist created ids with `save` / env vars for later steps in the same run

## Aligning Laravel code

1. Use `Accept: application/json` in tests (already set by the generator)
2. Return API Resources or consistent arrays — avoid mixing flat and wrapped in the same module
3. Customize `bootstrap/app.php` exception rendering only if you need a custom `error` key; otherwise rely on Laravel’s `message` + `errors`
4. Document deviations in your project’s `postman/config.php` descriptions, not by weakening assertions globally
