# E2E Testing

Browser tests live in `e2e/` and use [Playwright](https://playwright.dev/) (Chromium).

## Configuration

Playwright reads from `config/test.env` via `e2e/support/config.ts`:

| Setting | Env key | Default |
|---------|---------|---------|
| Laravel path | `PROJECT_ROOT` | required |
| Base URL | `PLAYWRIGHT_BASE_URL` | `http://127.0.0.1:8000` |
| API prefix | `API_PREFIX` | `/api/v1` |
| Email domain | `TEST_EMAIL_DOMAIN` | `test.example.com` |

## Running

```bash
npm install
npx playwright install chromium

# App must be running OR let Playwright start it (needs PROJECT_ROOT)
npx playwright test

# Single spec
npx playwright test e2e/invite-flow-full.spec.ts

# UI mode
npx playwright test --ui

# Against staging
PLAYWRIGHT_BASE_URL=https://staging.example.com npx playwright test
```

## Auth strategies

### Fast: mint token (recommended for API-level E2E)

```typescript
import { mintToken } from './support/auth'

const { token } = mintToken(undefined, true) // admin
const headers = { Authorization: `Bearer ${token}` }
```

Uses the same PHP adapter as curl API tests.

### Full UI: register + login

```typescript
import { setupAuthenticatedPage } from './support/helpers'

const { user, token } = await setupAuthenticatedPage(page, request)
```

Drives registration, email verification (reads code from DB), injects token into `localStorage`, navigates to dashboard.

### UI login only

```typescript
import { loginViaUi, uniqueUser, registerUser } from './support/auth'

const user = uniqueUser()
await registerUser(request, user)
await loginViaUi(page, user)
```

## Spec inventory

| Spec | Coverage |
|------|----------|
| `full-coverage.spec.ts` | Broad UI smoke |
| `invite-flow-full.spec.ts` | Member invite A→B→C |
| `member-invites.spec.ts` | Invite acceptance |
| `permission-visibility.spec.ts` | Role-based UI visibility |
| `creator-permissions.spec.ts` | Creator role gates |
| `teams-permission-visibility.spec.ts` | Team permissions |
| `email-verification.spec.ts` | Pending registration UI |
| `real-email-verification.spec.ts` | Mail.tm integration |
| `cicd-integrations.spec.ts` | Integration API (no browser) |
| `project-docs.spec.ts` | Project documentation modal |
| `notification-sound.spec.ts` | Notification preferences |
| `ui-interactions.spec.ts` | Buttons, modals, forms |
| `performance.spec.ts` | Page load budgets |

## Support files

- `support/helpers.ts` — API fixtures, page setup, waits
- `support/auth.ts` — users, registration, mint token
- `support/config.ts` — env loading
- `support/mail-tm.ts` — disposable email for real SMTP tests
- `seed-demo.mjs` — demo data script

## Locator strategy

Follow accessibility-first selectors:

1. `getByRole`
2. `getByLabel`
3. `getByPlaceholder`
4. `getByText`
5. `getByTestId`

## CI notes

- Set `PLAYWRIGHT_BASE_URL` to skip auto-starting `artisan serve`
- Use `CI=true` for blob reporter
- `PLAYWRIGHT_TRACE=on` for failure traces
- Build frontend assets if testing Vite pages: `npm run build` in `PROJECT_ROOT`

## Adapting to your app

1. Update login/register field selectors in `auth.ts`
2. Update post-login URL regex (`/dashboard` → your home route)
3. Update `helpers.ts` API payloads to match your validation rules
4. Remove App-specific specs you don't need
