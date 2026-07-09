import { test, expect } from '@playwright/test'

/**
 * Social Authentication E2E Tests
 *
 * Verifies that the Google and GitHub OAuth buttons render on Login and Register
 * pages and correctly initiate the OAuth flow (redirect to provider).
 * Since actual OAuth requires real credentials and provider interaction,
 * we test the UI elements, navigation, and the callback handling page.
 */

test.describe('Social Authentication - Login Page', () => {
  test('renders social login buttons on login page', async ({ page }) => {
    await page.goto('/login')

    await expect(page.locator('[data-testid="social-login-buttons"]')).toBeVisible()
    await expect(page.locator('[data-testid="social-login-google"]')).toBeVisible()
    await expect(page.locator('[data-testid="social-login-github"]')).toBeVisible()
  })

  test('Google button has correct label', async ({ page }) => {
    await page.goto('/login')

    const googleBtn = page.locator('[data-testid="social-login-google"]')
    await expect(googleBtn).toContainText('Sign in with Google')
    await expect(googleBtn).toHaveAttribute('aria-label', 'Sign in with Google')
  })

  test('GitHub button has correct label', async ({ page }) => {
    await page.goto('/login')

    const githubBtn = page.locator('[data-testid="social-login-github"]')
    await expect(githubBtn).toContainText('Sign in with GitHub')
    await expect(githubBtn).toHaveAttribute('aria-label', 'Sign in with GitHub')
  })

  test('social buttons appear before the email form', async ({ page }) => {
    await page.goto('/login')

    // Social buttons should be above the login form
    const socialButtons = page.locator('[data-testid="social-login-buttons"]')
    const loginForm = page.locator('[data-testid="login-form"]')

    const socialBox = await socialButtons.boundingBox()
    const formBox = await loginForm.boundingBox()

    expect(socialBox).not.toBeNull()
    expect(formBox).not.toBeNull()
    expect(socialBox!.y).toBeLessThan(formBox!.y)
  })

  test('divider "or" separator is visible', async ({ page }) => {
    await page.goto('/login')

    // The "or" separator between social and email login
    const orText = page.locator('[data-testid="social-login-buttons"]').locator('text=or')
    await expect(orText).toBeVisible()
  })

  test('Google button click makes API call for redirect URL', async ({ page }) => {
    // Mock the redirect API endpoint to avoid rate limiting
    let apiCalled = false
    await page.route('**/api/v1/auth/social/google/redirect', async (route) => {
      apiCalled = true
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          data: { redirect_url: 'https://accounts.google.com/o/oauth2/auth?client_id=test' },
        }),
      })
    })

    // Block external navigation so page doesn't unload
    await page.route('**/accounts.google.com/**', (route) => route.abort())

    await page.goto('/login')
    await page.locator('[data-testid="social-login-google"]').click()

    // Wait for the API call to complete
    await page.waitForTimeout(1000)

    expect(apiCalled).toBe(true)
  })

  test('GitHub button click makes API call for redirect URL', async ({ page }) => {
    // Mock the redirect API endpoint to avoid rate limiting
    let apiCalled = false
    await page.route('**/api/v1/auth/social/github/redirect', async (route) => {
      apiCalled = true
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          data: { redirect_url: 'https://github.com/login/oauth/authorize?client_id=test' },
        }),
      })
    })

    // Block external navigation
    await page.route('**/github.com/**', (route) => route.abort())

    await page.goto('/login')
    await page.locator('[data-testid="social-login-github"]').click()

    // Wait for the API call to complete
    await page.waitForTimeout(1000)

    expect(apiCalled).toBe(true)
  })

  test('buttons are disabled while loading', async ({ page }) => {
    await page.goto('/login')

    // Block the API response to keep button in loading state
    await page.route('**/auth/social/google/redirect', async (route) => {
      await new Promise((r) => setTimeout(r, 2000))
      await route.continue()
    })

    await page.locator('[data-testid="social-login-google"]').click()

    // Both buttons should be disabled while one is loading
    await expect(page.locator('[data-testid="social-login-google"]')).toBeDisabled()
    await expect(page.locator('[data-testid="social-login-github"]')).toBeDisabled()
  })
})

