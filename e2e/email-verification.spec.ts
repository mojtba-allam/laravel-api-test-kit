import { test, expect } from '@playwright/test'
import { execSync } from 'child_process'
import { projectRoot, testConfig } from './support/config'

const BASE_URL = process.env.PLAYWRIGHT_BASE_URL || 'http://127.0.0.1:8000'

function readVerificationCode(email: string): string {
  const model = testConfig.pendingRegistrationModel
  return execSync(
    `php artisan tinker --execute="echo ${model}::where('email','${email}')->value('verification_code');"`,
    { cwd: projectRoot(), encoding: 'utf-8' },
  ).trim()
}

test.describe('Email Verification Flow', () => {
  test('registration does NOT create a user until verification', async ({ request }) => {
    const email = `e2e-pending-${Date.now()}@test.example.com`
    const password = 'StrongPass123!'

    // 1. Register
    const regResponse = await request.post(`${BASE_URL}/api/v1/auth/register`, {
      data: {
        name: 'E2E Pending Test',
        email,
        password,
        password_confirmation: password,
        timezone: 'UTC',
      },
    })
    expect(regResponse.status()).toBe(201)
    const regBody = await regResponse.json()
    const pendingToken = regBody.data?.pending_token
    expect(pendingToken).toBeTruthy()
    expect(regBody.data?.email).toBe(email)

    // 2. No user should exist — no auth token was given
    expect(regBody.data?.token).toBeUndefined()
    expect(regBody.data?.user).toBeUndefined()
  })

  test('unverified pending registration cannot access protected pages', async ({ request }) => {
    const email = `e2e-noauth-${Date.now()}@test.example.com`
    const password = 'StrongPass123!'

    // Register — no auth token is returned
    const regResponse = await request.post(`${BASE_URL}/api/v1/auth/register`, {
      data: {
        name: 'E2E No Auth',
        email,
        password,
        password_confirmation: password,
        timezone: 'UTC',
      },
    })
    expect(regResponse.status()).toBe(201)

    // Without a token, protected endpoints should return 401
    const projectsResponse = await request.get(`${BASE_URL}/api/v1/projects`, {
      headers: { Accept: 'application/json' },
    })
    expect(projectsResponse.status()).toBe(401)
  })

  test('send-code endpoint sends verification email', async ({ request }) => {
    const email = `e2e-sendcode-${Date.now()}@test.example.com`
    const password = 'StrongPass123!'

    const regResponse = await request.post(`${BASE_URL}/api/v1/auth/register`, {
      data: {
        name: 'E2E Send Code',
        email,
        password,
        password_confirmation: password,
        timezone: 'UTC',
      },
    })
    expect(regResponse.status()).toBe(201)
    const pendingToken = (await regResponse.json()).data.pending_token

    // Send code
    const sendResponse = await request.post(`${BASE_URL}/api/v1/auth/pending/send-code`, {
      data: { pending_token: pendingToken },
    })
    expect(sendResponse.status()).toBe(200)
  })

  test('change-email endpoint updates pending registration email', async ({ request }) => {
    const email = `e2e-change-${Date.now()}@test.example.com`
    const newEmail = `e2e-changed-${Date.now()}@test.example.com`
    const password = 'StrongPass123!'

    const regResponse = await request.post(`${BASE_URL}/api/v1/auth/register`, {
      data: {
        name: 'E2E Change Email',
        email,
        password,
        password_confirmation: password,
        timezone: 'UTC',
      },
    })
    expect(regResponse.status()).toBe(201)
    const pendingToken = (await regResponse.json()).data.pending_token

    // Change email
    const changeResponse = await request.post(`${BASE_URL}/api/v1/auth/pending/change-email`, {
      data: { pending_token: pendingToken, email: newEmail },
    })
    expect(changeResponse.status()).toBe(200)
    const changeBody = await changeResponse.json()
    expect(changeBody.data.email).toBe(newEmail)
  })

  test('full verification flow creates user and returns auth token', async ({ request }) => {
    test.skip(!process.env.PROJECT_ROOT && !testConfig.projectRoot, 'Requires local DB access to read verification code')

    const email = `e2e-fullverify-${Date.now()}@test.example.com`
    const password = 'StrongPass123!'

    // 1. Register
    const regResponse = await request.post(`${BASE_URL}/api/v1/auth/register`, {
      data: {
        name: 'E2E Full Verify',
        email,
        password,
        password_confirmation: password,
        timezone: 'UTC',
      },
    })
    expect(regResponse.status()).toBe(201)
    const pendingToken = (await regResponse.json()).data.pending_token

    // 2. Send code
    await request.post(`${BASE_URL}/api/v1/auth/pending/send-code`, {
      data: { pending_token: pendingToken },
    })

    // 3. Get the code from DB
    await new Promise((r) => setTimeout(r, 500))
    const code = readVerificationCode(email)
    expect(code).toMatch(/^\d{6}$/)

    // 4. Verify
    const verifyResponse = await request.post(`${BASE_URL}/api/v1/auth/pending/verify`, {
      data: { pending_token: pendingToken, code },
    })
    expect(verifyResponse.status()).toBe(200)
    const verifyBody = await verifyResponse.json()
    expect(verifyBody.data.user).toBeTruthy()
    expect(verifyBody.data.user.email).toBe(email)
    expect(verifyBody.data.token).toBeTruthy()
    expect(verifyBody.data.user.email_verified_at).toBeTruthy()

    // 5. Authenticated user can access protected routes
    const projectsResponse = await request.get(`${BASE_URL}/api/v1/projects`, {
      headers: { Authorization: `Bearer ${verifyBody.data.token}` },
    })
    expect(projectsResponse.status()).toBe(200)
  })

  test('registration UI redirects to verify-email page without dashboard flash', async ({ page }) => {
    const email = `e2e-ui-${Date.now()}@test.example.com`
    const password = 'StrongPass123!'

    await page.goto('/register')

    await page.locator('[data-testid="register-name"]').fill('E2E UI Test')
    await page.locator('[data-testid="register-email"]').fill(email)
    await page.locator('[data-testid="register-password"]').fill(password)
    await page.locator('[data-testid="register-confirm"]').fill(password)
    await page.locator('[data-testid="register-submit"]').click()

    // Should redirect to verify-email page, NOT dashboard
    await expect(page).toHaveURL(/\/verify-email/, { timeout: 10000 })

    // Verify the page never shows the dashboard
    await expect(page.locator('[data-testid="email-verification-page"]')).toBeVisible()
    await expect(page).not.toHaveURL(/\/dashboard/)
  })

  test('verify-email page shows send code button (email not sent automatically)', async ({ page }) => {
    const email = `e2e-sendbtn-${Date.now()}@test.example.com`
    const password = 'StrongPass123!'

    await page.goto('/register')
    await page.locator('[data-testid="register-name"]').fill('E2E Send Btn')
    await page.locator('[data-testid="register-email"]').fill(email)
    await page.locator('[data-testid="register-password"]').fill(password)
    await page.locator('[data-testid="register-confirm"]').fill(password)
    await page.locator('[data-testid="register-submit"]').click()

    await expect(page).toHaveURL(/\/verify-email/, { timeout: 10000 })

    // Should see "Send Verification Code" button
    await expect(page.locator('[data-testid="send-code-button"]')).toBeVisible()

    // Should NOT see code inputs yet
    await expect(page.locator('[data-testid="code-input-0"]')).not.toBeVisible()

    // Email should be displayed
    await expect(page.getByText(email)).toBeVisible()
  })

  test('verify-email page has change email button', async ({ page }) => {
    const email = `e2e-changeemail-${Date.now()}@test.example.com`
    const password = 'StrongPass123!'

    await page.goto('/register')
    await page.locator('[data-testid="register-name"]').fill('E2E Change Email')
    await page.locator('[data-testid="register-email"]').fill(email)
    await page.locator('[data-testid="register-password"]').fill(password)
    await page.locator('[data-testid="register-confirm"]').fill(password)
    await page.locator('[data-testid="register-submit"]').click()

    await expect(page).toHaveURL(/\/verify-email/, { timeout: 10000 })

    // Should see "Change email address" button
    await expect(page.locator('[data-testid="change-email-button"]')).toBeVisible()

    // Click it
    await page.locator('[data-testid="change-email-button"]').click()

    // Should show email input
    await expect(page.locator('[data-testid="new-email-input"]')).toBeVisible()
    await expect(page.locator('[data-testid="confirm-change-email-button"]')).toBeVisible()
    await expect(page.locator('[data-testid="cancel-change-email-button"]')).toBeVisible()
  })

  test('back link goes to register page, not dashboard', async ({ page }) => {
    const email = `e2e-backlink-${Date.now()}@test.example.com`
    const password = 'StrongPass123!'

    await page.goto('/register')
    await page.locator('[data-testid="register-name"]').fill('E2E Back Link')
    await page.locator('[data-testid="register-email"]').fill(email)
    await page.locator('[data-testid="register-password"]').fill(password)
    await page.locator('[data-testid="register-confirm"]').fill(password)
    await page.locator('[data-testid="register-submit"]').click()

    await expect(page).toHaveURL(/\/verify-email/, { timeout: 10000 })

    // Click back link
    await page.locator('[data-testid="back-to-register-link"]').click()

    // Should go to register, NOT dashboard
    await expect(page).toHaveURL(/\/register/, { timeout: 5000 })
    await expect(page).not.toHaveURL(/\/dashboard/)
  })

  test('accessing verify-email without pending token redirects to register', async ({ page }) => {
    // Make sure localStorage has no pending token
    await page.goto('/register')
    await page.evaluate(() => {
      localStorage.removeItem('pending_token')
      localStorage.removeItem('pending_email')
    })

    await page.goto('/verify-email')

    // Should redirect to register
    await expect(page).toHaveURL(/\/register/, { timeout: 5000 })
  })
})

