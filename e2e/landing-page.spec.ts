import { test, expect } from '@playwright/test'

/**
 * Landing Page E2E Tests
 *
 * Verifies the professional landing page renders all sections, the demos
 * mount, and every CTA button routes to login or register.
 */

test.describe('Landing Page', () => {
  test('renders all main sections', async ({ page }) => {
    await page.goto('/')
    await expect(page.locator('[data-testid="home-page"]')).toBeVisible()
    await expect(page.locator('[data-testid="home-nav"]')).toBeVisible()
    await expect(page.locator('[data-testid="home-hero"]')).toBeVisible()
    await expect(page.locator('[data-testid="home-stats"]')).toBeVisible()
    await expect(page.locator('[data-testid="home-demo-graph"]')).toBeVisible()
    await expect(page.locator('[data-testid="home-demo-import"]')).toBeVisible()
    await expect(page.locator('[data-testid="home-demo-charts"]')).toBeVisible()
    await expect(page.locator('[data-testid="home-features"]')).toBeVisible()
    await expect(page.locator('[data-testid="home-solutions"]')).toBeVisible()
    await expect(page.locator('[data-testid="home-cta"]')).toBeVisible()
    await expect(page.locator('[data-testid="home-footer"]')).toBeVisible()
  })

  test('feature cards render', async ({ page }) => {
    await page.goto('/')
    const grid = page.locator('[data-testid="home-features-grid"]')
    await expect(grid).toBeVisible()
    // 6 feature cards
    await expect(page.locator('[data-testid^="feature-card-"]')).toHaveCount(6)
  })

  test('nav Get Started routes to register', async ({ page }) => {
    await page.goto('/')
    await page.locator('[data-testid="home-nav-getstarted"]').click()
    await expect(page).toHaveURL(/\/register$/)
  })

  test('nav Sign In routes to login', async ({ page }) => {
    await page.goto('/')
    await page.locator('[data-testid="home-nav-signin"]').click()
    await expect(page).toHaveURL(/\/login$/)
  })

  test('hero Start Free routes to register', async ({ page }) => {
    await page.goto('/')
    await page.locator('[data-testid="home-cta-start"]').click()
    await expect(page).toHaveURL(/\/register$/)
  })

  test('demo CTAs route to register', async ({ page }) => {
    for (const id of ['demo-graph-cta', 'demo-import-cta', 'demo-charts-cta']) {
      await page.goto('/')
      await page.locator(`[data-testid="${id}"]`).evaluate((el) => el.scrollIntoView({ block: 'center' }))
      await page.locator(`[data-testid="${id}"]`).click({ force: true })
      await expect(page).toHaveURL(/\/register$/)
    }
  })

  test('solution card CTAs route to register', async ({ page }) => {
    await page.goto('/')
    await page.locator('[data-testid="solution-cta-0"]').evaluate((el) => el.scrollIntoView({ block: 'center' }))
    await page.locator('[data-testid="solution-cta-0"]').click({ force: true })
    await expect(page).toHaveURL(/\/register$/)
  })

  test('final CTA buttons route correctly', async ({ page }) => {
    await page.goto('/')
    await page.locator('[data-testid="home-cta-register"]').evaluate((el) => el.scrollIntoView({ block: 'center' }))
    await page.locator('[data-testid="home-cta-register"]').click({ force: true })
    await expect(page).toHaveURL(/\/register$/)

    await page.goto('/')
    await page.locator('[data-testid="home-cta-login"]').evaluate((el) => el.scrollIntoView({ block: 'center' }))
    await page.locator('[data-testid="home-cta-login"]').click({ force: true })
    await expect(page).toHaveURL(/\/login$/)
  })

  test('theme toggle works on landing page', async ({ page }) => {
    await page.goto('/')
    const before = await page.evaluate(() => document.documentElement.getAttribute('data-theme'))
    await page.locator('[data-testid="home-nav"] [data-testid="theme-toggle-btn"]').click()
    await page.waitForTimeout(300)
    const after = await page.evaluate(() => document.documentElement.getAttribute('data-theme'))
    expect(after).not.toBe(before)
  })

  test('no empty href buttons — all CTAs have a destination', async ({ page }) => {
    await page.goto('/')
    // Collect all anchor links in the page
    const hrefs = await page.locator('a').evaluateAll((els) =>
      els.map((el) => (el as HTMLAnchorElement).getAttribute('href')),
    )
    for (const href of hrefs) {
      // No empty or placeholder hrefs
      expect(href).toBeTruthy()
      expect(href).not.toBe('#')
    }
  })

  test('feature cards use SVG icons, not emoji', async ({ page }) => {
    await page.goto('/')
    const grid = page.locator('[data-testid="home-features-grid"]')
    await expect(grid).toBeVisible()
    // Each feature card should contain an <svg> icon
    const svgCount = await grid.locator('svg').count()
    expect(svgCount).toBeGreaterThanOrEqual(6)
    // The grid text should not contain common emoji
    const text = await grid.innerText()
    expect(text).not.toMatch(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]/u)
  })

  test('interactive mockup switches board views', async ({ page }) => {
    await page.goto('/')
    await expect(page.locator('[data-testid="interactive-mockup"]')).toBeVisible()
    // Board page is default; kanban shown
    await expect(page.locator('[data-testid="mock-kanban"]')).toBeVisible()
    // Switch to List using the real view switcher
    await page.locator('[data-testid="interactive-mockup"] [data-testid="view-tab-list"]').click()
    await expect(page.locator('[data-testid="interactive-mockup"] [data-testid="list-view"]')).toBeVisible()
  })

  test('interactive mockup sidebar switches pages', async ({ page }) => {
    await page.goto('/')
    await page.locator('[data-testid="mock-nav-dashboard"]').click({ force: true })
    await expect(page.locator('[data-testid="mock-dashboard"]')).toBeVisible()
    await page.locator('[data-testid="mock-nav-analytics"]').click({ force: true })
    await expect(page.locator('[data-testid="mock-analytics"]')).toBeVisible()
    await page.locator('[data-testid="mock-nav-time"]').click({ force: true })
    await expect(page.locator('[data-testid="mock-time"]')).toBeVisible()
    await page.locator('[data-testid="mock-nav-teams"]').click({ force: true })
    await expect(page.locator('[data-testid="mock-teams"]')).toBeVisible()
    await page.locator('[data-testid="mock-nav-board"]').click({ force: true })
    await expect(page.locator('[data-testid="mock-kanban"]')).toBeVisible()
  })

  test('interactive mockup task click routes to register', async ({ page }) => {
    await page.goto('/')
    await page.locator('[data-testid="mock-task-t1"]').click()
    await expect(page).toHaveURL(/\/register$/)
  })

  test('responsive: mobile viewport renders sections', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 })
    await page.goto('/')
    await expect(page.locator('[data-testid="home-hero"]')).toBeVisible()
    await expect(page.locator('[data-testid="home-features"]')).toBeVisible()
  })
})
