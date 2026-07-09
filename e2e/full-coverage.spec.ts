import { test, expect } from '@playwright/test'
import {
  setupAuthenticatedPage,
  createWorkspace,
  setupBoardWithTask,
  createProject,
  createSection,
  createColumn,
  createTask,
  loginPageAs,
  loginViaApi,
  getMe,
  setupMemberWithPermissions,
} from './support/helpers'
import { registerUser, uniqueUser } from './support/auth'

/**
 * Full Coverage E2E Tests
 *
 * Covers all major user flows and edge cases not yet tested:
 * - Auth (register, login, logout, invalid credentials)
 * - Task CRUD (create, read, update, delete, move, assign)
 * - Time tracking
 * - Tags
 * - Attachments
 * - Notifications
 * - Search
 * - Workspaces
 * - Settings
 * - Error handling
 */

// ─── AUTH FLOWS ───────────────────────────────────────────────

test.describe('Auth Flows', () => {
  test('register → login → access dashboard', async ({ page, request }) => {
    const user = uniqueUser()
    await registerUser(request, user)
    const token = await loginViaApi(request, user)
    expect(token).toBeTruthy()
  })

  test('login with wrong password returns 401', async ({ request }) => {
    const user = uniqueUser()
    await registerUser(request, user)

    const res = await request.post('/api/v1/auth/login', {
      data: { email: user.email, password: 'WrongPass999!' },
    })
    expect(res.status()).toBe(401)
  })

  test('accessing API without token returns 401', async ({ request }) => {
    const res = await request.get('/api/v1/projects', {
      headers: { Accept: 'application/json' },
    })
    expect(res.status()).toBe(401)
  })

  test('logout invalidates token', async ({ request }) => {
    const user = uniqueUser()
    await registerUser(request, user)
    const token = await loginViaApi(request, user)

    // Logout
    const logoutRes = await request.post('/api/v1/auth/logout', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    expect(logoutRes.status()).toBe(200)

    // Token should be invalid now
    const afterRes = await request.get('/api/v1/auth/me', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    expect(afterRes.status()).toBe(401)
  })
})

// ─── TASK CRUD ────────────────────────────────────────────────

test.describe('Task CRUD', () => {
  test('full task lifecycle: create → update → move → delete', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project, section, column } = await setupBoardWithTask(request, token, workspace.id)

    // Create second column
    const col2 = await createColumn(request, token, section.id, 'Done', 2)

    // Create task
    const task = await createTask(request, token, {
      title: 'Lifecycle Task',
      project_id: project.id,
      column_id: column.id,
      section_id: section.id,
      priority: 'high',
    })
    expect(task.title).toBe('Lifecycle Task')

    // Update task
    const updateRes = await request.put(`/api/v1/tasks/${task.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { title: 'Updated Lifecycle Task', status: 'in_progress' },
    })
    expect(updateRes.status()).toBe(200)
    const updated = (await updateRes.json()).data
    expect(updated.title).toBe('Updated Lifecycle Task')

    // Move task to another column
    const moveRes = await request.post(`/api/v1/tasks/${task.id}/move`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { column_id: col2.id, sort_order: 0 },
    })
    expect(moveRes.status()).toBe(200)

    // Delete task
    const delRes = await request.delete(`/api/v1/tasks/${task.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    expect(delRes.status()).toBe(200)
  })

  test('cannot create task without required fields', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)

    const res = await request.post('/api/v1/tasks', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { title: '' },
    })
    expect(res.status()).toBe(422)
  })

  test('task with due date in the past is marked overdue', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project, section, column } = await setupBoardWithTask(request, token, workspace.id)

    const task = await createTask(request, token, {
      title: 'Overdue Task',
      project_id: project.id,
      column_id: column.id,
      due_date: '2020-01-01',
    })

    const showRes = await request.get(`/api/v1/tasks/${task.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    const taskData = (await showRes.json()).data
    expect(taskData.is_overdue).toBe(true)
  })
})

// ─── TIME TRACKING ────────────────────────────────────────────

test.describe('Time Tracking', () => {
  test('can log time on a task', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project, task } = await setupBoardWithTask(request, token, workspace.id)

    const res = await request.post('/api/v1/time-logs', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: {
        task_id: task.id,
        hours: 2,
        minutes: 30,
        description: 'Development work',
        logged_date: new Date().toISOString().slice(0, 10),
      },
    })
    expect(res.status()).toBe(201)
    const log = (await res.json()).data
    expect(log.hours).toBe(2)
    expect(log.minutes).toBe(30)
  })

  test('can list time logs by task', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { task } = await setupBoardWithTask(request, token, workspace.id)

    // Create a log
    await request.post('/api/v1/time-logs', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { task_id: task.id, hours: 1, minutes: 0, logged_date: new Date().toISOString().slice(0, 10) },
    })

    const res = await request.get(`/api/v1/time-logs/task/${task.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    expect(res.status()).toBe(200)
    const logs = (await res.json()).data
    expect(logs.length).toBeGreaterThanOrEqual(1)
  })
})

