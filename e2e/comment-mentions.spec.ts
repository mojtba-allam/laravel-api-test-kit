import { test, expect } from '@playwright/test'
import {
  setupAuthenticatedPage,
  waitForTestId,
  createWorkspace,
  setupBoardWithTask,
  getMe,
  createComment,
} from './support/helpers'

/**
 * Comment @Mention E2E Tests
 *
 * Covers:
 * 1. Self-mention does NOT generate a notification (actor-exclusion by design)
 * 2. Mentions in comments are rendered as clickable links to user profile
 */

test.describe('Comment @Mentions', () => {
  test('self-mention does not produce a notification (actor-exclusion)', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const me = await getMe(request, token)

    // Create a board with a task
    const workspace = await createWorkspace(request, token)
    const { task } = await setupBoardWithTask(request, token, workspace.id)

    // Post a comment mentioning self
    await createComment(request, token, {
      task_id: task.id,
      content: `Hey @${me.name}, reminding myself about this`,
      mentions: [me.id],
    })

    // Wait a moment for async listeners to process
    await page.waitForTimeout(1000)

    // Check notifications — should have zero for this self-mention
    const notifRes = await request.get('/api/v1/notifications', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    expect(notifRes.status()).toBe(200)
    const notifBody = await notifRes.json()
    const notifications = notifBody.data ?? []

    // Filter for comment_mention notifications — should be empty for self-mention
    const mentionNotifs = notifications.filter(
      (n: { type: string }) => n.type === 'comment_mention',
    )
    expect(mentionNotifs.length).toBe(0)
  })

  test('mention in comment is rendered as a clickable link to user profile', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const me = await getMe(request, token)

    // Create a board with a task
    const workspace = await createWorkspace(request, token)
    const { project, task } = await setupBoardWithTask(request, token, workspace.id)

    // Create a comment that mentions self (for simplicity — we control the user)
    await createComment(request, token, {
      task_id: task.id,
      content: `Hey @${me.name} check this task`,
      mentions: [me.id],
    })

    // Navigate to the board and open the task drawer
    await page.goto(`/projects/${project.id}/board`)
    await waitForTestId(page, 'board-page', 15_000)

    // Click the task card to open the drawer
    const taskCard = page.locator(`[data-testid="task-card-${task.id}"]`)
    await expect(taskCard).toBeVisible({ timeout: 10_000 })
    await taskCard.click()

    // Wait for comments section to load
    await waitForTestId(page, 'task-comments', 10_000)

    // The mention should be a clickable link
    const mentionLink = page.locator(`[data-testid="mention-link-${me.id}"]`)
    await expect(mentionLink).toBeVisible({ timeout: 5_000 })

    // Verify it has the correct text
    await expect(mentionLink).toContainText(`@${me.name}`)

    // Verify it has link styling (color is link color, cursor pointer)
    const cursor = await mentionLink.evaluate((el) => getComputedStyle(el).cursor)
    expect(cursor).toBe('pointer')

    // Click the mention link — should navigate to user profile
    await mentionLink.click()
    await page.waitForURL(/\/profile\//, { timeout: 5_000 })
    expect(page.url()).toContain(`/profile/${me.id}`)
  })

  test('mention link shows underline on hover', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const me = await getMe(request, token)

    const workspace = await createWorkspace(request, token)
    const { project, task } = await setupBoardWithTask(request, token, workspace.id)

    await createComment(request, token, {
      task_id: task.id,
      content: `@${me.name} review needed`,
      mentions: [me.id],
    })

    await page.goto(`/projects/${project.id}/board`)
    await waitForTestId(page, 'board-page', 15_000)

    const taskCard = page.locator(`[data-testid="task-card-${task.id}"]`)
    await expect(taskCard).toBeVisible({ timeout: 10_000 })
    await taskCard.click()

    await waitForTestId(page, 'task-comments', 10_000)

    const mentionLink = page.locator(`[data-testid="mention-link-${me.id}"]`)
    await expect(mentionLink).toBeVisible({ timeout: 5_000 })

    // Initially no underline
    const decorBefore = await mentionLink.evaluate((el) => getComputedStyle(el).textDecoration)
    expect(decorBefore).toContain('none')

    // Hover should show underline
    await mentionLink.hover()
    await page.waitForTimeout(150)
    const decorAfter = await mentionLink.evaluate((el) => getComputedStyle(el).textDecoration)
    expect(decorAfter).toContain('underline')
  })
})
