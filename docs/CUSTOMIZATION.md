# Customization Guide

Use this guide when adapting the test kit to **your** Laravel API.

## Step 1: Auth adapter

Copy and edit the generic adapter:

```bash
cp scripts/adapters/generic/mint-token.php scripts/adapters/myapp/mint-token.php
```

Update:

- User model FQCN (`App\Models\User` or `Modules\User\Models\User`)
- Admin/role assignment logic
- Any required fields on user creation

Set in `config/test.env`:

```bash
MINT_TOKEN_SCRIPT=scripts/adapters/myapp/mint-token.php
```

Test:

```bash
php scripts/adapters/myapp/mint-token.php --email=qa@myapp.test --json
```

## Step 2: Response shape

If your API wraps resources differently, set:

```bash
JSON_ID_PATH=id          # flat: { "id": 1 }
JSON_ID_PATH=data.id     # wrapped: { "data": { "id": 1 } }
```

Helpers `json_id`, `create_workspace`, etc. respect this setting.

## Step 3: Routes and payloads

Each `api/test-*.sh` file maps to a **module**. To adapt:

1. Open the suite (e.g. `test-workspace-api.sh`)
2. Update endpoint paths (`/workspaces` → your routes)
3. Update JSON field names in POST/PUT bodies
4. Update expected HTTP status codes if your API differs

**Tip:** Start with one small suite, get it green, then expand.

## Step 4: Fixture builders

`api-test-helpers.sh` provides chain builders used across suites:

| Function | Creates |
|----------|---------|
| `create_workspace` | Top-level container |
| `create_project` | Needs `WORKSPACE_ID` |
| `create_section` | Needs `PROJECT_ID` |
| `create_column` | Needs `SECTION_ID` |
| `create_task` | Needs `COLUMN_ID` |

Edit these functions once — all dependent suites inherit the change.

For unrelated domain models, add parallel helpers:

```bash
create_order() {
  local suffix="$1"
  local response
  response=$(api_json POST "/orders" "{\"name\":\"Order-$suffix\"}")
  ORDER_ID=$(json_id "$(body_from_response "$response")")
}
```

## Step 5: Seeders for policy tests

Policy suites (`test-policy-authorization-api.sh`, `policy/policy-fixtures.sh`) expect **pre-seeded users** with known roles.

1. Create a `TestingSeeder` in your app with fixed emails
2. Document emails in `config/test.env`:

```bash
SEED_ADMIN_EMAIL=admin@test.local
SEED_OWNER_EMAIL=owner@test.local
SEED_MEMBER_EMAIL=member@test.local
```

3. Run `php artisan db:seed --class=TestingSeeder` before policy suites

## Step 6: E2E customization

| File | What to change |
|------|----------------|
| `e2e/support/config.ts` | Reads `config/test.env` automatically |
| `e2e/support/auth.ts` | Registration fields, pending-registration model |
| `e2e/support/helpers.ts` | API fixture creators (workspace, project, task) |
| `e2e/*.spec.ts` | UI selectors (`getByRole`, `data-testid`) |

Set pending registration model if used:

```bash
PENDING_REGISTRATION_MODEL=App\\Models\\PendingRegistration
```

## Step 7: Add a new API suite

```bash
cp api/test-workspace-api.sh api/test-orders-api.sh
```

Template:

```bash
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "Orders API Tests"
login_admin
create_workspace "orders"
create_project "orders"

RESPONSE=$(api_get "/orders")
assert_api "GET /orders → 200" "200" "$RESPONSE"

trap cleanup_common_records EXIT
print_summary_and_exit
```

Register in `api/run-all-api-tests.sh` → `TEST_SCRIPTS` array.

## Step 8: Remove App-specific suites

Delete or skip suites that don't apply:

- `test-task-required-skills-api.sh`
- `test-project-docs-api.sh`
- `test-social-auth-api.sh`

Comment them out in `run-all-api-tests.sh`.

## Adapting for non-Laravel apps

The shell helpers (`api_json`, `assert_api`, JSON assertions) work with any JSON HTTP API. Replace:

- `mint_token_for` → your auth (API key, OAuth, etc.)
- `assert_db_*` → remove or replace with direct DB client

E2E and k6 scripts are similarly adaptable via `BASE_URL` and auth headers.
