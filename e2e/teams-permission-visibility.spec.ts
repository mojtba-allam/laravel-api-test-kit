import { test, expect } from '@playwright/test'
import {
  setupAuthenticatedPage,
  createWorkspace,
  setupBoardWithTask,
  loginPageAs,
  setupMemberWithPermissions,
} from './support/helpers'

/**
 * Teams Permission Visibility E2E Tests
 *
 * Verifies that the `manage_teams` permission controls visibility of
 * team management buttons (create, edit, delete, toggle, add/remove member).
 * Members WITHOUT the permission can view teams but cannot manage them.
 */

test.describe('Teams Permission Visibility', () => {
  test('owner can see Create Team button', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    await setupBoardWithTask(request, ownerToken, workspace.id)

    await page.goto('/teams')
    await page.waitForSelector('[data-testid="teams-permissions-loaded"]', { state: 'attached' })

    await expect(page.locator('[data-testid="create-team-btn"]')).toBeVisible()
  })

  test('member WITHOUT manage_teams cannot see Create Team button', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const member = await setupMemberWithPermissions(
      request, ownerToken, project.id, ['view_project'],
    )

    await loginPageAs(page, member.token, member.userObj)
    await page.goto('/teams')
    await page.waitForSelector('[data-testid="teams-permissions-loaded"]', { state: 'attached' })

    await expect(page.locator('[data-testid="create-team-btn"]')).not.toBeVisible()
  })

  test('member WITH manage_teams CAN see Create Team button', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const member = await setupMemberWithPermissions(
      request, ownerToken, project.id, ['view_project', 'manage_teams'],
    )

    await loginPageAs(page, member.token, member.userObj)
    await page.goto('/teams')
    await page.waitForSelector('[data-testid="teams-permissions-loaded"]', { state: 'attached' })

    await expect(page.locator('[data-testid="create-team-btn"]')).toBeVisible()
  })

  test('member WITHOUT manage_teams cannot see Edit/Delete/Toggle/AddMember in team detail', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    // Owner creates a team
    const teamRes = await request.post(`/api/v1/projects/${project.id}/teams`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { name: 'Dev Team' },
    })
    expect(teamRes.status()).toBe(201)
    const team = (await teamRes.json()).data

    const member = await setupMemberWithPermissions(
      request, ownerToken, project.id, ['view_project'],
    )

    await loginPageAs(page, member.token, member.userObj)
    await page.goto('/teams')
    await page.waitForSelector('[data-testid="teams-permissions-loaded"]', { state: 'attached' })

    // Click on the team card to open detail panel
    await page.locator(`[data-testid="team-card-${team.id}"]`).click()
    await page.waitForSelector(`[data-testid="team-detail-${team.id}"]`)

    // Management buttons should NOT be visible
    await expect(page.locator(`[data-testid="team-edit-btn-${team.id}"]`)).not.toBeVisible()
    await expect(page.locator(`[data-testid="team-delete-btn-${team.id}"]`)).not.toBeVisible()
    await expect(page.locator(`[data-testid="team-active-toggle-${team.id}"]`)).not.toBeAttached()
    await expect(page.locator(`[data-testid="add-member-btn-${team.id}"]`)).not.toBeVisible()
  })

  test('member WITH manage_teams CAN see Edit/Delete/Toggle/AddMember in team detail', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    // Owner creates a team
    const teamRes = await request.post(`/api/v1/projects/${project.id}/teams`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { name: 'Dev Team' },
    })
    expect(teamRes.status()).toBe(201)
    const team = (await teamRes.json()).data

    const member = await setupMemberWithPermissions(
      request, ownerToken, project.id, ['view_project', 'manage_teams'],
    )

    await loginPageAs(page, member.token, member.userObj)
    await page.goto('/teams')
    await page.waitForSelector('[data-testid="teams-permissions-loaded"]', { state: 'attached' })

    await page.locator(`[data-testid="team-card-${team.id}"]`).click()
    await page.waitForSelector(`[data-testid="team-detail-${team.id}"]`)

    // Management buttons should be visible
    await expect(page.locator(`[data-testid="team-edit-btn-${team.id}"]`)).toBeVisible()
    await expect(page.locator(`[data-testid="team-delete-btn-${team.id}"]`)).toBeVisible()
    // Toggle input is visually hidden (sr-only) but present in DOM when canManageTeams is true
    await expect(page.locator(`[data-testid="team-active-toggle-${team.id}"]`)).toBeAttached()
    await expect(page.locator(`[data-testid="add-member-btn-${team.id}"]`)).toBeVisible()
  })

  test('member WITHOUT manage_teams cannot create team via API', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const member = await setupMemberWithPermissions(
      request, ownerToken, project.id, ['view_project'],
    )

    const res = await request.post(`/api/v1/projects/${project.id}/teams`, {
      headers: { Authorization: `Bearer ${member.token}`, Accept: 'application/json' },
      data: { name: 'Hacked Team' },
    })
    expect(res.status()).toBe(403)
  })

  test('member WITH manage_teams CAN create team via API', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const member = await setupMemberWithPermissions(
      request, ownerToken, project.id, ['view_project', 'manage_teams'],
    )

    const res = await request.post(`/api/v1/projects/${project.id}/teams`, {
      headers: { Authorization: `Bearer ${member.token}`, Accept: 'application/json' },
      data: { name: 'Legit Team' },
    })
    expect(res.status()).toBe(201)
  })

  test('member WITHOUT manage_teams cannot update team via API', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const teamRes = await request.post(`/api/v1/projects/${project.id}/teams`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { name: 'Original Team' },
    })
    const team = (await teamRes.json()).data

    const member = await setupMemberWithPermissions(
      request, ownerToken, project.id, ['view_project'],
    )

    const res = await request.put(`/api/v1/project-teams/${team.id}`, {
      headers: { Authorization: `Bearer ${member.token}`, Accept: 'application/json' },
      data: { name: 'Hacked Name' },
    })
    expect(res.status()).toBe(403)
  })

  test('member WITHOUT manage_teams cannot delete team via API', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const teamRes = await request.post(`/api/v1/projects/${project.id}/teams`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { name: 'Team to Delete' },
    })
    const team = (await teamRes.json()).data

    const member = await setupMemberWithPermissions(
      request, ownerToken, project.id, ['view_project'],
    )

    const res = await request.delete(`/api/v1/project-teams/${team.id}`, {
      headers: { Authorization: `Bearer ${member.token}`, Accept: 'application/json' },
    })
    expect(res.status()).toBe(403)
  })

  test('member WITHOUT manage_teams cannot add member to team via API', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const teamRes = await request.post(`/api/v1/projects/${project.id}/teams`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { name: 'Protected Team' },
    })
    const team = (await teamRes.json()).data

    const member = await setupMemberWithPermissions(
      request, ownerToken, project.id, ['view_project'],
    )

    const res = await request.post(`/api/v1/project-teams/${team.id}/members`, {
      headers: { Authorization: `Bearer ${member.token}`, Accept: 'application/json' },
      data: { user_id: member.userObj.id },
    })
    expect(res.status()).toBe(403)
  })

  test('member WITHOUT manage_teams cannot activate/deactivate team via API', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const teamRes = await request.post(`/api/v1/projects/${project.id}/teams`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { name: 'Toggle Team' },
    })
    const team = (await teamRes.json()).data

    const member = await setupMemberWithPermissions(
      request, ownerToken, project.id, ['view_project'],
    )

    const res = await request.post(`/api/v1/project-teams/${team.id}/deactivate`, {
      headers: { Authorization: `Bearer ${member.token}`, Accept: 'application/json' },
    })
    expect(res.status()).toBe(403)
  })
})
