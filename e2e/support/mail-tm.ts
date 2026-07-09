/**
 * mail.tm API helper for real email verification testing.
 * Creates disposable inboxes and polls for incoming verification emails.
 */

import { request as pwRequest, type APIRequestContext } from '@playwright/test'

export interface MailTmInbox {
  ctx: APIRequestContext
  address: string
  token: string
}

/**
 * Creates a fresh disposable inbox on mail.tm.
 */
export async function createMailTmInbox(): Promise<MailTmInbox> {
  const ctx = await pwRequest.newContext({ baseURL: 'https://api.mail.tm' })

  // Get available domain
  const domainsRes = await ctx.get('/domains')
  const domainsBody = await domainsRes.json()
  const domain = domainsBody['hydra:member'][0].domain

  const address = `finolo-e2e-${Date.now()}-${Math.random().toString(36).slice(2, 8)}@${domain}`
  const password = 'TestMailTm@2026'

  // Create account (with retry)
  let createRes = await ctx.post('/accounts', { data: { address, password } })
  if (createRes.status() === 429) {
    await new Promise((r) => setTimeout(r, 5000))
    createRes = await ctx.post('/accounts', { data: { address, password } })
  }
  if (createRes.status() !== 201) {
    const body = await createRes.text()
    throw new Error(`Failed to create mail.tm account: ${createRes.status()} - ${body}`)
  }

  // Get auth token
  const tokenRes = await ctx.post('/token', { data: { address, password } })
  if (tokenRes.status() !== 200) {
    throw new Error(`Failed to get mail.tm token: ${tokenRes.status()}`)
  }
  const token = (await tokenRes.json()).token

  return { ctx, address, token }
}

/**
 * Polls the mail.tm inbox until an email arrives containing a 6-digit code.
 * Always reads the NEWEST message to avoid stale code issues.
 * If `afterMessageCount` is provided, waits until inbox has MORE than that many messages.
 */
export async function waitForVerificationCode(
  inbox: MailTmInbox,
  timeoutMs = 60_000,
  pollIntervalMs = 3_000,
  afterMessageCount = 0,
): Promise<string> {
  const deadline = Date.now() + timeoutMs

  while (Date.now() < deadline) {
    const listRes = await inbox.ctx.get('/messages', {
      headers: { Authorization: `Bearer ${inbox.token}` },
    })

    if (listRes.status() === 200) {
      const listBody = await listRes.json()
      const messages = listBody['hydra:member'] || []

      // Wait until we have more messages than the baseline
      if (messages.length > afterMessageCount) {
        // Read the newest message (first in the array — sorted by most recent)
        const msgId = messages[0].id
        const msgRes = await inbox.ctx.get(`/messages/${msgId}`, {
          headers: { Authorization: `Bearer ${inbox.token}` },
        })

        if (msgRes.status() === 200) {
          const msgBody = await msgRes.json()
          const text = `${msgBody.text || ''} ${(msgBody.html || []).join(' ')}`
          const match = text.match(/\b(\d{6})\b/)
          if (match) {
            return match[1]
          }
        }
      }
    }

    await new Promise((r) => setTimeout(r, pollIntervalMs))
  }

  throw new Error(`Verification code did not arrive within ${timeoutMs / 1000}s`)
}

/**
 * Returns current message count in the inbox.
 */
export async function getMessageCount(inbox: MailTmInbox): Promise<number> {
  const res = await inbox.ctx.get('/messages', {
    headers: { Authorization: `Bearer ${inbox.token}` },
  })
  if (res.status() !== 200) return 0
  const body = await res.json()
  return (body['hydra:member'] || []).length
}

/**
 * Cleanup: dispose the API context.
 */
export async function deleteMailTmInbox(inbox: MailTmInbox): Promise<void> {
  try {
    await inbox.ctx.dispose()
  } catch {
    // Ignore cleanup errors
  }
}
