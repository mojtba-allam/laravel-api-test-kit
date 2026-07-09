import { test, expect } from '@playwright/test'
import {
  setupAuthenticatedPage,
  createWorkspace,
  setupBoardWithTask,
  loginPageAs,
  loginViaApi,
  getMe,
} from './support/helpers'
import { registerUser, uniqueUser } from './support/auth'

/**
 * Full Invite Flow E2E Tests (A → B → C)
 *
 * A: Owner sends invite (user is NOT directly added)
 * B: Invitee receives notification about the invite
 * C: Invitee accepts → becomes member / declines → stays out
 *
 * Verifies that:
 * - Sending an invite does NOT directly add the user as a member
 * - The invitee gets a notification
 * - Only after accepting does the user become a member
 */

test.describe('Project Invite: A→B→C full flow', () => {
  test('A: owner invites user → user is NOT added as member yet', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    // Register target user
    const target = uniqueUser()
    await registerUser(request, target)
    const targetToken = await loginViaApi(request, target)
    const targetMe = await getMe(request, targetToken)

    // Owner sends invite via members-overview endpoint
    const inviteRes = await request.post(`/api/v1/projects/${project.id}/members-overview`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { user_id: targetMe.id },
    })
    expect(inviteRes.status()).toBe(201)
    const inviteBody = await inviteRes.json()
    expect(inviteBody.data.status).toBe('pending')

    // Verify user is NOT a project member yet
    const membersRes = await request.get(`/api/v1/projects/${project.id}/members`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
    })
    const members = (await membersRes.json()).data
    const isMember = members.some((m: { id?: string; user_id?: string }) =>
      m.user_id === targetMe.id || m.id === targetMe.id
    )
    expect(isMember).toBe(false)
  })

  test('B: invitee receives a notification about the project invite', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const target = uniqueUser()
    await registerUser(request, target)
    const targetToken = await loginViaApi(request, target)
    const targetMe = await getMe(request, targetToken)

    // Owner sends invite
    await request.post(`/api/v1/projects/${project.id}/invites`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { user_id: targetMe.id, message: 'Join us!' },
    })

    // Check invitee's notifications
    const notifRes = await request.get('/api/v1/notifications', {
      headers: { Authorization: `Bearer ${targetToken}`, Accept: 'application/json' },
    })
    expect(notifRes.status()).toBe(200)
    const notifications = (await notifRes.json()).data
    const inviteNotif = notifications.find((n: { type: string }) =>
      n.type === 'project_invitation'
    )
    expect(inviteNotif).toBeTruthy()
    expect(inviteNotif.data?.message || inviteNotif.message || '').toContain('invited you')
  })

  test('C: invitee accepts → becomes project member', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const target = uniqueUser()
    await registerUser(request, target)
    const targetToken = await loginViaApi(request, target)
    const targetMe = await getMe(request, targetToken)

    // A: Owner sends invite
    const inviteRes = await request.post(`/api/v1/projects/${project.id}/invites`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { user_id: targetMe.id },
    })
    expect(inviteRes.status()).toBe(201)
    const invite = (await inviteRes.json()).data

    // Verify NOT a member
    const beforeRes = await request.get(`/api/v1/projects/${project.id}/members`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
    })
    const beforeMembers = (await beforeRes.json()).data
    expect(beforeMembers.some((m: { user_id?: string }) => m.user_id === targetMe.id)).toBe(false)

    // C: Invitee accepts
    const acceptRes = await request.post(`/api/v1/invites/${invite.id}/accept`, {
      headers: { Authorization: `Bearer ${targetToken}`, Accept: 'application/json' },
    })
    expect(acceptRes.status()).toBe(200)

    // Now IS a member
    const afterRes = await request.get(`/api/v1/projects/${project.id}/members`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
    })
    const afterMembers = (await afterRes.json()).data
    expect(afterMembers.some((m: { user_id?: string; id?: string }) =>
      m.user_id === targetMe.id || m.id === targetMe.id
    )).toBe(true)
  })

  test('C (decline): invitee declines → does NOT become project member', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const target = uniqueUser()
    await registerUser(request, target)
    const targetToken = await loginViaApi(request, target)
    const targetMe = await getMe(request, targetToken)

    // A: Owner sends invite
    const inviteRes = await request.post(`/api/v1/projects/${project.id}/invites`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { user_id: targetMe.id },
    })
    const invite = (await inviteRes.json()).data

    // C: Invitee declines
    const declineRes = await request.post(`/api/v1/invites/${invite.id}/decline`, {
      headers: { Authorization: `Bearer ${targetToken}`, Accept: 'application/json' },
    })
    expect(declineRes.status()).toBe(200)

    // Still NOT a member
    const afterRes = await request.get(`/api/v1/projects/${project.id}/members`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
    })
    const afterMembers = (await afterRes.json()).data
    expect(afterMembers.some((m: { user_id?: string }) => m.user_id === targetMe.id)).toBe(false)
  })
})

