// The last Home rows, kept in this browser so Home opens onto them straight away while fresh
// ones load behind (port of lib/state/row_cache.dart).
import { auth } from '../api/jellyfin.js'

let rows = {}, user = '', timer

function load() {
  if (user === auth.userId) return
  user = auth.userId
  try {
    rows = JSON.parse(localStorage.getItem(`hevyfin.rows.${user}`) || '{}')
  } catch {
    rows = {}
  }
}

export function cached(key) {
  load()
  return rows[key] || null
}

export function keep(key, items) {
  load()
  rows[key] = items.slice(0, 30)
  clearTimeout(timer)
  timer = setTimeout(() => {
    try {
      localStorage.setItem(`hevyfin.rows.${user}`, JSON.stringify(rows))
    } catch {
      // Full: start over next time rather than keep stale rows.
      localStorage.removeItem(`hevyfin.rows.${user}`)
    }
  }, 2000)
}

/** Shows a row from the cache at once, then calls [set] again with the fresh one. */
export async function fresh(key, load, set) {
  const old = cached(key)
  if (old) set(old)
  const items = await load()
  keep(key, items)
  set(items)
  return items
}
