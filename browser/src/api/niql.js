// "Ask": an optional recommendation service of your own picks something to watch from the
// library (API in docs/niql.md). Off unless the build sets VITE_NIQL_URL (e.g. "/niql", passed
// on by the web server), because each question carries the user's Jellyfin token.
import { auth } from './jellyfin.js'

const base = (import.meta.env.VITE_NIQL_URL || '').replace(/\/+$/, '')
const url = base.startsWith('/') ? location.origin + base : base

/** Whether a recommendation service is set up for this build. */
export const enabled = !!url

/** Niql's answer: a line of chat and up to three titles, with a reason each. */
export async function ask(text) {
  if (!enabled) throw new Error('No recommendation service is set up')
  const ctl = new AbortController()
  const timer = setTimeout(() => ctl.abort(), 120000)
  try {
    const r = await fetch(`${url}/api/hevyfin/ask`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'X-Emby-Token': auth.token },
      body: JSON.stringify({ text }),
      signal: ctl.signal,
    })
    const body = await r.json().catch(() => ({}))
    if (!r.ok) throw new Error(body.error || `The recommendation service is unavailable (${r.status})`)
    return { answer: String(body.answer || ''), picks: (body.picks || []).map((p) => ({ id: String(p.id), why: String(p.why || '') })) }
  } catch (e) {
    if (e.name === 'AbortError') throw new Error('The recommendation service took too long to answer')
    throw e
  } finally {
    clearTimeout(timer)
  }
}
