# Helpers Reference

All API suites source `api/api-test-helpers.sh`, which loads `config/bootstrap.sh` first.

## HTTP helpers

| Function | Usage | Description |
|----------|-------|-------------|
| `api_get` | `api_get "/workspaces"` | GET with Bearer token |
| `api_json` | `api_json POST "/tasks" '{"title":"x"}'` | JSON request |
| `api_delete` | `api_delete "/tasks/1"` | DELETE |
| `api_multipart` | `api_multipart POST "/attachments" -F file=@x.txt` | File upload |

Global `TOKEN` is sent on every request. Switch users with `act_as "$OTHER_TOKEN"`.

## Response parsing

| Function | Example |
|----------|---------|
| `body_from_response` | `body=$(body_from_response "$RESPONSE")` |
| `status_from_response` | `status=$(status_from_response "$RESPONSE")` |
| `json_value` | `json_value "$body" "data.name"` |
| `json_id` | `json_id "$body"` — uses `JSON_ID_PATH` config |

## Assertions

| Function | Purpose |
|----------|---------|
| `print_result` | HTTP status check + pass/fail counter |
| `assert_api` | Shorthand: name, expected status(es), response |
| `assert_json_field` | Field exists in JSON |
| `assert_json_value` | Field equals expected |
| `assert_json_type` | Field type (string, number, array, object) |
| `assert_json_structure` | Multiple required fields |
| `assert_json_array_count` | Array length |
| `assert_validation_error` | Status 422 |
| `assert_validation_field` | 422 with field in errors |
| `assert_unauthorized` | Status 401 |
| `assert_forbidden` | Status 403 |
| `assert_not_found` | Status 404 |

## Database verification

Uses `php artisan tinker` against `PROJECT_ROOT`:

| Function | Example |
|----------|---------|
| `assert_db_has` | `assert_db_has "tasks" "id = 5"` |
| `assert_db_missing` | Record deleted |
| `assert_db_count` | Exact count |
| `assert_db_field_value` | Column value |
| `assert_db_relationship` | Child rows exist |
| `assert_db_timestamp` | `updated_at` set |

## Authentication

| Function | Description |
|----------|-------------|
| `mint_token_for` | `mint_token_for "user@test.local" [admin]` |
| `login_admin` | Fresh admin user + sets `TOKEN`, `USER_ID` |
| `login_as` | Returns token for email (stdout) |
| `login_as_super_admin` | Super-admin token (stdout) |
| `act_as` | `act_as "$TOKEN"` — switch active bearer |
| `test_email` | `test_email "prefix"` → unique email |

## Fixture builders (A→B→C chain)

Build dependent resources in order:

```bash
login_admin
create_workspace "mytest"    # → WORKSPACE_ID
create_project "mytest"      # → PROJECT_ID
create_section "mytest"      # → SECTION_ID
create_column "mytest"       # → COLUMN_ID
create_task "mytest"         # → TASK_ID
```

Alternate task variable: `create_task "x" TASK_ID_2`

## Cleanup

```bash
trap cleanup_common_records EXIT
```

Deletes `TASK_ID*`, `COLUMN_ID`, `SECTION_ID`, `PROJECT_ID`, `WORKSPACE_ID`, and test-specific IDs.

## Policy / multi-user

| Function | Description |
|----------|-------------|
| `add_member_direct` | Bypass invite flow (Finolo `ProjectService`) |
| `expected_gap` | Document known deviation (no pass/fail) |
| `skip_case` | Skip undefined policy ability |

Policy fixtures: `source api/policy/policy-fixtures.sh` then `setup_policy_fixtures` / `teardown_policy_fixtures`.

## Suite lifecycle

```bash
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

login_admin
create_workspace "suite"
create_project "suite"
# ... tests ...
trap cleanup_common_records EXIT
print_summary_and_exit
```

## E2E TypeScript helpers

See `e2e/support/helpers.ts`:

- `setupAuthenticatedPage` — register + inject token + goto dashboard
- `createWorkspace`, `createProject`, `createSection`, `createColumn`, `createTask`
- `mintToken` in `e2e/support/auth.ts` — same adapter as shell tests
