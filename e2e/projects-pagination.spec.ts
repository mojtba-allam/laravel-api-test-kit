import { test, expect } from '@playwright/test'
import {
  setupAuthenticatedPage,
  createWorkspace,
  createProject,
} from './support/helpers'

/**
 * Projects Page Pagination E2E Tests
 *
 * Verifies:
 * - Pagination controls appear when there are more projects than per_page
 * - Next/Prev buttons navigate between pages
 * - Page number buttons work
 * - Pagination info text shows correct totals
 * - Pagination is hidden when only one page of results
 */

test.describe('Projects Page Pagination', () => {
  test('pagination is hidden when projects fit on one page', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)

    // Create only 2 projects (fewer than per_page=12)
    await createProject(request, token, workspace.id, 'Project Alpha')
    await createProject(request, token, workspace.id, 'Project Beta')

    await page.goto('/projects')
    await page.waitForSelector('[data-testid="projects-page"]')
    await page.waitForSelector('[data-testid="projects-grid"]')

    // Pagination should NOT be visible
    await expect(page.locator('[data-testid="projects-pagination"]')).not.toBeVisible()
  })

  test('pagination appears when projects exceed per_page and buttons work', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)

    // Create 14 projects (more than per_page=12)
    for (let i = 1; i <= 14; i++) {
      await createProject(request, token, workspace.id, `Pagination Project ${i.toString().padStart(2, '0')}`)
    }

    await page.goto('/projects')
    await page.waitForSelector('[data-testid="projects-page"]')
    await page.waitForSelector('[data-testid="projects-grid"]')

    // Pagination should be visible
    await expect(page.locator('[data-testid="projects-pagination"]')).toBeVisible()

    // Should show page info
    const info = page.locator('[data-testid="pagination-info"]')
    await expect(info).toBeVisible()
    await expect(info).toContainText('Page 1 of 2')
    await expect(info).toContainText('14 projects')

    // Page 1 button should be active (primary appearance)
    await expect(page.locator('[data-testid="pagination-page-1"]')).toBeVisible()
    await expect(page.locator('[data-testid="pagination-page-2"]')).toBeVisible()

    // Prev should be disabled, Next should be enabled
    await expect(page.locator('[data-testid="pagination-prev"]')).toBeDisabled()
    await expect(page.locator('[data-testid="pagination-next"]')).not.toBeDisabled()

    // Click Next
    await page.locator('[data-testid="pagination-next"]').click()

    // Should now be on page 2
    await expect(page.locator('[data-testid="pagination-info"]')).toContainText('Page 2 of 2')

    // Prev should be enabled, Next should be disabled
    await expect(page.locator('[data-testid="pagination-prev"]')).not.toBeDisabled()
    await expect(page.locator('[data-testid="pagination-next"]')).toBeDisabled()

    // Click Prev to go back
    await page.locator('[data-testid="pagination-prev"]').click()
    await expect(page.locator('[data-testid="pagination-info"]')).toContainText('Page 1 of 2')
  })

  test('page number buttons navigate directly', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)

    for (let i = 1; i <= 14; i++) {
      await createProject(request, token, workspace.id, `Direct Nav Project ${i}`)
    }

    await page.goto('/projects')
    await page.waitForSelector('[data-testid="projects-grid"]')

    // Click page 2 directly
    await page.locator('[data-testid="pagination-page-2"]').click()
    await expect(page.locator('[data-testid="pagination-info"]')).toContainText('Page 2 of 2')

    // Click page 1 directly
    await page.locator('[data-testid="pagination-page-1"]').click()
    await expect(page.locator('[data-testid="pagination-info"]')).toContainText('Page 1 of 2')
  })

  test('first and last buttons work', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)

    for (let i = 1; i <= 14; i++) {
      await createProject(request, token, workspace.id, `FL Project ${i}`)
    }

    await page.goto('/projects')
    await page.waitForSelector('[data-testid="projects-grid"]')

    // First should be disabled on page 1
    await expect(page.locator('[data-testid="pagination-first"]')).toBeDisabled()

    // Go to last page
    await page.locator('[data-testid="pagination-last"]').click()
    await expect(page.locator('[data-testid="pagination-info"]')).toContainText('Page 2 of 2')

    // Last should be disabled on last page
    await expect(page.locator('[data-testid="pagination-last"]')).toBeDisabled()

    // Go back to first
    await page.locator('[data-testid="pagination-first"]').click()
    await expect(page.locator('[data-testid="pagination-info"]')).toContainText('Page 1 of 2')
  })
})
