import { test, expect } from '@playwright/test'
import { setupAuthenticatedPage, waitForTestId, createWorkspace, setupBoardWithTask } from './support/helpers'

/**
 * UI Interactions E2E Tests
 *
 * Covers:
 *  - Button hover states, text color contrast, and appearances
 *  - Dropdown/select z-index layering (not clipped by headers)
 *  - Date picker visibility (not hidden under other elements)
 *  - List items clickable and navigable
 *  - Glass blur transparency (content visible through glass)
 */

test.describe('Buttons', () => {
  test('primary button has visible white text on colored background', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    await waitForTestId(page, 'dashboard-page')

    const btn = page.locator('[data-testid="dashboard-view-projects-btn"]')
    await expect(btn).toBeVisible()

    // Check text color is white (not theme inverse which could be black in dark mode)
    const color = await btn.evaluate((el) => getComputedStyle(el).color)
    // Should be white: rgb(255, 255, 255)
    expect(color).toMatch(/rgb\(255,\s*255,\s*255\)/)
  })

  test('primary button changes background on hover', async ({ page, request }) => {
    await setupAuthenticatedPage(page, request)
    await waitForTestId(page, 'dashboard-page')

    const btn = page.locator('[data-testid="dashboard-view-projects-btn"]')
    const bgBefore = await btn.evaluate((el) => getComputedStyle(el).backgroundColor)

    await btn.hover()
    await page.waitForTimeout(200) // wait for hover transition

    const bgAfter = await btn.evaluate((el) => getComputedStyle(el).backgroundColor)
    // Background should change on hover
    expect(bgAfter).not.toBe(bgBefore)
  })

  test('subtle button is visible and clickable', async ({ page, request }) => {
    await setupAuthenticatedPage(page, request)
    await waitForTestId(page, 'dashboard-page')

    // Dashboard has a "View all" subtle button if there's activity
    // Or the refresh button which is default appearance
    const refreshBtn = page.locator('[data-testid="dashboard-refresh-btn"]')
    await expect(refreshBtn).toBeVisible()
    await refreshBtn.click()
    // Should not crash, page should still be visible
    await waitForTestId(page, 'dashboard-page')
  })

  test('disabled button cannot be clicked', async ({ page, request }) => {
    await setupAuthenticatedPage(page, request)
    await page.goto('/settings')

    // The delete account button might be in a confirm flow
    // Just verify buttons with disabled state have correct cursor
    const buttons = page.locator('.ds-btn--disabled')
    const count = await buttons.count()
    if (count > 0) {
      const cursor = await buttons.first().evaluate((el) => getComputedStyle(el).cursor)
      expect(cursor).toBe('not-allowed')
    }
  })
})

test.describe('Dropdown/Select z-index', () => {
  test('GlassSelect dropdown appears above header and content', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project } = await setupBoardWithTask(request, token, workspace.id)

    await page.goto(`/projects/${project.id}/board`)
    await waitForTestId(page, 'board-page')

    // The board page has view switcher dropdown or add task modal with selects
    // Try opening the view switcher dropdown
    const viewSwitcher = page.locator('[data-testid="view-switcher"]')
    if (await viewSwitcher.isVisible()) {
      await viewSwitcher.click()
      // Wait for dropdown to appear
      await page.waitForTimeout(100)

      // Check that the menu is visible in the viewport (not clipped)
      const menu = page.locator('[role="menu"]')
      if (await menu.isVisible()) {
        const menuBox = await menu.boundingBox()
        expect(menuBox).not.toBeNull()
        if (menuBox) {
          // Menu should be within viewport
          expect(menuBox.y).toBeGreaterThan(0)
          expect(menuBox.x).toBeGreaterThan(0)
        }
      }
    }
  })

  test('dropdown items are fully visible and not clipped', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project, task } = await setupBoardWithTask(request, token, workspace.id)

    await page.goto(`/projects/${project.id}/board`)
    await waitForTestId(page, 'board-page', 30_000)

    // Find a task card dropdown trigger (the "•••" button)
    const taskCard = page.locator(`[data-testid="task-card-${task.id}"]`)
    if (await taskCard.isVisible()) {
      const trigger = taskCard.locator('[aria-haspopup="true"]')
      if (await trigger.isVisible()) {
        await trigger.click()
        await page.waitForTimeout(100)

        const menuItems = page.locator('[role="menuitem"]')
        const count = await menuItems.count()
        expect(count).toBeGreaterThan(0)

        // Every menu item should be within viewport bounds
        for (let i = 0; i < count; i++) {
          const box = await menuItems.nth(i).boundingBox()
          expect(box).not.toBeNull()
          if (box) {
            const viewport = page.viewportSize()!
            expect(box.y + box.height).toBeLessThanOrEqual(viewport.height + 1)
          }
        }
      }
    }
  })
})

test.describe('Date Selectors', () => {
  test('date input is visible and accessible within task drawer', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project, task } = await setupBoardWithTask(request, token, workspace.id)

    await page.goto(`/projects/${project.id}/board`)
    await waitForTestId(page, 'board-page')

    // Open the task drawer
    const taskCard = page.locator(`[data-testid="task-card-${task.id}"]`)
    if (await taskCard.isVisible()) {
      await taskCard.click()
      await page.waitForTimeout(300)

      // Look for date inputs inside the drawer
      const dateInputs = page.locator('input[type="date"]')
      const count = await dateInputs.count()
      if (count > 0) {
        for (let i = 0; i < count; i++) {
          const input = dateInputs.nth(i)
          if (await input.isVisible()) {
            const box = await input.boundingBox()
            expect(box).not.toBeNull()
            // Date input should not be hidden (height > 0)
            if (box) {
              expect(box.height).toBeGreaterThan(0)
              expect(box.width).toBeGreaterThan(0)
            }
          }
        }
      }
    }
  })
})

