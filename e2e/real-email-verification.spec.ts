/**
 * Real email verification E2E tests.
 * Uses mail.tm disposable inboxes — no mocking, no DB access, no skipping.
 *
 * Pending registration flow:
 *   1. POST /api/v1/auth/register → creates PendingRegistration, returns { email, pending_token }
 *   2. POST /api/v1/auth/pending/send-code { pending_token } → queues verification code email
 *   3. POST /api/v1/auth/pending/verify { pending_token, code } → creates user, returns { user, token }
 *
 * Run locally:  npx playwright test real-email-verification --project=chromium
 * Run vs prod: PLAYWRIGHT_BASE_URL=https://finolo.ir npx playwright test real-email-verification --project=chromium
 */
import { test, expect } from '@playwright/test'
import {
  createMailTmInbox,
  waitForVerificationCode,
  getMessageCount,
  deleteMailTmInbox,
  type MailTmInbox,
} from './support/mail-tm'

const PASSWORD = 'StrongPass123!'

test.describe('Real Email Verification (mail.tm)', () => {
  test.setTimeout(90_000)
  test.describe.configure({ mode: 'serial' })

  let inbox: MailTmInbox

  test.beforeEach(async () => {
    inbox = await createMailTmInbox()
  })

  test.afterEach(async () => {
    if (inbox) await deleteMailTmInbox(inbox)
  })

  test('API: full register → send-code → verify → authenticated', async ({ request }) => {
    const regRes = await request.post('/api/v1/auth/register', {
      data: {
        name: 'E2E Tester',
        email: inbox.address,
        password: PASSWORD,
        password_confirmation: PASSWORD,
        timezone: 'UTC',
      },
    })
    expect(regRes.status()).toBe(201)
    const pendingToken = (await regRes.json()).data?.pending_token
    expect(pendingToken).toBeTruthy()

    // Snapshot message count before send-code
    const before = await getMessageCount(inbox)

    const sendRes = await request.post('/api/v1/auth/pending/send-code', {
      data: { pending_token: pendingToken },
    })
    expect(sendRes.status()).toBe(200)

    // Wait for the NEW email (after send-code)
    const code = await waitForVerificationCode(inbox, 60_000, 3_000, before)
    expect(code).toMatch(/^\d{6}$/)

    const verifyRes = await request.post('/api/v1/auth/pending/verify', {
      data: { pending_token: pendingToken, code },
    })
    expect(verifyRes.status()).toBe(200)
    const verifyBody = await verifyRes.json()
    expect(verifyBody.data?.user?.email).toBe(inbox.address)
    expect(verifyBody.data?.user?.email_verified_at).toBeTruthy()
    expect(verifyBody.data?.token).toBeTruthy()

    const meRes = await request.get('/api/v1/auth/me', {
      headers: { Authorization: `Bearer ${verifyBody.data.token}` },
    })
    expect(meRes.status()).toBe(200)
    expect((await meRes.json()).data?.email).toBe(inbox.address)
  })

  test('API: wrong code is rejected', async ({ request }) => {
    const regRes = await request.post('/api/v1/auth/register', {
      data: {
        name: 'E2E Wrong Code',
        email: inbox.address,
        password: PASSWORD,
        password_confirmation: PASSWORD,
        timezone: 'UTC',
      },
    })
    expect(regRes.status()).toBe(201)
    const pendingToken = (await regRes.json()).data?.pending_token

    await request.post('/api/v1/auth/pending/send-code', {
      data: { pending_token: pendingToken },
    })

    const verifyRes = await request.post('/api/v1/auth/pending/verify', {
      data: { pending_token: pendingToken, code: '000000' },
    })
    expect(verifyRes.status()).toBe(422)
  })

  test('API: change-email then verify with new address', async ({ request }) => {
    const inbox2 = await createMailTmInbox()
    try {
      const regRes = await request.post('/api/v1/auth/register', {
        data: {
          name: 'E2E Change Email',
          email: inbox.address,
          password: PASSWORD,
          password_confirmation: PASSWORD,
          timezone: 'UTC',
        },
      })
      expect(regRes.status()).toBe(201)
      const pendingToken = (await regRes.json()).data?.pending_token

      const changeRes = await request.post('/api/v1/auth/pending/change-email', {
        data: { pending_token: pendingToken, email: inbox2.address },
      })
      expect(changeRes.status()).toBe(200)
      expect((await changeRes.json()).data?.email).toBe(inbox2.address)

      const before = await getMessageCount(inbox2)
      await request.post('/api/v1/auth/pending/send-code', {
        data: { pending_token: pendingToken },
      })

      const code = await waitForVerificationCode(inbox2, 60_000, 3_000, before)
      expect(code).toMatch(/^\d{6}$/)

      const verifyRes = await request.post('/api/v1/auth/pending/verify', {
        data: { pending_token: pendingToken, code },
      })
      expect(verifyRes.status()).toBe(200)
      expect((await verifyRes.json()).data?.user?.email).toBe(inbox2.address)
    } finally {
      await deleteMailTmInbox(inbox2)
    }
  })

  test('API: duplicate email rejected after user exists', async ({ request }) => {
    // Register + verify to create a real user
    const regRes = await request.post('/api/v1/auth/register', {
      data: {
        name: 'E2E First',
        email: inbox.address,
        password: PASSWORD,
        password_confirmation: PASSWORD,
        timezone: 'UTC',
      },
    })
    expect(regRes.status()).toBe(201)
    const pendingToken = (await regRes.json()).data?.pending_token

    const before = await getMessageCount(inbox)
    await request.post('/api/v1/auth/pending/send-code', {
      data: { pending_token: pendingToken },
    })

    const code = await waitForVerificationCode(inbox, 60_000, 3_000, before)
    expect(code).toMatch(/^\d{6}$/)

    const verifyRes = await request.post('/api/v1/auth/pending/verify', {
      data: { pending_token: pendingToken, code },
    })
    expect(verifyRes.status()).toBe(200)

    // Now duplicate register should fail with 422
    const dupRes = await request.post('/api/v1/auth/register', {
      data: {
        name: 'E2E Duplicate',
        email: inbox.address,
        password: PASSWORD,
        password_confirmation: PASSWORD,
        timezone: 'UTC',
      },
    })
    expect(dupRes.status()).toBe(422)
    expect((await dupRes.json()).errors?.email).toBeTruthy()
  })

  test('UI: register → verify page → enter code → dashboard', async ({ page }) => {
    await page.goto('/register')
    await expect(page.locator('[data-testid="register-form"]')).toBeVisible({ timeout: 15_000 })

    await page.locator('[data-testid="register-name"]').fill('E2E UI')
    await page.locator('[data-testid="register-email"]').fill(inbox.address)
    await page.locator('[data-testid="register-password"]').fill(PASSWORD)
    await page.locator('[data-testid="register-confirm"]').fill(PASSWORD)
    await page.locator('[data-testid="register-submit"]').click()

    await expect(page).toHaveURL(/\/verify-email/, { timeout: 15_000 })
    await expect(page.locator('[data-testid="email-verification-page"]')).toBeVisible()

    await page.locator('[data-testid="send-code-button"]').click()
    await expect(page.locator('[data-testid="code-input-0"]')).toBeVisible({ timeout: 15_000 })

    const code = await waitForVerificationCode(inbox)
    for (let i = 0; i < 6; i++) {
      await page.locator(`[data-testid="code-input-${i}"]`).fill(code[i])
    }

    await page.locator('[data-testid="verify-button"]').click()
    await expect(page).toHaveURL(/\/dashboard/, { timeout: 15_000 })
  })
})
