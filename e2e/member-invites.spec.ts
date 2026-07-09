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
 * Member Invite Flow E2E Tests
 *
 * Covers:
 * 1. Standalone team creation (no project required)
 * 2. Team member invite → accept/decline flow
 * 3. Project member invite → accept/decline flow
 * 4. Invites page UI shows pending invites
 */

test.describe('Standalone Teams (no project)', () => {
  test('user can create a team without a project', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)

    const res = await request.post('/api/v1/teams', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { name: 'Standalone Team', description: 'No project needed' },
    })
    expect(res.status()).toBe(201)

    const body = await res.json()
    expect(body.data.name).toBe('Standalone Team')
    expect(body.data.project_id).toBeNull()
  })
})

test.describe('Team Member Invite Flow', () => {
  test('owner sends invite to team → invitee sees it and accepts', async ({ page, request }) => {
    // Setup owner with project + team
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    // Create a team
    const teamRes = await request.post(`/api/v1/projects/${project.id}/teams`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { name: 'Alpha Team' },
    })
    expect(teamRes.status()).toBe(201)
    const team = (await teamRes.json()).data

    // Register invitee
    const invitee = uniqueUser()
    await registerUser(request, invitee)
    const inviteeToken = await loginViaApi(request, invitee)
    const inviteeMe = await getMe(request, inviteeToken)

    // Owner sends invite to team
    const inviteRes = await request.post(`/api/v1/project-teams/${team.id}/invites`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { user_id: inviteeMe.id, role: 'member', message: 'Join our team!' },
    })
    expect(inviteRes.status()).toBe(201)
    const invite = (await inviteRes.json()).data

    // Invitee checks their pending invites
    const myInvitesRes = await request.get('/api/v1/my-invites', {
      headers: { Authorization: `Bearer ${inviteeToken}`, Accept: 'application/json' },
    })
    expect(myInvitesRes.status()).toBe(200)
    const myInvites = (await myInvitesRes.json()).data
    expect(myInvites.length).toBeGreaterThanOrEqual(1)
    expect(myInvites.some((i: { id: string }) => i.id === invite.id)).toBe(true)

    // Invitee accepts the invite
    const acceptRes = await request.post(`/api/v1/invites/${invite.id}/accept`, {
      headers: { Authorization: `Bearer ${inviteeToken}`, Accept: 'application/json' },
    })
    expect(acceptRes.status()).toBe(200)
    const accepted = (await acceptRes.json()).data
    expect(accepted.status).toBe('accepted')

    // Verify invitee is now a team member
    const membersRes = await request.get(`/api/v1/project-teams/${team.id}/members`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
    })
    expect(membersRes.status()).toBe(200)
    const members = (await membersRes.json()).data
    expect(members.some((m: { user_id: string }) => m.user_id === inviteeMe.id)).toBe(true)
  })

  test('invitee can decline a team invite', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const teamRes = await request.post(`/api/v1/projects/${project.id}/teams`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { name: 'Beta Team' },
    })
    const team = (await teamRes.json()).data

    const invitee = uniqueUser()
    await registerUser(request, invitee)
    const inviteeToken = await loginViaApi(request, invitee)
    const inviteeMe = await getMe(request, inviteeToken)

    const inviteRes = await request.post(`/api/v1/project-teams/${team.id}/invites`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { user_id: inviteeMe.id },
    })
    const invite = (await inviteRes.json()).data

    // Decline
    const declineRes = await request.post(`/api/v1/invites/${invite.id}/decline`, {
      headers: { Authorization: `Bearer ${inviteeToken}`, Accept: 'application/json' },
    })
    expect(declineRes.status()).toBe(200)
    const declined = (await declineRes.json()).data
    expect(declined.status).toBe('declined')

    // Invitee should NOT be a team member
    const membersRes = await request.get(`/api/v1/project-teams/${team.id}/members`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
    })
    const members = (await membersRes.json()).data
    expect(members.some((m: { user_id: string }) => m.user_id === inviteeMe.id)).toBe(false)
  })

  test('duplicate invite to same team is rejected', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const teamRes = await request.post(`/api/v1/projects/${project.id}/teams`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { name: 'Gamma Team' },
    })
    const team = (await teamRes.json()).data

    const invitee = uniqueUser()
    await registerUser(request, invitee)
    const inviteeToken = await loginViaApi(request, invitee)
    const inviteeMe = await getMe(request, inviteeToken)

    // First invite succeeds
    const first = await request.post(`/api/v1/project-teams/${team.id}/invites`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { user_id: inviteeMe.id },
    })
    expect(first.status()).toBe(201)

    // Second invite should be rejected
    const second = await request.post(`/api/v1/project-teams/${team.id}/invites`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { user_id: inviteeMe.id },
    })
    expect(second.status()).toBe(422)
  })
})