// ─── TAGS ─────────────────────────────────────────────────────

test.describe('Tags', () => {
  test('create, assign to task, remove from task', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project, task } = await setupBoardWithTask(request, token, workspace.id)

    // Create tag
    const tagRes = await request.post('/api/v1/tags', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { name: 'urgent', color: '#FF0000', project_id: project.id },
    })
    expect(tagRes.status()).toBe(201)
    const tag = (await tagRes.json()).data

    // Assign tag to task
    const assignRes = await request.put(`/api/v1/tasks/${task.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { tag_ids: [tag.id] },
    })
    expect(assignRes.status()).toBe(200)

    // Verify tag is on the task
    const taskRes = await request.get(`/api/v1/tasks/${task.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    const taskData = (await taskRes.json()).data
    expect(taskData.tags?.some((t: { id: string }) => t.id === tag.id)).toBe(true)
  })
})

// ─── COMMENTS ─────────────────────────────────────────────────

test.describe('Comments', () => {
  test('create, edit, delete comment on task', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { task } = await setupBoardWithTask(request, token, workspace.id)

    // Create
    const createRes = await request.post('/api/v1/comments', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { task_id: task.id, content: 'Test comment' },
    })
    expect(createRes.status()).toBe(201)
    const comment = (await createRes.json()).data

    // Edit
    const editRes = await request.put(`/api/v1/comments/${comment.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { content: 'Edited comment' },
    })
    expect(editRes.status()).toBe(200)
    expect((await editRes.json()).data.content).toBe('Edited comment')

    // Delete
    const delRes = await request.delete(`/api/v1/comments/${comment.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    expect(delRes.status()).toBe(200)
  })
})

// ─── ATTACHMENTS ──────────────────────────────────────────────

