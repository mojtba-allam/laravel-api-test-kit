import { test, expect } from '@playwright/test'
import {
  setupAuthenticatedPage,
  createWorkspace,
  setupBoardWithTask,
} from './support/helpers'

/**
 * UI Performance E2E Tests
 *
 * Measures page load times, navigation speed, and interaction latency.
 * Thresholds:
 *   - Page initial load: < 3000ms
 *   - Navigation between pages: < 2000ms
 *   - Modal open: < 500ms
 *   - API response reflected in UI: < 2000ms
 */

const LOAD_THRESHOLD = 3000
const NAV_THRESHOLD = 2000
const MODAL_THRESHOLD = 500
const INTERACTION_THRESHOLD = 2000

test.describe('Page Load Performance', () => {
  test('Dashboard loads within threshold', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)

    const start = Date.now()
    await page.goto('/dashboard')
    await page.waitForSelector('[data-testid="dashboard-page"]')
    const duration = Date.now() - start

    console.log(`Dashboard load: ${duration}ms`)
    expect(duration).toBeLessThan(LOAD_THRESHOLD)
  })

  test('Projects page loads within threshold', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    // Create a few projects so the page has data
    for (let i = 0; i < 5; i++) {
      await request.post('/api/v1/projects', {
        headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
        data: { name: `Perf Project ${i}`, status: 'active', priority: 'medium', workspace_id: workspace.id },
      })
    }

    const start = Date.now()
    await page.goto('/projects')
    await page.waitForSelector('[data-testid="projects-grid"]')
    const duration = Date.now() - start

    console.log(`Projects page load: ${duration}ms`)
    expect(duration).toBeLessThan(LOAD_THRESHOLD)
  })

  test('Board page loads within threshold', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project } = await setupBoardWithTask(request, token, workspace.id)

    const start = Date.now()
    await page.goto(`/projects/${project.id}/board`)
    await page.waitForSelector('[data-testid="permissions-loaded"]', { state: 'attached' })
    const duration = Date.now() - start

    console.log(`Board page load: ${duration}ms`)
    expect(duration).toBeLessThan(LOAD_THRESHOLD)
  })

  test('Teams page loads within threshold', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)

    const start = Date.now()
    await page.goto('/teams')
    await page.waitForSelector('[data-testid="teams-permissions-loaded"]', { state: 'attached' })
    const duration = Date.now() - start

    console.log(`Teams page load: ${duration}ms`)
    expect(duration).toBeLessThan(LOAD_THRESHOLD)
  })

  test('Notifications page loads within threshold', async ({ page, request }) => {
    await setupAuthenticatedPage(page, request)

    const start = Date.now()
    await page.goto('/notifications')
    await page.waitForSelector('[data-testid="notifications-page"]')
    const duration = Date.now() - start

    console.log(`Notifications page load: ${duration}ms`)
    expect(duration).toBeLessThan(LOAD_THRESHOLD)
  })
})

test.describe('Navigation Performance', () => {
  test('navigating from Projects to Board is fast', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project } = await setupBoardWithTask(request, token, workspace.id)

    await page.goto('/projects')
    await page.waitForSelector('[data-testid="projects-page"]')

    // Navigate to board
    const start = Date.now()
    await page.goto(`/projects/${project.id}/board`)
    await page.waitForSelector('[data-testid="permissions-loaded"]', { state: 'attached' })
    const duration = Date.now() - start

    console.log(`Projects → Board navigation: ${duration}ms`)
    expect(duration).toBeLessThan(NAV_THRESHOLD)
  })
})

test.describe('Interaction Performance', () => {
  test('opening task drawer is fast', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project, task } = await setupBoardWithTask(request, token, workspace.id)

    await page.goto(`/projects/${project.id}/board`)
    await page.waitForSelector('[data-testid="permissions-loaded"]', { state: 'attached' })

    // Click task to open drawer
    const start = Date.now()
    await page.locator(`[data-testid="task-card-${task.id}"]`).click()
    await page.waitForSelector('[data-testid="task-drawer"]')
    const duration = Date.now() - start

    console.log(`Task drawer open: ${duration}ms`)
    expect(duration).toBeLessThan(INTERACTION_THRESHOLD)
  })

  test('opening project create modal is fast', async ({ page, request }) => {
    await setupAuthenticatedPage(page, request)

    await page.goto('/projects')
    await page.waitForSelector('[data-testid="projects-page"]')

    const start = Date.now()
    await page.locator('[data-testid="create-project-btn"]').click()
    await page.waitForSelector('[data-testid="project-modal"]')
    const duration = Date.now() - start

    console.log(`Create project modal open: ${duration}ms`)
    expect(duration).toBeLessThan(MODAL_THRESHOLD)
  })
})

test.describe('Web Vitals (Performance API)', () => {
  test('Board page has acceptable navigation timing', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project } = await setupBoardWithTask(request, token, workspace.id)

    await page.goto(`/projects/${project.id}/board`)
    await page.waitForSelector('[data-testid="permissions-loaded"]', { state: 'attached' })

    // Collect performance metrics
    const metrics = await page.evaluate(() => {
      const nav = performance.getEntriesByType('navigation')[0] as PerformanceNavigationTiming
      const paint = performance.getEntriesByType('paint')
      const fcp = paint.find(e => e.name === 'first-contentful-paint')

      return {
        domContentLoaded: Math.round(nav.domContentLoadedEventEnd - nav.startTime),
        loadComplete: Math.round(nav.loadEventEnd - nav.startTime),
        ttfb: Math.round(nav.responseStart - nav.startTime),
        fcp: fcp ? Math.round(fcp.startTime) : null,
        domInteractive: Math.round(nav.domInteractive - nav.startTime),
        resourceCount: performance.getEntriesByType('resource').length,
        transferSize: performance.getEntriesByType('resource').reduce(
          (sum, r) => sum + ((r as PerformanceResourceTiming).transferSize || 0), 0
        ),
      }
    })

    console.log('=== Board Page Web Vitals ===')
    console.log(`  TTFB: ${metrics.ttfb}ms`)
    console.log(`  FCP: ${metrics.fcp}ms`)
    console.log(`  DOM Interactive: ${metrics.domInteractive}ms`)
    console.log(`  DOM Content Loaded: ${metrics.domContentLoaded}ms`)
    console.log(`  Load Complete: ${metrics.loadComplete}ms`)
    console.log(`  Resources: ${metrics.resourceCount}`)
    console.log(`  Transfer Size: ${(metrics.transferSize / 1024).toFixed(1)}KB`)

    // Assert acceptable values
    expect(metrics.ttfb).toBeLessThan(800)       // TTFB < 800ms
    expect(metrics.domInteractive).toBeLessThan(2000)  // Interactive < 2s
    if (metrics.fcp) {
      expect(metrics.fcp).toBeLessThan(2500)     // FCP < 2.5s
    }
  })
})