test.describe('Signup UI Validation', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/register')
  })

  test('shows the registration form with all fields', async ({ page }) => {
    await expect(page.locator('[data-testid="register-form"]')).toBeVisible()
    await expect(page.locator('[data-testid="register-name"]')).toBeVisible()
    await expect(page.locator('[data-testid="register-email"]')).toBeVisible()
    await expect(page.locator('[data-testid="register-password"]')).toBeVisible()
    await expect(page.locator('[data-testid="register-confirm"]')).toBeVisible()
    await expect(page.locator('[data-testid="register-submit"]')).toBeVisible()
  })

  test('shows validation errors for empty submission', async ({ page }) => {
    await page.locator('[data-testid="register-submit"]').click()

    await expect(page.locator('#register-name-error')).toHaveText(/required/i)
    await expect(page.locator('#register-email-error')).toHaveText(/required/i)
    await expect(page.locator('#register-password-error')).toHaveText(/required/i)
    await expect(page).toHaveURL(/\/register/)
  })

  test('rejects invalid email format', async ({ page }) => {
    await page.locator('[data-testid="register-name"]').fill('Test User')
    await page.locator('[data-testid="register-email"]').fill('not-an-email')
    await page.locator('[data-testid="register-password"]').fill('StrongPass123!')
    await page.locator('[data-testid="register-confirm"]').fill('StrongPass123!')
    await page.locator('[data-testid="register-submit"]').click()

    await expect(page.locator('#register-email-error')).toHaveText(/valid email/i)
    await expect(page).toHaveURL(/\/register/)
  })

  test('rejects password shorter than 8 characters', async ({ page }) => {
    await page.locator('[data-testid="register-name"]').fill('Test User')
    await page.locator('[data-testid="register-email"]').fill(`short-${Date.now()}@test.example.com`)
    await page.locator('[data-testid="register-password"]').fill('short')
    await page.locator('[data-testid="register-confirm"]').fill('short')
    await page.locator('[data-testid="register-submit"]').click()

    await expect(page.locator('#register-password-error')).toHaveText(/at least 8 characters/i)
    await expect(page).toHaveURL(/\/register/)
  })

  test('rejects mismatched password confirmation', async ({ page }) => {
    await page.locator('[data-testid="register-name"]').fill('Test User')
    await page.locator('[data-testid="register-email"]').fill(`mismatch-${Date.now()}@test.example.com`)
    await page.locator('[data-testid="register-password"]').fill('StrongPass123!')
    await page.locator('[data-testid="register-confirm"]').fill('DifferentPass123!')
    await page.locator('[data-testid="register-submit"]').click()

    await expect(page.locator('#register-confirm-error')).toHaveText(/do not match/i)
    await expect(page).toHaveURL(/\/register/)
  })

  test('shows password strength indicator', async ({ page }) => {
    await page.locator('[data-testid="register-password"]').fill('weak')
    await expect(page.locator('[data-testid="password-strength-label"]')).toBeVisible()

    await page.locator('[data-testid="register-password"]').fill('StrongPass123!@#')
    await expect(page.locator('[data-testid="password-strength-label"]')).toHaveText(/strong/i)
  })

  test('rejects duplicate email registration', async ({ page, request }) => {
    const email = `dup-${Date.now()}@test.example.com`
    const password = 'StrongPass123!'

    // First registration via API
    const first = await request.post(`${BASE_URL}/api/v1/auth/register`, {
      data: {
        name: 'First User',
        email,
        password,
        password_confirmation: password,
        timezone: 'UTC',
      },
    })
    expect(first.status()).toBe(201)

    // Verify the first user so it occupies the email in the users table
    const pendingToken = (await first.json()).data.pending_token
    await request.post(`${BASE_URL}/api/v1/auth/pending/send-code`, {
      data: { pending_token: pendingToken },
    })
    await new Promise((r) => setTimeout(r, 500))

    const code = readVerificationCode(email)

    await request.post(`${BASE_URL}/api/v1/auth/pending/verify`, {
      data: { pending_token: pendingToken, code },
    })

    // Attempt duplicate registration via UI
    await page.locator('[data-testid="register-name"]').fill('Second User')
    await page.locator('[data-testid="register-email"]').fill(email)
    await page.locator('[data-testid="register-password"]').fill(password)
    await page.locator('[data-testid="register-confirm"]').fill(password)
    await page.locator('[data-testid="register-submit"]').click()

    // Should show an error and stay on register page
    await expect(page.locator('[data-testid="register-error"]')).toBeVisible({ timeout: 10000 })
    await expect(page).toHaveURL(/\/register/)
  })

  test('can navigate to login from register page', async ({ page }) => {
    await page.locator('[data-testid="register-login-link"]').click()
    await expect(page).toHaveURL(/\/login/)
  })

  test('successful signup shows verification page with email', async ({ page }) => {
    const email = `verify-ui-${Date.now()}@test.example.com`
    const password = 'StrongPass123!'

    await page.locator('[data-testid="register-name"]').fill('Verify UI User')
    await page.locator('[data-testid="register-email"]').fill(email)
    await page.locator('[data-testid="register-password"]').fill(password)
    await page.locator('[data-testid="register-confirm"]').fill(password)
    await page.locator('[data-testid="register-submit"]').click()

    // Lands on verify-email page
    await expect(page).toHaveURL(/\/verify-email/, { timeout: 10000 })

    // The verification page shows the registered email
    await expect(page.getByText(email)).toBeVisible({ timeout: 10000 })

    // The send code button is present
    await expect(page.locator('[data-testid="send-code-button"]')).toBeVisible()
  })
})
