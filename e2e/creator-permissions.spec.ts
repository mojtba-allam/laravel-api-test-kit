import { test, expect } from '@playwright/test'
import {
  setupAuthenticatedPage,
  createWorkspace,
  setupBoardWithTask,
  openBoardProjectActionsMenu,
  openBoardSectionActionsMenu,
  clickBoardProjectMenuItem,
} from './support/helpers'

/**
 * Project Creator Permissions E2E Tests
 *
 * Verifies:
 * 1. The project creator always gets all 36 permissions
 * 2. The "Save Permissions" button syncs all permissions in one request
 * 3. The "Select All" / "Deselect All" buttons work
 */

const ALL_36_PERMISSIONS = [
  'view_project', 'edit_project', 'delete_project',
  'manage_members', 'manage_roles',
  'view_reports', 'view_activity_log', 'export_data',
  'create_section', 'edit_section', 'delete_section',
  'create_column', 'edit_column', 'delete_column', 'reorder_column',
  'create_task', 'edit_task', 'delete_task', 'assign_task', 'move_task',
  'create_comment', 'edit_comment', 'delete_comment',
  'upload_attachment', 'delete_attachment',
  'create_tag', 'edit_tag', 'delete_tag',
  'upload_project_doc', 'delete_project_doc',
  'log_time', 'view_timelogs',
  'manage_teams', 'manage_custom_fields', 'manage_webhooks', 'manage_automation',
]

test.describe('Project Creator has all 36 permissions', () => {
  test('my-permissions API returns all 36 permissions for project creator', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project } = await setupBoardWithTask(request, token, workspace.id)

    const res = await request.get(`/api/v1/projects/${project.id}/my-permissions`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    expect(res.status()).toBe(200)

    const body = await res.json()
    const permissions: string[] = body.data.permissions

    // Should be project admin
    expect(body.data.is_project_admin).toBe(true)

    // Should have all 36 permissions
    expect(permissions.length).toBe(36)
    for (const perm of ALL_36_PERMISSIONS) {
      expect(permissions).toContain(perm)
    }
  })

  test('creator sees all board actions (all 36 permissions active)', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, token)
    const { project, section, column } = await setupBoardWithTask(request, token, workspace.id)

    await page.goto(`/projects/${project.id}/board`)
    await page.waitForSelector('[data-testid="permissions-loaded"]', { state: 'attached' })

    // All board-level buttons should be visible for creator
    await openBoardProjectActionsMenu(page)
    await expect(page.locator('[data-testid="board-add-section-btn"]')).toBeVisible()
    await expect(page.locator('[data-testid="board-import-section-btn"]')).toBeVisible()
    await expect(page.locator('[data-testid="board-export-project-btn"]')).toBeVisible()
    await expect(page.locator('[data-testid="board-project-settings-btn"]')).toBeVisible()
    await openBoardSectionActionsMenu(page, section.id)
    await expect(page.locator(`[data-testid="section-add-column-btn-${section.id}"]`)).toBeVisible()
    await expect(page.locator(`[data-testid="section-delete-btn-${section.id}"]`)).toBeVisible()
    await expect(page.locator(`[data-testid="column-add-task-btn-${column.id}"]`)).toBeVisible()
  })
})

test.describe('Permissions bulk sync (Save All button)', () => {
  test('can sync all permissions in one request via API', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    // Add a member with no permissions
    const { setupMemberWithPermissions } = await import('./support/helpers')
    const member = await setupMemberWithPermissions(
      request, ownerToken, project.id, ['view_project'],
    )

    // Verify member has only 1 permission
    const beforeRes = await request.get(
      `/api/v1/projects/${project.id}/members/${member.membership.member_id}/permissions`,
      { headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' } },
    )
    const before = (await beforeRes.json()).data.permissions
    expect(before).toEqual(['view_project'])

    // Sync ALL 36 permissions in one request
    const syncRes = await request.put(
      `/api/v1/projects/${project.id}/members/${member.membership.member_id}/permissions`,
      {
        headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
        data: { permissions: ALL_36_PERMISSIONS },
      },
    )
    expect(syncRes.status()).toBe(200)

    // Verify member now has all 36
    const afterRes = await request.get(
      `/api/v1/projects/${project.id}/members/${member.membership.member_id}/permissions`,
      { headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' } },
    )
    const after = (await afterRes.json()).data.permissions
    expect(after.length).toBe(36)
    for (const perm of ALL_36_PERMISSIONS) {
      expect(after).toContain(perm)
    }
  })

  test('can deselect all permissions in one request via API', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const { setupMemberWithPermissions } = await import('./support/helpers')
    const member = await setupMemberWithPermissions(
      request, ownerToken, project.id, ALL_36_PERMISSIONS,
    )

    // Sync to empty
    const syncRes = await request.put(
      `/api/v1/projects/${project.id}/members/${member.membership.member_id}/permissions`,
      {
        headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
        data: { permissions: [] },
      },
    )
    expect(syncRes.status()).toBe(200)

    const afterRes = await request.get(
      `/api/v1/projects/${project.id}/members/${member.membership.member_id}/permissions`,
      { headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' } },
    )
    const after = (await afterRes.json()).data.permissions
    expect(after.length).toBe(0)
  })

  test('Save Permissions button works in the UI', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const { setupMemberWithPermissions } = await import('./support/helpers')
    const member = await setupMemberWithPermissions(
      request, ownerToken, project.id, ['view_project'],
    )

    // Navigate to project settings
    await page.goto(`/projects/${project.id}/board`)
    await page.waitForSelector('[data-testid="permissions-loaded"]', { state: 'attached' })
    await clickBoardProjectMenuItem(page, 'board-project-settings-btn')
    await page.waitForSelector('[data-testid="project-settings-modal"]')

    // Go to Members tab
    await page.locator('[data-testid="settings-tab-members"]').click()
    await page.waitForSelector('[data-testid="settings-members"]')

    // Open the member's permissions panel
    await page.locator(`[data-testid="member-perms-btn-${member.userObj.id}"]`).click()
    await page.waitForSelector(`[data-testid="member-perms-popup-${member.userObj.id}"]`)

    // Click "Select All"
    await page.locator(`[data-testid="perms-select-all-${member.userObj.id}"]`).click()

    // Click "Save Permissions"
    await page.locator(`[data-testid="perms-save-btn-${member.userObj.id}"]`).click()

    // Wait for save to complete (button becomes disabled again)
    await expect(page.locator(`[data-testid="perms-save-btn-${member.userObj.id}"]`)).toBeDisabled({ timeout: 10000 })

    // Verify via API that all permissions were saved
    const afterRes = await request.get(
      `/api/v1/projects/${project.id}/members/${member.membership.member_id}/permissions`,
      { headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' } },
    )
    const after = (await afterRes.json()).data.permissions
    expect(after.length).toBe(36)
  })
})
