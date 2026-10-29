// Seerr, through the page's own server (/seerr): the browser keeps its session cookie, which
// goes along by itself (port of lib/api/seerr.dart). Signed in with the Jellyfin account.
import { ref } from 'vue'

const base = `${location.origin}/seerr/api/v1`

/** Seerr answers for this browser's sign-in. */
export const seerrReady = ref(false)

export class SeerrError extends Error {
  constructor(message, status) {
    super(message)
    this.status = status
  }
}

async function send(method, path, { query = {}, body } = {}) {
  // Seerr rejects '+' for spaces, so the query is encoded by hand.
  const q = Object.entries(query)
    .filter(([, v]) => v !== null && v !== undefined)
    .map(([k, v]) => `${k}=${encodeURIComponent(v)}`)
    .join('&')
  const r = await fetch(`${base}${path}${q ? `?${q}` : ''}`, {
    method,
    credentials: 'same-origin',
    headers: { Accept: 'application/json', ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}) },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  })
  if (r.status === 401 || r.status === 403) {
    if (!path.startsWith('/auth')) seerrReady.value = false
    throw new SeerrError(path.startsWith('/auth') ? 'Seerr did not accept the login' : 'Seerr session expired', r.status)
  }
  const text = await r.text()
  const data = text ? JSON.parse(text) : null
  if (!r.ok) throw new SeerrError(data?.message || `Seerr error ${r.status}`, r.status)
  return data
}

export async function login(username, password) {
  await send('POST', '/auth/jellyfin', { body: { username, password } })
  seerrReady.value = true
}

/** Ends this browser's Seerr session (one browser holds one sign-in for every profile). */
export async function logout() {
  seerrReady.value = false
  try {
    await send('POST', '/auth/logout', { body: {} })
  } catch {}
}

export async function check() {
  try {
    await send('GET', '/auth/me')
    seerrReady.value = true
  } catch {
    seerrReady.value = false
  }
  return seerrReady.value
}

// ---- reading what Seerr (TMDb) says about a title ----

export const image = (path, size = 'w342') => (path ? `https://image.tmdb.org/t/p/${size}${path}` : '')
export const mediaType = (m) => m.mediaType || (m.firstAirDate || m.name ? 'tv' : 'movie')
export const isTv = (m) => mediaType(m) === 'tv'
export const title = (m) => m.title || m.name || ''
export const year = (m) => Number(String(m.releaseDate || m.firstAirDate || '').split('-')[0]) || null
export const genreNames = (m) => (m.genres || []).map((g) => g.name)

/** Seerr's media status: 2 pending, 3 processing, 4 partly available, 5 available, 6 deleted. */
export const status = (m) => m.mediaInfo?.status || 1
export const statusLabel = (s) => ({ 2: 'Waiting for approval', 3: 'Downloading', 4: 'Partly available', 5: 'Available' })[s] || ''
export const requestable = (s) => s === 1 || s === 6 || s === 4
export const jellyfinId = (m) => m.mediaInfo?.jellyfinMediaId || null

/** The official trailer on YouTube (details only). */
export function trailerUrl(m) {
  const vids = (m.relatedVideos || []).filter((v) => v.site === 'YouTube' && v.type === 'Trailer')
  const official = (v) => (String(v.name).toLowerCase().includes('official') ? 0 : 1)
  return vids.sort((a, b) => official(a) - official(b))[0]?.url || null
}

/** Download progress 0..1 from Sonarr/Radarr, if something is downloading. */
export function downloadProgress(mediaInfo) {
  let size = 0, left = 0
  for (const d of mediaInfo?.downloadStatus || []) {
    size += d.size || 0
    left += d.sizeLeft || 0
  }
  return size > 0 ? Math.min(1, Math.max(0, (size - left) / size)) : null
}

/** Season numbers (TV only, specials left out). */
export const seasonNumbers = (m) => (m.seasons || []).map((s) => s.seasonNumber).filter((n) => n > 0)

/** Status per season; seasons someone already asked for count as requested. */
export function seasonStatus(m) {
  const out = {}
  for (const s of m.mediaInfo?.seasons || []) out[s.seasonNumber] = s.status
  for (const r of m.mediaInfo?.requests || []) {
    if (r.status === 3) continue // declined
    for (const s of r.seasons || []) out[s.seasonNumber] ??= 2
  }
  return out
}

