/**
 * k6 API Performance Test — Finolo
 *
 * Tests all major API endpoints for response time and throughput.
 * Run: k6 run tests/performance/k6-api-load.js
 *
 * Thresholds:
 *   - 95th percentile response time < 500ms
 *   - 99th percentile response time < 1500ms
 *   - Error rate < 1%
 */

import http from 'k6/http'
import { check, sleep, group } from 'k6'
import { Rate, Trend } from 'k6/metrics'

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:8000/api/v1'
const TEST_EMAIL_DOMAIN = __ENV.TEST_EMAIL_DOMAIN || 'test.example.com'
const errorRate = new Rate('errors')
const authDuration = new Trend('auth_duration')
const projectDuration = new Trend('project_duration')
const taskDuration = new Trend('task_duration')
const boardDuration = new Trend('board_duration')

export const options = {
  stages: [
    { duration: '10s', target: 5 },   // ramp up
    { duration: '30s', target: 10 },  // sustained load
    { duration: '10s', target: 20 },  // peak
    { duration: '10s', target: 0 },   // ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1500'],
    errors: ['rate<0.01'],
    auth_duration: ['p(95)<300'],
    project_duration: ['p(95)<500'],
    task_duration: ['p(95)<500'],
    board_duration: ['p(95)<800'],
  },
}

const HEADERS = { 'Content-Type': 'application/json', Accept: 'application/json' }

