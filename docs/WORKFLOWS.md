# Workflow Tests (A → B → C)

Many suites exercise **multi-step business flows** where each step depends on the previous one. This mirrors real user journeys and catches integration bugs that isolated CRUD tests miss.

## Pattern

```
A: Authenticate + seed context
    ↓
B: Create parent resources (workspace → project → board)
    ↓
C: Perform action under test + assert side effects
    ↓
D: Cleanup (trap EXIT)
```

## Examples in this kit

### Integration API (`test-integration-api.sh`)

```
Phase 1: List CI providers
Phase 2: Create integration on project
Phase 3: List project integrations
Phase 4: Test connection
Phase 5: Trigger run / list runs
Phase 6: Update + delete integration
```

Each phase uses IDs from the previous phase (`PROJECT_ID`, `INTEGRATION_ID`).

### Permission grant flow (`test-permission-grant-flow-api.sh`)

```
A: Admin creates workspace + project
B: Invite member with role
C: Member accepts / gains permissions
D: Member performs allowed action
E: Member blocked on forbidden action
```

### Email verification flow (`test-email-verification-flow-api.sh`)

```
A: Register pending user
B: Send verification code
C: Verify code → active user
D: Login succeeds
```

### Import 100 tasks (`test-import-100-tasks-api.sh`)

```
A: Build project board structure
B: Bulk import tasks
C: Verify count, hierarchy, assignments via API + DB
```

### Notifications cross-user (`test-notifications-cross-user-api.sh`)

```
A: User A creates task, assigns User B
B: User B receives notification
C: User B marks read / preferences apply
```

### Policy authorization (`test-policy-authorization-api.sh`)

```
A: setup_policy_fixtures — 6 users, shared resources
B: For each (role × endpoint × action): expect allow/deny
C: teardown_policy_fixtures
```

## Writing a new workflow test

```bash
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/api-test-helpers.sh"

echo "=== Workflow: Order → Payment → Shipment ==="

# ── A: Setup ──
login_admin
create_workspace "wf"
create_project "wf"

# ── B: Create order ──
RESPONSE=$(api_json POST "/orders" "{\"project_id\":\"$PROJECT_ID\",\"total\":99.99}")
ORDER_ID=$(json_id "$(body_from_response "$RESPONSE")")
assert_api "POST /orders → 201" "201" "$RESPONSE"

# ── C: Pay ──
RESPONSE=$(api_json POST "/orders/$ORDER_ID/pay" '{"method":"card"}')
assert_api "POST /orders/{id}/pay → 200" "200" "$RESPONSE"
assert_db_field_value "orders" "$ORDER_ID" "status" "paid"

# ── D: Ship ──
RESPONSE=$(api_json POST "/orders/$ORDER_ID/ship" '{}')
assert_api "POST /orders/{id}/ship → 200" "200" "$RESPONSE"

trap cleanup_common_records EXIT
print_summary_and_exit
```

## Best practices for chains

1. **One workflow per file** — keeps failures diagnosable
2. **Named phases** — echo `--- Phase N: Description ---`
3. **Guard conditionals** — `if [ -n "$ORDER_ID" ]; then` before dependent steps
4. **Unique resource names** — `$(date +%s)-$RANDOM` avoids collisions in parallel CI
5. **Always trap cleanup** — even on `set -e` failure
6. **Assert DB + HTTP** — UI-facing state should match database
7. **Multi-user flows** — use `login_as` + `act_as` to switch identities

## E2E workflow equivalents

Playwright specs like `invite-flow-full.spec.ts` and `member-invites.spec.ts` run the same A→B→C pattern through the browser:

- `setupAuthenticatedPage` or `mintToken` for A
- API helpers in `e2e/support/helpers.ts` for fast B setup
- UI interactions + `expect()` for C

Prefer API setup for B when the UI path is not what you're testing — it's faster and more stable.