test.describe('Team Invite: A→B→C full flow', () => {
  test('A: team manager invites user → user is NOT added as team member yet', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    // Create a team
    const teamRes = await request.post(`/api/v1/projects/${project.id}/teams`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { name: 'Invite Test Team' },
    })
    expect(teamRes.status()).toBe(201)
    const team = (await teamRes.json()).data

    // Register target user
    const target = uniqueUser()
    await registerUser(request, target)
    const targetToken = await loginViaApi(request, target)
    const targetMe = await getMe(request, targetToken)

    // A: Owner adds member (now goes through invite)
    const addRes = await request.post(`/api/v1/project-teams/${team.id}/members`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { user_id: targetMe.id, role: 'member' },
    })
    expect(addRes.status()).toBe(201)
    const addBody = await addRes.json()
    expect(addBody.data.status).toBe('pending')

    // Verify NOT a team member yet
    const membersRes = await request.get(`/api/v1/project-teams/${team.id}/members`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
    })
    const members = (await membersRes.json()).data
    expect(members.some((m: { user_id?: string }) => m.user_id === targetMe.id)).toBe(false)
  })

  test('B: invitee receives notification about team invite', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const teamRes = await request.post(`/api/v1/projects/${project.id}/teams`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { name: 'Notif Test Team' },
    })
    const team = (await teamRes.json()).data

    const target = uniqueUser()
    await registerUser(request, target)
    const targetToken = await loginViaApi(request, target)
    const targetMe = await getMe(request, targetToken)

    // Send team invite
    await request.post(`/api/v1/project-teams/${team.id}/invites`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { user_id: targetMe.id, message: 'Join our team!' },
    })

    // Check notifications
    const notifRes = await request.get('/api/v1/notifications', {
      headers: { Authorization: `Bearer ${targetToken}`, Accept: 'application/json' },
    })
    expect(notifRes.status()).toBe(200)
    const notifications = (await notifRes.json()).data
    const inviteNotif = notifications.find((n: { type: string }) =>
      n.type === 'project_invitation'
    )
    expect(inviteNotif).toBeTruthy()
    expect(inviteNotif.data?.message || inviteNotif.message || '').toContain('invited you')
  })

  test('C: invitee accepts team invite → becomes team member', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const teamRes = await request.post(`/api/v1/projects/${project.id}/teams`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { name: 'Accept Test Team' },
    })
    const team = (await teamRes.json()).data

    const target = uniqueUser()
    await registerUser(request, target)
    const targetToken = await loginViaApi(request, target)
    const targetMe = await getMe(request, targetToken)

    // A: Send invite
    const inviteRes = await request.post(`/api/v1/project-teams/${team.id}/invites`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { user_id: targetMe.id },
    })
    const invite = (await inviteRes.json()).data

    // Verify NOT a member yet
    const beforeRes = await request.get(`/api/v1/project-teams/${team.id}/members`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
    })
    expect((await beforeRes.json()).data.some((m: { user_id?: string }) => m.user_id === targetMe.id)).toBe(false)

    // C: Accept
    const acceptRes = await request.post(`/api/v1/invites/${invite.id}/accept`, {
      headers: { Authorization: `Bearer ${targetToken}`, Accept: 'application/json' },
    })
    expect(acceptRes.status()).toBe(200)

    // Now IS a team member
    const afterRes = await request.get(`/api/v1/project-teams/${team.id}/members`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
    })
    expect((await afterRes.json()).data.some((m: { user_id?: string }) => m.user_id === targetMe.id)).toBe(true)
  })
})

