// Calls to the panel's own API. A 401 means the session ended: the app shows the sign-in again.
import { ref } from 'vue'

export const signedOut = ref(false)
export const toast = ref('')
let timer

export function say(text) {
  toast.value = text
  clearTimeout(timer)
  timer = setTimeout(() => (toast.value = ''), 4000)
}

export async function api(path, { method = 'GET', body } = {}) {
  const r = await fetch('/api/' + path, {
    method,
    headers: { 'X-Hevyfin-Admin': '1', ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}) },
    body: body !== undefined ? JSON.stringify(body) : undefined,
    credentials: 'same-origin',
  })
  const data = await r.json().catch(() => ({}))
  if (r.status === 401 && path !== 'login') signedOut.value = true
  if (!r.ok) throw new Error(data.error || `Error ${r.status}`)
  return data
}

export const gb = (b) => (b >= 1e12 ? (b / 1e12).toFixed(2) + ' TB' : (b / 1e9).toFixed(b >= 1e10 ? 0 : 1) + ' GB')
export const ago = (s) => {
  if (!s) return 'never'
  const m = Math.round((Date.now() - new Date(s)) / 60000)
  if (m < 2) return 'just now'
  if (m < 60) return `${m} min ago`
  if (m < 48 * 60) return `${Math.round(m / 60)} h ago`
  return `${Math.round(m / 1440)} days ago`
}
