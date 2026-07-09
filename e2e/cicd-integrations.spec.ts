import { test, expect } from '@playwright/test'
import { mintToken } from './support/auth'

/**
 * CI/CD Integrations E2E Tests — API level only.
 * Fast: no page navigation, direct token minting via shared adapter.
 */

test.describe('CI/CD Integrations', () => {
  test('full CRUD lifecycle + runs + test connection', async ({ request }) => {
    const { token } = mintToken(undefined, true)
    const h = { Authorization: `Bearer ${token}`, Accept: 'application/json' }

    // Providers
    const provRes = await request.get('/api/v1/integrations/providers', { headers: h })
    expect(provRes.status()).toBe(200)
    expect((await provRes.json()).data.map((p: { value: string }) => p.value)).toContain('github_actions')

    // Setup project
    const ws = (await (await request.post('/api/v1/workspaces', { headers: h, data: { name: 'CW', description: 'x' } })).json()).data
    const proj = (await (await request.post('/api/v1/projects', { headers: h, data: { name: 'CP', status: 'active', workspace_id: ws.id } })).json()).data

    // Create
    const cr = await request.post(`/api/v1/projects/${proj.id}/integrations`, {
      headers: h,
      data: { provider: 'github_actions', name: 'CI', repository: 'org/repo', token: 'ghp_x' },
    })
    expect(cr.status()).toBe(201)
    const intg = (await cr.json()).data
    expect(intg.provider).toBe('github_actions')
    expect(intg.token).toBeUndefined()

    // List
    const list = await request.get(`/api/v1/projects/${proj.id}/integrations`, { headers: h })
    expect(list.status()).toBe(200)
    expect((await list.json()).data.length).toBe(1)

    // Show
    const show = await request.get(`/api/v1/integrations/${intg.id}`, { headers: h })
    expect(show.status()).toBe(200)

    // Update
    const upd = await request.put(`/api/v1/integrations/${intg.id}`, { headers: h, data: { name: 'New' } })
    expect(upd.status()).toBe(200)
    expect((await upd.json()).data.name).toBe('New')

    // Runs
    const runs = await request.get(`/api/v1/integrations/${intg.id}/runs`, { headers: h })
    expect(runs.status()).toBe(200)
    expect((await runs.json()).meta.provider).toBe('github_actions')

    // Test connection
    const tc = await request.post(`/api/v1/integrations/${intg.id}/test`, { headers: h })
    expect(tc.status()).toBe(200)

    // Delete
    expect((await request.delete(`/api/v1/integrations/${intg.id}`, { headers: h })).status()).toBe(200)
    expect((await request.get(`/api/v1/integrations/${intg.id}`, { headers: h })).status()).toBe(404)
  })

  test('validation errors', async ({ request }) => {
    const { token } = mintToken()
    const h = { Authorization: `Bearer ${token}`, Accept: 'application/json' }

    const ws = (await (await request.post('/api/v1/workspaces', { headers: h, data: { name: 'VW', description: 'x' } })).json()).data
    const proj = (await (await request.post('/api/v1/projects', { headers: h, data: { name: 'VP', status: 'active', workspace_id: ws.id } })).json()).data

    // Empty body
    expect((await request.post(`/api/v1/projects/${proj.id}/integrations`, { headers: h, data: {} })).status()).toBe(422)

    // Invalid provider
    expect((await request.post(`/api/v1/projects/${proj.id}/integrations`, {
      headers: h, data: { provider: 'bad', name: 'X', repository: 'a/b', token: 't' },
    })).status()).toBe(422)
  })
})