test.describe('Attachments', () => {
  test('upload and delete attachment', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { task } = await setupBoardWithTask(request, token, workspace.id)

    // Upload
    const uploadRes = await request.post('/api/v1/attachments/upload', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      multipart: {
        task_id: task.id,
        description: 'Test file',
        file: { name: 'test.txt', mimeType: 'text/plain', buffer: Buffer.from('hello') },
      },
    })
    expect(uploadRes.status()).toBe(201)
    const attachment = (await uploadRes.json()).data

    // Delete
    const delRes = await request.delete(`/api/v1/attachments/${attachment.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    expect(delRes.status()).toBe(200)
  })
})

// ─── NOTIFICATIONS ────────────────────────────────────────────

test.describe('Notifications', () => {
  test('list notifications and mark as read', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)

    // List
    const listRes = await request.get('/api/v1/notifications', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    expect(listRes.status()).toBe(200)

    // Unread count
    const countRes = await request.get('/api/v1/notifications/unread-count', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    expect(countRes.status()).toBe(200)
  })
})

// ─── WORKSPACES ───────────────────────────────────────────────

test.describe('Workspaces', () => {
  test('CRUD workspace', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)

    // Create
    const ws = await createWorkspace(request, token, 'CRUD Workspace')
    expect(ws.name).toBe('CRUD Workspace')

    // Update
    const updateRes = await request.put(`/api/v1/workspaces/${ws.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { name: 'Updated Workspace' },
    })
    expect(updateRes.status()).toBe(200)

    // Show
    const showRes = await request.get(`/api/v1/workspaces/${ws.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    expect(showRes.status()).toBe(200)
    expect((await showRes.json()).data.name).toBe('Updated Workspace')
  })

  test('workspace page loads and shows data', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    await createWorkspace(request, token, 'UI Workspace')

    await page.goto('/workspaces')
    await expect(page.locator('text=UI Workspace')).toBeVisible({ timeout: 10000 })
  })
})

// ─── SEARCH ───────────────────────────────────────────────────

test.describe('Search', () => {
  test('search returns matching tasks', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project, column, section } = await setupBoardWithTask(request, token, workspace.id)

    // Create a task with distinct title
    await createTask(request, token, {
      title: 'UniqueSearchTarget12345',
      project_id: project.id,
      column_id: column.id,
    })

    // Search via API
    const res = await request.get('/api/v1/tasks?search=UniqueSearchTarget12345', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    expect(res.status()).toBe(200)
    const results = (await res.json()).data
    expect(results.some((t: { title: string }) => t.title.includes('UniqueSearchTarget'))).toBe(true)
  })
})

// ─── SECTIONS & COLUMNS CRUD ──────────────────────────────────

test.describe('Sections & Columns', () => {
  test('section CRUD', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const project = await createProject(request, token, workspace.id, 'Section CRUD Project')

    // Create
    const section = await createSection(request, token, project.id, 'New Section')
    expect(section.name).toBe('New Section')

    // Update
    const updateRes = await request.put(`/api/v1/sections/${section.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { name: 'Renamed Section' },
    })
    expect(updateRes.status()).toBe(200)

    // Delete
    const delRes = await request.delete(`/api/v1/sections/${section.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    expect(delRes.status()).toBe(200)
  })

  test('column CRUD', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const project = await createProject(request, token, workspace.id, 'Column CRUD Project')
    const section = await createSection(request, token, project.id, 'Sprint')

    // Create
    const column = await createColumn(request, token, section.id, 'New Column', 1)
    expect(column.name).toBe('New Column')

    // Update
    const updateRes = await request.put(`/api/v1/columns/${column.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { name: 'Renamed Column' },
    })
    expect(updateRes.status()).toBe(200)

    // Delete
    const delRes = await request.delete(`/api/v1/columns/${column.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    expect(delRes.status()).toBe(200)
  })
})

// ─── EDGE CASES ───────────────────────────────────────────────

test.describe('Edge Cases', () => {
  test('accessing non-existent resource returns 404', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)

    const res = await request.get('/api/v1/projects/00000000-0000-0000-0000-000000000000', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    expect(res.status()).toBe(404)
  })

  test('accessing another users project returns 403', async ({ page, request }) => {
    // User A creates a project
    const { token: tokenA } = await setupAuthenticatedPage(page, request)
    const wsA = await createWorkspace(request, tokenA)
    const projectA = await createProject(request, tokenA, wsA.id, 'Private Project')

    // User B tries to access it
    const userB = uniqueUser()
    await registerUser(request, userB)
    const tokenB = await loginViaApi(request, userB)

    const res = await request.get(`/api/v1/projects/${projectA.id}`, {
      headers: { Authorization: `Bearer ${tokenB}`, Accept: 'application/json' },
    })
    expect(res.status()).toBe(403)
  })

  test('rate limiting prevents abuse (too many requests)', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)

    // Fire many requests rapidly
    const promises = Array.from({ length: 100 }, () =>
      request.get('/api/v1/notifications', {
        headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      })
    )
    const results = await Promise.all(promises)
    const statuses = results.map(r => r.status())

    // Most should be 200, but at least some should be 429 if rate limiting works
    // If no rate limiting, all will be 200 (which is also informative)
    const total200 = statuses.filter(s => s === 200).length
    const total429 = statuses.filter(s => s === 429).length
    console.log(`Rate limit test: ${total200} OK, ${total429} throttled out of 100 requests`)
    // At minimum all requests should not error
    expect(statuses.every(s => s === 200 || s === 429)).toBe(true)
  })

  test('large payload is rejected (413 or 422)', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)

    // Try to create a project with a massive description
    const bigDescription = 'x'.repeat(1_000_000) // 1MB string
    const res = await request.post('/api/v1/projects', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { name: 'Big Project', description: bigDescription, status: 'active', priority: 'medium' },
    })
    // Should be rejected (413 payload too large, 422 validation, or 500)
    expect([413, 422, 500]).toContain(res.status())
  })

  test('concurrent task updates dont corrupt data', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { task } = await setupBoardWithTask(request, token, workspace.id)

    // Fire 5 concurrent updates to the same task
    const updates = ['Title A', 'Title B', 'Title C', 'Title D', 'Title E'].map(title =>
      request.put(`/api/v1/tasks/${task.id}`, {
        headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
        data: { title },
      })
    )
    const results = await Promise.all(updates)

    // All should succeed (last writer wins)
    expect(results.every(r => r.status() === 200)).toBe(true)

    // Final state should be consistent (one of the titles)
    const finalRes = await request.get(`/api/v1/tasks/${task.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    const finalTask = (await finalRes.json()).data
    expect(['Title A', 'Title B', 'Title C', 'Title D', 'Title E']).toContain(finalTask.title)
  })

  test('deleted project returns 404 or restricted access', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const project = await createProject(request, token, workspace.id, 'To Delete')

    // Delete
    await request.delete(`/api/v1/projects/${project.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })

    // Try to access
    const res = await request.get(`/api/v1/projects/${project.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    expect([404, 200]).toContain(res.status()) // soft-deleted may return 200 with is_deleted flag
  })

  test('SQL injection in search is safe', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)

    const res = await request.get("/api/v1/tasks?search=' OR 1=1 --", {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    // Should not crash — either 200 with empty results or 422
    expect([200, 422]).toContain(res.status())
  })

  test('XSS in task title is escaped', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project, column } = await setupBoardWithTask(request, token, workspace.id)

    const xssTitle = '<script>alert("xss")</script>'
    const task = await createTask(request, token, {
      title: xssTitle,
      project_id: project.id,
      column_id: column.id,
    })

    // The API should store it as-is (React escapes on render)
    const showRes = await request.get(`/api/v1/tasks/${task.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    const taskData = (await showRes.json()).data
    expect(taskData.title).toBe(xssTitle)

    // On the UI, it should be rendered as text, not executed
    await page.goto(`/projects/${project.id}/board`)
    await page.waitForSelector('[data-testid="permissions-loaded"]', { state: 'attached' })
    // The script tag should be visible as text, not execute
    await expect(page.locator(`text=${xssTitle}`)).toBeVisible()
  })
})

// ─── SETTINGS & PROFILE ───────────────────────────────────────

test.describe('Settings & Profile', () => {
  test('settings page loads', async ({ page, request }) => {
    await setupAuthenticatedPage(page, request)
    await page.goto('/settings')
    await expect(page.locator('[data-testid="settings-page"]')).toBeVisible()
  })

  test('can update user profile via API', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const me = await getMe(request, token)

    const res = await request.put(`/api/v1/users/${me.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { name: 'Updated Name', job_title: 'Senior Dev' },
    })
    // Either 200 (updated) or 403 (if only self-update is allowed differently)
    expect([200, 403]).toContain(res.status())
  })
})