test.describe('Project Member Invite Flow', () => {
  test('owner sends project invite → invitee accepts and becomes member', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    // Register invitee
    const invitee = uniqueUser()
    await registerUser(request, invitee)
    const inviteeToken = await loginViaApi(request, invitee)
    const inviteeMe = await getMe(request, inviteeToken)

    // Owner sends project invite
    const inviteRes = await request.post(`/api/v1/projects/${project.id}/invites`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { user_id: inviteeMe.id, message: 'Welcome to the project!' },
    })
    expect(inviteRes.status()).toBe(201)
    const invite = (await inviteRes.json()).data
    expect(invite.type).toBe('project')
    expect(invite.project_name).toBe(project.name)

    // Invitee accepts
    const acceptRes = await request.post(`/api/v1/invites/${invite.id}/accept`, {
      headers: { Authorization: `Bearer ${inviteeToken}`, Accept: 'application/json' },
    })
    expect(acceptRes.status()).toBe(200)

    // Verify invitee is now a project member
    const membersRes = await request.get(`/api/v1/projects/${project.id}/members`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
    })
    expect(membersRes.status()).toBe(200)
    const members = (await membersRes.json()).data
    expect(members.some((m: { user_id?: string; id?: string }) => m.user_id === inviteeMe.id || m.id === inviteeMe.id)).toBe(true)
  })

  test('invitee can decline a project invite', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    const invitee = uniqueUser()
    await registerUser(request, invitee)
    const inviteeToken = await loginViaApi(request, invitee)
    const inviteeMe = await getMe(request, inviteeToken)

    const inviteRes = await request.post(`/api/v1/projects/${project.id}/invites`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { user_id: inviteeMe.id },
    })
    const invite = (await inviteRes.json()).data

    const declineRes = await request.post(`/api/v1/invites/${invite.id}/decline`, {
      headers: { Authorization: `Bearer ${inviteeToken}`, Accept: 'application/json' },
    })
    expect(declineRes.status()).toBe(200)

    // Should NOT be a member
    const membersRes = await request.get(`/api/v1/projects/${project.id}/members`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
    })
    const members = (await membersRes.json()).data
    expect(members.some((m: { user_id?: string }) => m.user_id === inviteeMe.id)).toBe(false)
  })

  test('non-admin cannot send project invites', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    // Create a regular member (no manage_members permission)
    const member = uniqueUser()
    await registerUser(request, member)
    const memberToken = await loginViaApi(request, member)
    const memberMe = await getMe(request, memberToken)

    // Another user to invite
    const target = uniqueUser()
    await registerUser(request, target)
    const targetToken = await loginViaApi(request, target)
    const targetMe = await getMe(request, targetToken)

    const res = await request.post(`/api/v1/projects/${project.id}/invites`, {
      headers: { Authorization: `Bearer ${memberToken}`, Accept: 'application/json' },
      data: { user_id: targetMe.id },
    })
    expect(res.status()).toBe(403)
  })
})

