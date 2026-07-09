import { test, expect, type APIRequestContext } from '@playwright/test'
import { execSync } from 'node:child_process'
import { uniqueUser, registerUser, type TestUser } from './support/auth'
import {
  loginViaApi,
  getMe,
  loginPageAs,
  createWorkspace,
  createProject,
  createSection,
  createColumn,
  createTaskWith,
  setInAppPreference,
} from './support/helpers'

/**
 * The notification chime is synthesized at runtime with the Web Audio API
 * (resources/js/hooks/useNotificationSound.ts). It is NOT audible in an
 * automated browser (no audio output device), so we don't try to "hear" it —
 * we assert the chime actually fired by spying on AudioContext.
 *
 * Prerequisites for the trigger to reach the page user:
 *  - A queue worker must be running (the notification listeners are
 *    ShouldQueue), e.g. `php artisan queue:work`, or QUEUE_CONNECTION=sync.
 *  - The in-app SSE notification stream delivers the new notification to the
 *    open page, which bumps the dropdown's unread count.
 */
test.use({
  // Belt-and-suspenders: stop Chromium from suspending the AudioContext.
  launchOptions: { args: ['--autoplay-policy=no-user-gesture-required'] },
})

// Setup (DB-backed email verification via tinker) plus the SSE-delivery poll
// comfortably exceeds the default 30s; give these tests more room.
test.describe.configure({ timeout: 90_000 })

/**
 * Mark a freshly registered user's email as verified directly in the DB so
 * they can log in and reach `verified`-gated endpoints (local only).
 */
function verifyEmailInDb(email: string): void {
  execSync(
    `php artisan tinker --execute="\\Modules\\User\\Models\\User::where('email','${email}')->update(['email_verified_at' => now()]);"`,
    { cwd: process.cwd(), encoding: 'utf-8' },
  )
}

async function registerVerifiedUser(
  request: APIRequestContext,
  user: TestUser,
): Promise<string> {
  await registerUser(request, user)
  verifyEmailInDb(user.email)
  return loginViaApi(request, user)
}

/** Install an AudioContext spy that counts oscillator .start() calls. */
async function installChimeSpy(page: import('@playwright/test').Page): Promise<void> {
  await page.addInitScript(() => {
    const w = window as unknown as {
      __chimeStarts: number
      AudioContext?: typeof AudioContext
      webkitAudioContext?: typeof AudioContext
    }
    w.__chimeStarts = 0
    const Real = w.AudioContext || w.webkitAudioContext
    if (!Real) return

    const Spy = function (this: unknown, ...args: unknown[]) {
      const ctx = new (Real as unknown as new (...a: unknown[]) => AudioContext)(...args)
      const origCreate = ctx.createOscillator.bind(ctx)
      ctx.createOscillator = () => {
        const osc = origCreate()
        const origStart = osc.start.bind(osc)
        osc.start = (...a: Parameters<OscillatorNode['start']>) => {
          w.__chimeStarts++
          return origStart(...a)
        }
        return osc
      }
      return ctx
    } as unknown as typeof AudioContext

    w.AudioContext = Spy
    w.webkitAudioContext = Spy
  })
}

const chimeStarts = (page: import('@playwright/test').Page) =>
  page.evaluate(() => (window as unknown as { __chimeStarts: number }).__chimeStarts)

test('plays a chime when a new notification arrives', async ({ page, request }) => {
  await installChimeSpy(page)

  // Actor (owner) who will notify the page user.
  const owner = uniqueUser()
  const ownerToken = await registerVerifiedUser(request, owner)
  const workspace = await createWorkspace(request, ownerToken, 'Sound WS')
  const project = await createProject(request, ownerToken, workspace.id, 'Sound Project')
  const section = await createSection(request, ownerToken, project.id)
  const column = await createColumn(request, ownerToken, section.id)

  // The page user who should hear the chime.
  const pageUser = uniqueUser()
  const pageToken = await registerVerifiedUser(request, pageUser)
  const pageUserObj = await getMe(request, pageToken)
  await setInAppPreference(request, pageToken, 'task_assigned', true)

  // Open the app as the page user (NotificationDropdown lives in the shell).
  await loginPageAs(page, pageToken, pageUserObj)
  await page.goto('/dashboard')
  await expect(page).toHaveURL(/\/dashboard$/)

  // Sound not muted; satisfy the "first user interaction" requirement.
  await page.evaluate(() => localStorage.removeItem('notification_sound_muted'))
  await page.mouse.click(5, 5)

  // Trigger a real notification: owner assigns a task to the page user.
  await createTaskWith(request, ownerToken, {
    title: 'Please review',
    project_id: project.id,
    section_id: section.id,
    column_id: column.id,
    assignee_ids: [pageUserObj.id],
  })

  // The unread count increases via SSE; the hook then starts the oscillators.
  await expect
    .poll(() => chimeStarts(page), {
      timeout: 25_000,
      message: 'Expected the notification chime to start an oscillator after a new notification arrived',
    })
    .toBeGreaterThan(0)
})

test('does not play when notification sound is muted', async ({ page, request }) => {
  await installChimeSpy(page)

  const owner = uniqueUser()
  const ownerToken = await registerVerifiedUser(request, owner)
  const workspace = await createWorkspace(request, ownerToken, 'Mute WS')
  const project = await createProject(request, ownerToken, workspace.id, 'Mute Project')
  const section = await createSection(request, ownerToken, project.id)
  const column = await createColumn(request, ownerToken, section.id)

  const pageUser = uniqueUser()
  const pageToken = await registerVerifiedUser(request, pageUser)
  const pageUserObj = await getMe(request, pageToken)
  await setInAppPreference(request, pageToken, 'task_assigned', true)

  await loginPageAs(page, pageToken, pageUserObj)
  await page.goto('/dashboard')
  await page.evaluate(() => localStorage.setItem('notification_sound_muted', 'true'))
  await page.mouse.click(5, 5)

  await createTaskWith(request, ownerToken, {
    title: 'Muted assignment',
    project_id: project.id,
    section_id: section.id,
    column_id: column.id,
    assignee_ids: [pageUserObj.id],
  })

  // Wait for the notification to arrive, then assert the chime never fired.
  await page.waitForTimeout(10_000)
  expect(await chimeStarts(page)).toBe(0)
})
