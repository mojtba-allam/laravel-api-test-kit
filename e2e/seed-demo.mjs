/**
 * Seeds two stable demo users and generates EVERY in-app notification type for
 * User B against the running app (http://127.0.0.1:8000), using only the real
 * REST API — no mocking. Re-runnable: if the users already exist it just logs
 * them in. After running, sign in as User B and watch the notifications work.
 *
 *   node tests/e2e/seed-demo.mjs
 */

const BASE = process.env.BASE_URL ?? 'http://127.0.0.1:8000'

const USER_A = { name: 'Demo User A', email: 'demo-a@test.example.com', password: 'Demo12345!' }
const USER_B = { name: 'Demo User B', email: 'demo-b@test.example.com', password: 'Demo12345!' }

async function api(path, { token, method = 'GET', body, form } = {}) {
  const headers = { Accept: 'application/json' }
  if (token) headers.Authorization = `Bearer ${token}`
  let payload
  if (form) {
    payload = form
  } else if (body !== undefined) {
    headers['Content-Type'] = 'application/json'
    payload = JSON.stringify(body)
  }
  const res = await fetch(`${BASE}${path}`, { method, headers, body: payload })
  const text = await res.text()
  let json
  try {
    json = text ? JSON.parse(text) : {}
  } catch {
    json = { raw: text }
  }
  return { status: res.status, json }
}

async function ensureUser(user) {
  await api('/api/v1/auth/register', {
    method: 'POST',
    body: {
      name: user.name,
      email: user.email,
      password: user.password,
      password_confirmation: user.password,
      timezone: 'UTC',
      job_title: 'Demo',
    },
  })
  const login = await api('/api/v1/auth/login', {
    method: 'POST',
    body: { email: user.email, password: user.password },
  })
  if (login.status !== 200) {
    throw new Error(`Login failed for ${user.email}: ${login.status} ${JSON.stringify(login.json)}`)
  }
  const token = login.json.data?.token ?? login.json.token
  const me = await api('/api/v1/auth/me', { token })
  return { token, id: me.json.data.id }
}

async function enablePref(token, type) {
  await api('/api/v1/notification-preferences', {
    token,
    method: 'POST',
    body: {
      notification_type: type,
      email_enabled: false,
      in_app_enabled: true,
      realtime_enabled: false,
      push_enabled: false,
    },
  })
}

async function main() {
  const a = await ensureUser(USER_A)
  const b = await ensureUser(USER_B)
  const stamp = Date.now()

  // Make sure B receives the default-disabled types too.
  for (const t of ['task_status_changed', 'comment_added', 'attachment_added']) {
    await enablePref(b.token, t)
  }

  // A builds a board and assigns a task to B (this also makes B a project
  // member → project_member_added + task_assigned).
  const ws = (await api('/api/v1/workspaces', {
    token: a.token, method: 'POST', body: { name: `Demo Workspace ${stamp}`, description: 'Demo' },
  })).json.data
  const project = (await api('/api/v1/projects', {
    token: a.token, method: 'POST',
    body: { name: `Demo Project ${stamp}`, description: 'Demo', status: 'active', priority: 'medium', workspace_id: ws.id },
  })).json.data
  const section = (await api('/api/v1/sections', {
    token: a.token, method: 'POST', body: { name: 'Sprint 1', project_id: project.id, sort_order: 1 },
  })).json.data
  const column = (await api('/api/v1/columns', {
    token: a.token, method: 'POST', body: { name: 'To Do', section_id: section.id, sort_order: 1 },
  })).json.data
  const task = (await api('/api/v1/tasks', {
    token: a.token, method: 'POST',
    body: {
      title: `Demo Task ${stamp}`, project_id: project.id, section_id: section.id, column_id: column.id,
      status: 'open', priority: 'medium', assignee_ids: [b.id],
    },
  })).json.data

  // comment_mention (B mentioned) + comment_added (separate comment, B is assignee, not mentioned)
  await api('/api/v1/comments', { token: a.token, method: 'POST', body: { task_id: task.id, content: 'Please review this, thanks!', mentions: [b.id] } })
  await api('/api/v1/comments', { token: a.token, method: 'POST', body: { task_id: task.id, content: 'General progress update on the task.' } })

  // attachment_added
  const fd = new FormData()
  fd.set('task_id', task.id)
  fd.set('description', 'Demo attachment')
  fd.set('file', new Blob([`Demo file ${stamp}`], { type: 'text/plain' }), `demo-${stamp}.txt`)
  await api('/api/v1/attachments/upload', { token: a.token, method: 'POST', form: fd })

  // task_status_changed then task_completed
  await api(`/api/v1/tasks/${task.id}`, { token: a.token, method: 'PATCH', body: { status: 'in_progress' } })
  await api(`/api/v1/tasks/${task.id}`, { token: a.token, method: 'PATCH', body: { status: 'completed' } })

  // project_invitation (workspace invite to B's email)
  await api(`/api/v1/workspaces/${ws.id}/invites`, { token: a.token, method: 'POST', body: { email: USER_B.email } })

  // Report what B now has.
  const feed = await api('/api/v1/notifications?per_page=50', { token: b.token })
  const types = (feed.json.data ?? []).map((n) => n.type)

  console.log('\n=== Demo data seeded ===')
  console.log(`App URL:        ${BASE}`)
  console.log(`User A (actor): ${USER_A.email}  /  ${USER_A.password}`)
  console.log(`User B (recv):  ${USER_B.email}  /  ${USER_B.password}`)
  console.log(`\nUser B now has ${types.length} notifications:`)
  console.log(types.map((t) => `  - ${t}`).join('\n'))
  console.log('\nLog in as User B, open /notifications, and click any card to see it navigate.')
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
