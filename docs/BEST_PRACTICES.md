# Best Practices

Guidelines used across this test kit for **speed**, **reliability**, and **real-world fidelity**.

## 1. Use real data, not mocks

- Hit the actual HTTP API and database
- Only mock **external** services (Stripe, SendGrid, third-party OAuth)
- Verify persistence with `assert_db_*` helpers after mutations

## 2. Authenticate once per suite

**Don't** register/login via HTTP in every API test. Use token minting:

```bash
login_admin   # one call at suite start
# all tests reuse $TOKEN
```

For multi-user policy tests, mint tokens for each seeded user once in `setup_policy_fixtures`.

Set `AUTH_STRATEGY=http_login` only when explicitly testing the auth endpoints.

## 3. Seeders vs dynamic creation

| Approach | When to use |
|----------|-------------|
| **Seeders** | Fixed roles, policy matrices, demo accounts (`admin@…`, `user-01@…`) |
| **Dynamic creation** | CRUD suites, parallel CI, avoiding collisions |

Recommended app setup:

```bash
php artisan migrate:fresh --seed   # local dev
php artisan db:seed --class=TestingSeeder   # CI: roles only
```

Document seeded emails in `config/test.env` (`SEED_ADMIN_EMAIL`, etc.).

## 4. Unique identifiers every run

```bash
"name": "TestWorkspace-$(date +%s)-$RANDOM"
email=$(test_email "api-test")
```

Prevents collisions when multiple developers or CI jobs run simultaneously.

## 5. Cleanup after every suite

```bash
trap cleanup_common_records EXIT
```

Delete resources you created. For resources without DELETE endpoints, use artisan tinker in cleanup or namespaced test DB.

## 6. Keep tests independent

- No suite should depend on another suite's output
- Each file creates its own workspace/project chain
- Policy suites use isolated `setup_policy_fixtures` / `teardown_policy_fixtures`

## 7. Speed optimizations

| Technique | Impact |
|-----------|--------|
| Token minting vs HTTP login | ~10× faster per suite |
| `api_json` helpers vs raw curl | Less boilerplate, fewer bugs |
| API setup in E2E vs UI clicks | 5–30s saved per test |
| `PHP_CLI_SERVER_WORKERS=10` | Parallel Playwright workers |
| `reuseExistingServer: true` | Skip server boot per run |
| Run single suite during dev | `./api/test-task-api.sh` |
| Skip heavy suites in PR CI | Policy matrix on nightly only |

## 8. No arbitrary sleeps

**Never** use `sleep` or `waitForTimeout` in E2E. Wait for state:

```typescript
await expect(page.getByRole('heading', { name: 'Dashboard' })).toBeVisible()
await page.waitForURL(/\/projects\/\d+/)
```

In shell tests, use conditional checks — not `sleep 2`.

## 9. Assert meaningfully

Every user action should assert:

- HTTP status
- Response shape (`assert_json_structure`)
- Business state (`assert_db_field_value`)
- Authorization boundary (403 for wrong user)

## 10. Structure for reuse

```
config/test.env          ← one place for URLs, paths, emails
api-test-helpers.sh      ← shared HTTP + auth + fixtures
api/test-<module>.sh     ← one module per file
api/run-all-api-tests.sh ← orchestrator
scripts/adapters/        ← project-specific auth
```

When adding endpoints to your app, extend the matching `test-*.sh` — don't create overlapping files.

Mirror the same modules in `postman/config.php` so interactive Postman coverage stays aligned with CI curl suites ([POSTMAN.md](POSTMAN.md)).

## 11. CI pipeline order

```
1. migrate + seed
2. start server (or use deployed staging)
3. API suites (fast, high signal)
4. Optional: Newman against generated Postman collection
5. E2E (slower, UI coverage)
6. k6 (nightly / pre-release)
```

## 12. Failure investigation

API suite failure:

```bash
./api/test-workspace-api.sh 2>&1 | tee /tmp/debug.log
```

E2E failure:

```bash
PLAYWRIGHT_TRACE=on npx playwright test --last-failed
npx playwright show-report
```

Postman / Newman failure: open the failed request’s **Test** results and compare status + JSON envelope to [POSTMAN_JSON_CONTRACT.md](POSTMAN_JSON_CONTRACT.md).

## 13. Adapting checklist for new projects

- [ ] `config/test.env` with `PROJECT_ROOT`
- [ ] Mint-token adapter for your User model
- [ ] `JSON_ID_PATH` matches API resources
- [ ] `create_*` helpers match your hierarchy
- [ ] TestingSeeder with policy users
- [ ] Trim irrelevant suites from `run-all-api-tests.sh`
- [ ] Update E2E login selectors and home URL
- [ ] Add your modules as new `test-*.sh` files
- [ ] `postman/config.php` with happy + negative requests and at least one flow
- [ ] `npm run postman:generate` and Collection Runner smoke