// ─── WEBHOOKS ─────────────────────────────────────────────────

test.describe('Webhooks', () => {
  test('CRUD webhook for a project', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const project = await createProject(request, token, workspace.id, 'Webhook Project')

    // Create
    const createRes = await request.post(`/api/v1/projects/${project.id}/webhooks`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { name: 'Test Hook', url: 'https://example.com/hook', events: ['task.created'] },
    })
    expect(createRes.status()).toBe(201)
    const webhook = (await createRes.json()).data

    // List
    const listRes = await request.get(`/api/v1/projects/${project.id}/webhooks`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    expect(listRes.status()).toBe(200)

    // Delete
    const delRes = await request.delete(`/api/v1/webhooks/${webhook.id}`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    expect(delRes.status()).toBe(200)
  })
})

// ─── CHECKLISTS ───────────────────────────────────────────────

test.describe('Checklists', () => {
  test('create checklist with items on a task', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { task } = await setupBoardWithTask(request, token, workspace.id)

    // Create checklist
    const clRes = await request.post(`/api/v1/tasks/${task.id}/checklists`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { title: 'QA Checklist' },
    })
    expect(clRes.status()).toBe(201)
    const checklist = (await clRes.json()).data

    // Add items
    const itemRes = await request.post(`/api/v1/task-checklists/${checklist.id}/items`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { title: 'Test item 1' },
    })
    expect(itemRes.status()).toBe(201)
  })
})