test.describe('Invites Page UI', () => {
  test('invitee sees pending invite on the invites page and can accept', async ({ page, request }) => {
    const { token: ownerToken } = await setupAuthenticatedPage(page, request)
    const workspace = await createWorkspace(request, ownerToken)
    const { project } = await setupBoardWithTask(request, ownerToken, workspace.id)

    // Register invitee
    const invitee = uniqueUser()
    await registerUser(request, invitee)
    const inviteeToken = await loginViaApi(request, invitee)
    const inviteeMe = await getMe(request, inviteeToken)

    // Owner sends project invite
    const inviteRes = await request.post(`/api/v1/projects/${project.id}/invites`, {
      headers: { Authorization: `Bearer ${ownerToken}`, Accept: 'application/json' },
      data: { user_id: inviteeMe.id, message: 'Welcome aboard' },
    })
    expect(inviteRes.status()).toBe(201)
    const invite = (await inviteRes.json()).data

    // Login as invitee and navigate to invites page
    await loginPageAs(page, inviteeToken, inviteeMe)
    await page.goto('/invites')
    await page.waitForSelector('[data-testid="invites-page"]')

    // Should see the invite
    await page.waitForSelector(`[data-testid="invite-${invite.id}"]`)
    await expect(page.locator(`[data-testid="invite-${invite.id}"]`)).toBeVisible()

    // Accept button should be visible
    await expect(page.locator(`[data-testid="invite-accept-${invite.id}"]`)).toBeVisible()
    await expect(page.locator(`[data-testid="invite-decline-${invite.id}"]`)).toBeVisible()

    // Click accept
    await page.locator(`[data-testid="invite-accept-${invite.id}"]`).click()

    // Invite should disappear after acceptance
    await expect(page.locator(`[data-testid="invite-${invite.id}"]`)).not.toBeVisible()
  })

  test('invitee sees empty state when no pending invites', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)

    await page.goto('/invites')
    await page.waitForSelector('[data-testid="invites-page"]')

    await expect(page.locator('[data-testid="invites-empty"]')).toBeVisible()
  })
})

test.describe('Standalone team creation via UI', () => {
  test('user can create a team without selecting a project in the UI', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)

    await page.goto('/teams')
    await page.waitForSelector('[data-testid="teams-permissions-loaded"]', { state: 'attached' })

    // Click Create Team button
    await page.locator('[data-testid="create-team-btn"]').click()

    // Fill in only the name (leave project unselected)
    await page.waitForSelector('[data-testid="team-modal"]')
    await page.locator('[data-testid="team-name-input"]').fill('My Standalone Team')
    await page.locator('[data-testid="team-description-input"]').fill('No project needed')

    // Submit without selecting a project
    await page.locator('[data-testid="team-submit-btn"]').click()

    // Should succeed - team appears in list
    await page.waitForSelector('[data-testid="teams-list"]')
    await expect(page.locator('text=My Standalone Team')).toBeVisible()
  })
})

test.describe('Standalone team creator permissions', () => {
  test('creator is auto-added as team member when creating standalone team', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)
    const me = await getMe(request, token)

    // Create standalone team
    const teamRes = await request.post('/api/v1/teams', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { name: 'My Team' },
    })
    expect(teamRes.status()).toBe(201)
    const team = (await teamRes.json()).data

    // Check members — creator should be there
    const membersRes = await request.get(`/api/v1/project-teams/${team.id}/members`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    expect(membersRes.status()).toBe(200)
    const members = (await membersRes.json()).data
    expect(members.some((m: { user_id: string }) => m.user_id === me.id)).toBe(true)
  })

  test('creator can invite members to their standalone team', async ({ page, request }) => {
    const { token } = await setupAuthenticatedPage(page, request)

    // Create standalone team
    const teamRes = await request.post('/api/v1/teams', {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { name: 'Invite Team' },
    })
    const team = (await teamRes.json()).data

    // Register another user
    const target = uniqueUser()
    await registerUser(request, target)
    const targetToken = await loginViaApi(request, target)
    const targetMe = await getMe(request, targetToken)

    // Creator invites via the team invite endpoint
    const inviteRes = await request.post(`/api/v1/project-teams/${team.id}/invites`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      data: { user_id: targetMe.id, role: 'member' },
    })
    expect(inviteRes.status()).toBe(201)

    // Target accepts
    const invite = (await inviteRes.json()).data
    const acceptRes = await request.post(`/api/v1/invites/${invite.id}/accept`, {
      headers: { Authorization: `Bearer ${targetToken}`, Accept: 'application/json' },
    })
    expect(acceptRes.status()).toBe(200)

    // Verify target is now a member
    const membersRes = await request.get(`/api/v1/project-teams/${team.id}/members`, {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
    })
    const members = (await membersRes.json()).data
    expect(members.some((m: { user_id: string }) => m.user_id === targetMe.id)).toBe(true)
  })
})