function registerAndLogin() {
  const id = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`
  const email = `perf-${id}@${TEST_EMAIL_DOMAIN}`
  const password = 'PerfTest1!'

  http.post(`${BASE_URL}/auth/register`, JSON.stringify({
    name: `Perf User ${id}`,
    email,
    password,
    password_confirmation: password,
    timezone: 'UTC',
    job_title: 'Tester',
  }), { headers: HEADERS })

  const loginRes = http.post(`${BASE_URL}/auth/login`, JSON.stringify({
    email,
    password,
  }), { headers: HEADERS })

  authDuration.add(loginRes.timings.duration)

  const body = JSON.parse(loginRes.body || '{}')
  const token = body.data?.token || body.token || ''
  return { token, email }
}

export default function () {
  const { token } = registerAndLogin()
  const authHeaders = { ...HEADERS, Authorization: `Bearer ${token}` }

  let workspaceId, projectId, sectionId, columnId, taskId

  // ─── Auth endpoints ─────────────────────────────────────
  group('Auth', () => {
    const me = http.get(`${BASE_URL}/auth/me`, { headers: authHeaders })
    check(me, { 'GET /auth/me → 200': (r) => r.status === 200 })
    errorRate.add(me.status !== 200)
    authDuration.add(me.timings.duration)
  })

  // ─── Workspace ──────────────────────────────────────────
  group('Workspace', () => {
    const create = http.post(`${BASE_URL}/workspaces`, JSON.stringify({
      name: `PerfWS-${Date.now()}`,
      description: 'Performance test',
      visibility: 'private',
    }), { headers: authHeaders })
    check(create, { 'POST /workspaces → 201': (r) => r.status === 201 })
    workspaceId = JSON.parse(create.body || '{}').data?.id

    const list = http.get(`${BASE_URL}/workspaces`, { headers: authHeaders })
    check(list, { 'GET /workspaces → 200': (r) => r.status === 200 })
  })

  // ─── Projects ───────────────────────────────────────────
  group('Projects', () => {
    const create = http.post(`${BASE_URL}/projects`, JSON.stringify({
      name: `PerfProject-${Date.now()}`,
      status: 'active',
      priority: 'medium',
      workspace_id: workspaceId,
    }), { headers: authHeaders })
    check(create, { 'POST /projects → 201': (r) => r.status === 201 })
    projectId = JSON.parse(create.body || '{}').data?.id
    projectDuration.add(create.timings.duration)

    const list = http.get(`${BASE_URL}/projects?per_page=12`, { headers: authHeaders })
    check(list, { 'GET /projects → 200': (r) => r.status === 200 })
    projectDuration.add(list.timings.duration)

    if (projectId) {
      const show = http.get(`${BASE_URL}/projects/${projectId}`, { headers: authHeaders })
      check(show, { 'GET /projects/:id → 200': (r) => r.status === 200 })
      projectDuration.add(show.timings.duration)
    }
  })

  // ─── Sections & Columns ─────────────────────────────────
  group('Board Setup', () => {
    if (!projectId) return

    const sec = http.post(`${BASE_URL}/sections`, JSON.stringify({
      name: 'Sprint 1',
      project_id: projectId,
      sort_order: 1,
    }), { headers: authHeaders })
    sectionId = JSON.parse(sec.body || '{}').data?.id
    boardDuration.add(sec.timings.duration)

    if (sectionId) {
      const col = http.post(`${BASE_URL}/columns`, JSON.stringify({
        name: 'To Do',
        section_id: sectionId,
        sort_order: 1,
      }), { headers: authHeaders })
      columnId = JSON.parse(col.body || '{}').data?.id
      boardDuration.add(col.timings.duration)

      const secList = http.get(`${BASE_URL}/sections?project_id=${projectId}`, { headers: authHeaders })
      check(secList, { 'GET /sections → 200': (r) => r.status === 200 })
      boardDuration.add(secList.timings.duration)

      if (sectionId) {
        const colList = http.get(`${BASE_URL}/sections/${sectionId}/columns`, { headers: authHeaders })
        check(colList, { 'GET /sections/:id/columns → 200': (r) => r.status === 200 })
        boardDuration.add(colList.timings.duration)
      }
    }
  })

  // ─── Tasks ──────────────────────────────────────────────
  group('Tasks', () => {
    if (!columnId) return

    const create = http.post(`${BASE_URL}/tasks`, JSON.stringify({
      title: `PerfTask-${Date.now()}`,
      column_id: columnId,
      priority: 'medium',
      status: 'open',
    }), { headers: authHeaders })
    check(create, { 'POST /tasks → 201': (r) => r.status === 201 })
    taskId = JSON.parse(create.body || '{}').data?.id
    taskDuration.add(create.timings.duration)

    const list = http.get(`${BASE_URL}/tasks?project_id=${projectId}&per_page=10`, { headers: authHeaders })
    check(list, { 'GET /tasks → 200': (r) => r.status === 200 })
    taskDuration.add(list.timings.duration)

    if (taskId) {
      const show = http.get(`${BASE_URL}/tasks/${taskId}`, { headers: authHeaders })
      check(show, { 'GET /tasks/:id → 200': (r) => r.status === 200 })
      taskDuration.add(show.timings.duration)

      const update = http.patch(`${BASE_URL}/tasks/${taskId}`, JSON.stringify({
        title: 'Updated Task',
        status: 'in_progress',
      }), { headers: authHeaders })
      check(update, { 'PATCH /tasks/:id → 200': (r) => r.status === 200 })
      taskDuration.add(update.timings.duration)
    }
  })

  // ─── Comments ───────────────────────────────────────────
  group('Comments', () => {
    if (!taskId) return

    const create = http.post(`${BASE_URL}/comments`, JSON.stringify({
      task_id: taskId,
      content: 'Performance test comment',
    }), { headers: authHeaders })
    check(create, { 'POST /comments → 201': (r) => r.status === 201 })

    const list = http.get(`${BASE_URL}/comments?task_id=${taskId}`, { headers: authHeaders })
    check(list, { 'GET /comments → 200': (r) => r.status === 200 })
  })

  // ─── Time Logs ──────────────────────────────────────────
  group('Time Logs', () => {
    if (!taskId) return

    const create = http.post(`${BASE_URL}/time-logs`, JSON.stringify({
      task_id: taskId,
      hours: 1,
      minutes: 30,
      description: 'Perf test log',
      logged_date: new Date().toISOString().slice(0, 10),
    }), { headers: authHeaders })
    check(create, { 'POST /time-logs → 201': (r) => r.status === 201 })
  })

  // ─── Notifications ──────────────────────────────────────
  group('Notifications', () => {
    const list = http.get(`${BASE_URL}/notifications`, { headers: authHeaders })
    check(list, { 'GET /notifications → 200': (r) => r.status === 200 })
  })

  // ─── My Permissions ─────────────────────────────────────
  group('Permissions', () => {
    if (!projectId) return
    const perms = http.get(`${BASE_URL}/projects/${projectId}/my-permissions`, { headers: authHeaders })
    check(perms, { 'GET /my-permissions → 200': (r) => r.status === 200 })
  })

  // ─── Teams ──────────────────────────────────────────────
  group('Teams', () => {
    const create = http.post(`${BASE_URL}/teams`, JSON.stringify({
      name: `PerfTeam-${Date.now()}`,
    }), { headers: authHeaders })
    check(create, { 'POST /teams → 201': (r) => r.status === 201 })

    const my = http.get(`${BASE_URL}/teams/my`, { headers: authHeaders })
    check(my, { 'GET /teams/my → 200': (r) => r.status === 200 })
  })

  // ─── Search ─────────────────────────────────────────────
  group('Search', () => {
    const search = http.get(`${BASE_URL}/tasks/search?q=perf&per_page=5`, { headers: authHeaders })
    check(search, { 'GET /tasks/search → 200': (r) => r.status === 200 })
  })

  sleep(1)
}
