import { expect, type APIRequestContext, type Page } from '@playwright/test'
import { execSync } from 'child_process'
import { projectRoot, testConfig, resolveMintTokenScript } from './config'

export type TestUser = {
  name: string
  email: string
  password: string
}

export function uniqueUser(prefix = 'e2e'): TestUser {
  const id = crypto.randomUUID()

  return {
    name: `E2E User ${id.slice(0, 8)}`,
    email: `${prefix}-${id}@${testConfig.testEmailDomain}`,
    password: 'StrongPass123!',
  }
}

/**
 * Register a user and complete email verification when your app uses a pending flow.
 * Falls through silently when registration returns a user directly (legacy flow).
 */
export async function registerUser(request: APIRequestContext, user: TestUser): Promise<void> {
  const response = await request.post('/api/v1/auth/register', {
    data: {
      name: user.name,
      email: user.email,
      password: user.password,
      password_confirmation: user.password,
      timezone: 'UTC',
      job_title: 'QA Engineer',
    },
  })

  expect(response.status()).toBe(201)
  const body = await response.json()
  const pendingToken = body.data?.pending_token

  if (!pendingToken) {
    return
  }

  await request.post('/api/v1/auth/pending/send-code', {
    data: { pending_token: pendingToken },
  })

  const model = testConfig.pendingRegistrationModel
  const code = execSync(
    `php artisan tinker --execute="echo ${model}::where('email','${user.email}')->value('verification_code');"`,
    { cwd: projectRoot(), encoding: 'utf-8' },
  ).trim()

  const verifyRes = await request.post('/api/v1/auth/pending/verify', {
    data: { pending_token: pendingToken, code },
  })
  expect(verifyRes.status()).toBe(200)
}

export async function loginViaUi(page: Page, user: TestUser): Promise<void> {
  await page.goto('/login')
  await page.getByLabel('Email Address').fill(user.email)
  await page.locator('[data-testid="login-password"]').fill(user.password)
  await page.getByRole('button', { name: 'Sign In' }).click()
  await expect(page).toHaveURL(/\/dashboard$/)
}

export type MintedToken = { token: string; userId: string; email?: string }

/** Fast auth for API-level E2E — uses the same adapter as curl API tests. */
export function mintToken(email?: string, admin = false): MintedToken {
  const script = resolveMintTokenScript()
  const args = [
    email ? `--email=${email}` : '',
    admin ? '--admin' : '',
    '--json',
  ].filter(Boolean)

  const output = execSync(`php ${script} ${args.join(' ')}`, {
    cwd: projectRoot(),
    encoding: 'utf-8',
    timeout: 15_000,
    env: { ...process.env, PROJECT_ROOT: projectRoot() },
  }).trim()

  return JSON.parse(output) as MintedToken
}