test.describe('Social Authentication - Register Page', () => {
  test('renders social signup buttons on register page', async ({ page }) => {
    await page.goto('/register')

    await expect(page.locator('[data-testid="social-login-buttons"]')).toBeVisible()
    await expect(page.locator('[data-testid="social-login-google"]')).toBeVisible()
    await expect(page.locator('[data-testid="social-login-github"]')).toBeVisible()
  })

  test('Google button has "Sign up" label on register page', async ({ page }) => {
    await page.goto('/register')

    const googleBtn = page.locator('[data-testid="social-login-google"]')
    await expect(googleBtn).toContainText('Sign up with Google')
    await expect(googleBtn).toHaveAttribute('aria-label', 'Sign up with Google')
  })

  test('GitHub button has "Sign up" label on register page', async ({ page }) => {
    await page.goto('/register')

    const githubBtn = page.locator('[data-testid="social-login-github"]')
    await expect(githubBtn).toContainText('Sign up with GitHub')
    await expect(githubBtn).toHaveAttribute('aria-label', 'Sign up with GitHub')
  })

  test('social buttons appear before the register form', async ({ page }) => {
    await page.goto('/register')

    const socialButtons = page.locator('[data-testid="social-login-buttons"]')
    const registerForm = page.locator('[data-testid="register-form"]')

    const socialBox = await socialButtons.boundingBox()
    const formBox = await registerForm.boundingBox()

    expect(socialBox).not.toBeNull()
    expect(formBox).not.toBeNull()
    expect(socialBox!.y).toBeLessThan(formBox!.y)
  })
})

test.describe('Social Authentication - Callback Page', () => {
  test('callback page renders loading state with token', async ({ page }) => {
    // Mock the /auth/me endpoint so completeSocialAuth succeeds
    await page.route('**/api/v1/auth/me', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          data: {
            id: 'test-uuid',
            name: 'Test User',
            email: 'test@example.com',
            is_active: true,
            email_verified_at: '2026-01-01T00:00:00Z',
          },
        }),
      })
    })

    await page.goto('/auth/social/callback?token=test-token-123&is_new_user=1')

    // Should show loading or redirect to dashboard
    // If token is valid, it should eventually navigate to /dashboard
    await expect(page).toHaveURL(/\/dashboard/, { timeout: 10000 })
  })

  test('callback page shows error when no token provided', async ({ page }) => {
    await page.goto('/auth/social/callback')

    await expect(page.locator('[data-testid="social-auth-error"]')).toBeVisible()
    await expect(page.locator('[data-testid="social-auth-error"]')).toContainText('No authentication token received')
  })

  test('callback page shows error from provider', async ({ page }) => {
    await page.goto('/auth/social/callback?error=Your+account+has+been+deactivated.')

    await expect(page.locator('[data-testid="social-auth-error"]')).toBeVisible()
    await expect(page.locator('[data-testid="social-auth-error"]')).toContainText('deactivated')
  })

  test('callback page redirects to login on error after delay', async ({ page }) => {
    await page.goto('/auth/social/callback?error=Something+went+wrong')

    await expect(page.locator('[data-testid="social-auth-error"]')).toBeVisible()
    // Should redirect to /login after ~3 seconds
    await expect(page).toHaveURL(/\/login/, { timeout: 5000 })
  })
})

test.describe('Social Authentication - Accessibility', () => {
  test('social buttons have proper aria labels', async ({ page }) => {
    await page.goto('/login')

    const googleBtn = page.locator('[data-testid="social-login-google"]')
    const githubBtn = page.locator('[data-testid="social-login-github"]')

    await expect(googleBtn).toHaveAttribute('aria-label', 'Sign in with Google')
    await expect(githubBtn).toHaveAttribute('aria-label', 'Sign in with GitHub')
  })

  test('social buttons contain SVG icons with aria-hidden', async ({ page }) => {
    await page.goto('/login')

    const googleSvg = page.locator('[data-testid="social-login-google"] svg')
    const githubSvg = page.locator('[data-testid="social-login-github"] svg')

    await expect(googleSvg).toHaveAttribute('aria-hidden', 'true')
    await expect(githubSvg).toHaveAttribute('aria-hidden', 'true')
  })

  test('divider is aria-hidden from screen readers', async ({ page }) => {
    await page.goto('/login')

    const divider = page.locator('[data-testid="social-login-buttons"] [aria-hidden="true"]').last()
    await expect(divider).toBeVisible()
  })
})