test.describe('Invite flow UI (invites page)', () => {
  test('full UI flow: invite sent → invitee sees notification → navigates to invites page → accepts', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const target = uniqueUser()
    await registerUser(request, target)
    const targetToken = await loginViaApi(request, target)
    const targetMe = await getMe(request, targetToken)

    // A: Owner sends project invite
    const inviteRes = await request.post(`/api/v1/projects/${project.id}/invites`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { user_id: targetMe.id, message: 'Welcome to the team!' },
    })
    expect(inviteRes.status()).toBe(201)
    const invite = (await inviteRes.json()).data

    // B: Login as invitee and verify they can see the invite via API
    const myInvitesRes = await request.get('/api/v1/my-invites', {
      headers: { Authorization: `Bearer ${targetToken}`, Accept: 'application/json' },
    })
    const myInvites = (await myInvitesRes.json()).data
    expect(myInvites.some((i: { id: string }) => i.id === invite.id)).toBe(true)

    // C: Navigate to invites page and accept
    await loginPageAs(page, targetToken, targetMe)
    await page.goto('/invites')
    await page.waitForSelector('[data-testid="invites-page"]')
    await page.waitForSelector(`[data-testid="invite-${invite.id}"]`)

    // Accept
    await page.locator(`[data-testid="invite-accept-${invite.id}"]`).click()

    // Invite disappears
    await expect(page.locator(`[data-testid="invite-${invite.id}"]`)).not.toBeVisible({ timeout: 10000 })

    // Verify now a project member via API
    const membersRes = await request.get(`/api/v1/projects/${project.id}/members`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
    })
    const members = (await membersRes.json()).data
    expect(members.some((m: { user_id?: string; id?: string }) =>
      m.user_id === targetMe.id || m.id === targetMe.id
    )).toBe(true)
  })
})

test.describe('Invite notification navigation', () => {
  test('clicking invite notification navigates to /invites, not dashboard', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const target = uniqueUser()
    await registerUser(request, target)
    const targetToken = await loginViaApi(request, target)
    const targetMe = await getMe(request, targetToken)

    // Owner sends invite
    await request.post(`/api/v1/projects/${project.id}/invites`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { user_id: targetMe.id, message: 'Come join!' },
    })

    // Login as invitee
    await loginPageAs(page, targetToken, targetMe)
    await page.goto('/dashboard')
    await page.waitForSelector('[data-testid="dashboard-page"]')

    // Open notification dropdown
    await page.locator('[data-testid="notification-bell-btn"]').click()

    // Find and click the invite notification
    const notifItem = page.locator('[data-testid^="dropdown-notification-"]').first()
    await notifItem.waitFor({ state: 'visible' })
    await notifItem.click()

    // Should navigate to /invites, NOT stay on dashboard
    await page.waitForURL(/\/invites$/, { timeout: 10000 })
    await expect(page).toHaveURL(/\/invites$/)
  })

  test('invite notification message says "invited" not "added"', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const target = uniqueUser()
    await registerUser(request, target)
    const targetToken = await loginViaApi(request, target)
    const targetMe = await getMe(request, targetToken)

    // Owner sends invite
    await request.post(`/api/v1/projects/${project.id}/invites`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { user_id: targetMe.id },
    })

    // Check notification text via API
    const notifRes = await request.get('/api/v1/notifications', {
      headers: { Authorization: `Bearer ${targetToken}`, Accept: 'application/json' },
    })
    const notifications = (await notifRes.json()).data
    const inviteNotif = notifications.find((n: { type: string }) => n.type === 'project_invitation')

    expect(inviteNotif).toBeTruthy()
    const message = inviteNotif.data?.message || inviteNotif.message || ''
    // Should say "invited" not "added"
    expect(message).toContain('invited you')
    expect(message).not.toContain('added you')
  })
})
