import { test, expect } from '@playwright/test'
import {
  setupAuthenticatedPage,
  createWorkspace,
  loginViaApi,
  getMe,
} from './support/helpers'
import { registerUser, uniqueUser } from './support/auth'

/**
 * Standalone Project E2E Tests
 *
 * Covers:
 * 1. Creating a project without a workspace (API)
 * 2. Creating a project without a workspace (UI)
 * 3. Moving a project to a workspace via API
 * 4. Removing a project from a workspace (set workspace_id to null)
 */

test.describe('Standalone Project (no workspace required)', () => {
  test('can create a project without workspace_id via API', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)

    const res = await request.post('/api/v1/projects', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: {
        name: 'Standalone Project',
        description: 'No workspace needed',
        status: 'active',
        priority: 'medium',
        workspace_id: null,
      },
    })
    expect(res.status()).toBe(201)

    const body = await res.json()
    expect(body.data.name).toBe('Standalone Project')
    expect(body.data.workspace_id).toBeNull()
  })

  test('can create a project with a workspace via API', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)

    const res = await request.post('/api/v1/projects', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: {
        name: 'Workspace Project',
        description: 'In a workspace',
        status: 'active',
        priority: 'medium',
        workspace_id: workspace.id,
      },
    })
    expect(res.status()).toBe(201)

    const body = await res.json()
    expect(body.data.workspace_id).toBe(workspace.id)
  })

  test('can move a standalone project to a workspace via API', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)

    // Create standalone project
    const projRes = await request.post('/api/v1/projects', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { name: 'Movable Project', status: 'active', priority: 'medium', workspace_id: null },
    })
    expect(projRes.status()).toBe(201)
    const project = (await projRes.json()).data
    expect(project.workspace_id).toBeNull()

    // Create workspace
    const workspace = await createWorkspace(request, token)

    // Move project to workspace
    const moveRes = await request.put(`/api/v1/projects/${project.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { workspace_id: workspace.id },
    })
    expect(moveRes.status()).toBe(200)
    const moved = (await moveRes.json()).data
    expect(moved.workspace_id).toBe(workspace.id)
  })

  test('can remove a project from workspace (set workspace_id to null)', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)

    // Create project in workspace
    const projRes = await request.post('/api/v1/projects', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { name: 'Remove from WS', status: 'active', priority: 'medium', workspace_id: workspace.id },
    })
    const project = (await projRes.json()).data
    expect(project.workspace_id).toBe(workspace.id)

    // Remove from workspace
    const removeRes = await request.put(`/api/v1/projects/${project.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { workspace_id: null },
    })
    expect(removeRes.status()).toBe(200)
    const removed = (await removeRes.json()).data
    expect(removed.workspace_id).toBeNull()
  })

  test('cannot move project to a workspace the user does not own', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)

    // Create standalone project
    const projRes = await request.post('/api/v1/projects', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { name: 'Blocked Move', status: 'active', priority: 'medium', workspace_id: null },
    })
    const project = (await projRes.json()).data

    // Another user creates a workspace
    const other = uniqueUser()
    await registerUser(request, other)
    const otherToken = await loginViaApi(request, other)
    const otherWs = await createWorkspace(request, otherToken, 'Private WS')

    // Try to move — should be forbidden
    const moveRes = await request.put(`/api/v1/projects/${project.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { workspace_id: otherWs.id },
    })
    expect(moveRes.status()).toBe(403)
  })
})

test.describe('Standalone Project via UI', () => {
  test('can create a project without selecting a workspace in the UI', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)

    await page.goto('/projects')
    await page.waitForSelector('[data-testid="projects-page"]')

    // Click create button
    const createBtn = page.locator('[data-testid="create-project-btn"]')
    await createBtn.click()

    // Fill name only (skip workspace)
    await page.waitForSelector('[data-testid="project-modal"]')
    await page.locator('[data-testid="project-name-input"]').fill('UI Standalone Project')

    // Submit
    await page.locator('[data-testid="project-submit-btn"]').click()

    // Should succeed — project appears in list
    await expect(page.locator('text=UI Standalone Project')).toBeVisible({ timeout: 10000 })
  })
})