const results = (j) => (j?.results || []).filter((m) => !m.mediaType || m.mediaType === 'movie' || m.mediaType === 'tv')

export const trending = (page = 1) => send('GET', '/discover/trending', { query: { page } }).then(results)
export const popularMovies = (page = 1, genre) => send('GET', '/discover/movies', { query: { page, genre } }).then(results)
export const popularTv = (page = 1, genre) => send('GET', '/discover/tv', { query: { page, genre } }).then(results)
export const upcomingMovies = (page = 1) => send('GET', '/discover/movies/upcoming', { query: { page } }).then(results)
export const upcomingTv = (page = 1) => send('GET', '/discover/tv/upcoming', { query: { page } }).then(results)
export const search = (query, page = 1) => send('GET', '/search', { query: { query, page } }).then(results)
export const recommendations = (type, tmdb) =>
  send('GET', `/${type}/${tmdb}/recommendations`).then((j) => results(j).map((m) => ({ ...m, mediaType: type })))
/** TMDb's genres for films ("movie") or shows ("tv"): [{id, name}]. */
export const genres = (type) => send('GET', `/genres/${type}`)
export const details = (type, tmdb) => send('GET', `/${type}/${tmdb}`).then((m) => ({ ...m, mediaType: type }))
export const person = (tmdb) => send('GET', `/person/${tmdb}`)

/** Acting credits first, then directing, writing and producing ("Self" appearances left out). */
export async function personCredits(tmdb) {
  const j = await send('GET', `/person/${tmdb}/combined_credits`)
  const seen = new Set(), out = []
  for (const m of j.cast || []) {
    if (m.mediaType !== 'movie' && m.mediaType !== 'tv') continue
    if (m.character && /^(self|himself|herself|themselves)\b/i.test(m.character)) continue
    if (!seen.has(m.mediaType + m.id)) seen.add(m.mediaType + m.id), out.push({ media: m, role: m.character, episodes: m.episodeCount })
  }
  const jobs = new Set(['Director', 'Screenplay', 'Writer', 'Creator', 'Producer', 'Executive Producer'])
  for (const m of j.crew || []) {
    if ((m.mediaType !== 'movie' && m.mediaType !== 'tv') || !jobs.has(m.job)) continue
    if (!seen.has(m.mediaType + m.id)) seen.add(m.mediaType + m.id), out.push({ media: m, role: m.job, episodes: null })
  }
  return out
}

/** IMDb and Rotten Tomatoes scores, where Seerr has them. */
export async function ratings(type, tmdb) {
  try {
    if (type === 'movie') {
      const j = await send('GET', `/movie/${tmdb}/ratingscombined`)
      return { imdb: j.imdb?.criticsScore ?? null, imdbUrl: j.imdb?.url, critics: j.rt?.criticsScore ?? null, audience: j.rt?.audienceScore ?? null }
    }
    const rt = await send('GET', `/tv/${tmdb}/ratings`)
    return { critics: rt.criticsScore ?? null, audience: rt.audienceScore ?? null }
  } catch {
    return {}
  }
}

export async function myRequests(take = 40) {
  const me = (await send('GET', '/auth/me')).id
  const j = await send('GET', '/request', { query: { take, skip: 0, sort: 'added', requestedBy: me, filter: 'all' } })
  return j.results || []
}

/** How a request is getting on, in words. */
export function requestLabel(r) {
  if (r.status === 3) return 'Declined'
  if (r.status === 4) return 'Failed'
  if (r.media?.status === 5) return 'Available'
  if (downloadProgress(r.media) !== null) return 'Downloading'
  if (r.media?.status === 4) return 'Partly available'
  if (r.status === 1) return 'Awaiting approval'
  return 'Requested'
}

/** Ask for a film, or seasons of a show. True when it went straight through (no approval wait). */
export async function request(m, seasons) {
  const r = await send('POST', '/request', {
    body: { mediaType: mediaType(m), mediaId: m.id, ...(isTv(m) ? { seasons: seasons || seasonNumbers(m) } : {}) },
  })
  return !(r && r.status === 1)
}