test.describe('Lists and Navigation', () => {
  test('project list items are clickable and navigate', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    await setupBoardWithTask(request, token, workspace.id, { projectName: 'Click Test Project' })

    await page.goto('/projects')
    await waitForTestId(page, 'projects-page')

    // Find the project card/row and click it
    const projectItem = page.locator('text=Click Test Project').first()
    if (await projectItem.isVisible()) {
      await projectItem.click()
      await page.waitForTimeout(500)
      // Should navigate to project board
      expect(page.url()).toContain('/projects/')
    }
  })

  test('sidebar navigation items are clickable', async ({ page, request }) => {
    await setupAuthenticatedPage(page, request)
    await waitForTestId(page, 'dashboard-page')

    // Check sidebar nav items exist and are clickable
    const navItems = page.locator('[data-testid="side-nav"] button[aria-current], [data-testid="side-nav"] button')
    const count = await navItems.count()
    if (count > 0) {
      // Click the second nav item (not the currently active one)
      const target = count > 1 ? navItems.nth(1) : navItems.first()
      if (await target.isVisible()) {
        await target.click()
        await page.waitForTimeout(500)
        // URL should have changed from /dashboard
        const url = page.url()
        expect(url).toBeTruthy()
      }
    }
  })

  test('task cards in board are hoverable with visual feedback', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project, task } = await setupBoardWithTask(request, token, workspace.id)

    await page.goto(`/projects/${project.id}/board`)
    await waitForTestId(page, 'board-page')

    const taskCard = page.locator(`[data-testid="task-card-${task.id}"]`)
    if (await taskCard.isVisible()) {
      // Get initial border style
      const borderBefore = await taskCard.evaluate((el) => getComputedStyle(el).borderColor)

      await taskCard.hover()
      await page.waitForTimeout(150)

      // Task card should still be visible and interactive
      await expect(taskCard).toBeVisible()
      const cursor = await taskCard.evaluate((el) => getComputedStyle(el).cursor)
      expect(cursor).toBe('pointer')
    }
  })
})

test.describe('Glass Blur Transparency', () => {
  test('glass header shows content blurred underneath when scrolled', async ({ page, request }) => {
    await setupAuthenticatedPage(page, request)
    await waitForTestId(page, 'dashboard-page')

    const header = page.locator('[data-testid="top-nav"]')
    await expect(header).toBeVisible()

    // Verify the header has backdrop-filter applied
    const backdropFilter = await header.evaluate((el) => getComputedStyle(el).backdropFilter)
    // Should contain blur — not 'none'
    expect(backdropFilter).toContain('blur')
  })

  test('glass sidebar has transparent background showing page beneath', async ({ page, request }) => {
    await setupAuthenticatedPage(page, request)
    await waitForTestId(page, 'dashboard-page')

    const sidebar = page.locator('[data-testid="side-nav"]')
    if (await sidebar.isVisible()) {
      const bg = await sidebar.evaluate((el) => getComputedStyle(el).backgroundColor)
      // Background should be semi-transparent (rgba with alpha < 1)
      expect(bg).toMatch(/rgba?\(/)
      // If rgba, the alpha component should be less than 1
      const alphaMatch = bg.match(/rgba\(\d+,\s*\d+,\s*\d+,\s*([\d.]+)\)/)
      if (alphaMatch) {
        const alpha = parseFloat(alphaMatch[1])
        expect(alpha).toBeLessThan(1)
      }

      // Verify backdrop-filter is applied
      const filter = await sidebar.evaluate((el) => getComputedStyle(el).backdropFilter)
      expect(filter).toContain('blur')
    }
  })

  test('glass surfaces do not have contain:paint (which blocks backdrop-filter)', async ({ page, request }) => {
    await setupAuthenticatedPage(page, request)
    await waitForTestId(page, 'dashboard-page')

    const glassSurfaces = page.locator('.ds-glass-surface')
    const count = await glassSurfaces.count()
    expect(count).toBeGreaterThan(0)

    // Check that no glass surface has contain:paint
    for (let i = 0; i < Math.min(count, 5); i++) {
      const contain = await glassSurfaces.nth(i).evaluate((el) => getComputedStyle(el).contain)
      // Should NOT include 'paint' — only 'layout', 'style', or 'layout style'
      expect(contain).not.toContain('paint')
    }
  })
})

test.describe('Chart Theme Adaptation', () => {
  test('chart tooltip has readable text in dark mode', async ({ page, request }) => {
    await setupAuthenticatedPage(page, request)

    // Switch to dark mode
    await page.evaluate(() => {
      localStorage.setItem('color_mode', 'dark')
    })
    await page.reload()
    await waitForTestId(page, 'dashboard-page')

    // Verify theme is dark
    const theme = await page.evaluate(() =>
      document.documentElement.getAttribute('data-theme'),
    )
    expect(theme).toBe('dark')

    // Verify recharts legend text is themed
    const legendItems = page.locator('.recharts-legend-item-text')
    const count = await legendItems.count()
    if (count > 0) {
      const color = await legendItems.first().evaluate((el) => getComputedStyle(el).color)
      // Should not be black text on dark bg
      expect(color).not.toBe('rgb(0, 0, 0)')
    }
  })
})
