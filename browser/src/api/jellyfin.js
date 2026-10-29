// Jellyfin, through the page's own server (/jellyfin, server/web/nginx.conf): the calls the
// Flutter app's JellyfinClient makes (lib/api/jellyfin.dart), for the browser. Items stay as
// Jellyfin sends them; src/lib/item.js reads them.
import { groupOf, isEpisode, isSeason, isSeries, isUniverse, providerIds, storyPlace } from '../lib/item.js'

export const VERSION = '1.0.0'
export const server = `${location.origin}/jellyfin`

/** Who's signed in (set by state/session.js). */
export const auth = { deviceId: '', userId: '', userName: '', token: '' }

export class JellyfinError extends Error {
  constructor(message, status) {
    super(message)
    this.status = status
  }
}

/** Called when the server says the sign-in is no longer valid. */
export const onSignedOut = { fn: null }

const FIELDS = 'Overview,Genres,ProviderIds,PrimaryImageAspectRatio,ChildCount,Taglines,MediaSourceCount,DateCreated,Width,Tags,ImageBlurHashes'
const IMAGES = 'Primary,Backdrop,Logo,Thumb'

function authHeader() {
  let a = `MediaBrowser Client="Hevyfin", Device="Web", DeviceId="${auth.deviceId}", Version="${VERSION}"`
  if (auth.token) a += `, Token="${auth.token}"`
  return a
}

export function url(path, query = {}) {
  const u = new URL(server + path)
  for (const [k, v] of Object.entries(query)) if (v !== null && v !== undefined && v !== '') u.searchParams.set(k, String(v))
  return u.toString()
}

// The same GET asked for twice at once is fetched once.
const inflight = new Map()

async function send(method, path, { query, body, timeout = 20000, keepalive = false } = {}) {
  const target = url(path, query)
  const key = method === 'GET' ? target : null
  if (key && inflight.has(key)) return inflight.get(key)
  const job = (async () => {
    const ctl = new AbortController()
    const timer = setTimeout(() => ctl.abort(), timeout)
    try {
      const r = await fetch(target, {
        method,
        headers: { Authorization: authHeader(), Accept: 'application/json', ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}) },
        body: body !== undefined ? JSON.stringify(body) : undefined,
        signal: ctl.signal,
        keepalive,
      })
      if (r.status === 401) {
        if (auth.token) onSignedOut.fn?.()
        throw new JellyfinError('Signed out by the server. Sign in again.', 401)
      }
      if (!r.ok) throw new JellyfinError(`Jellyfin error ${r.status}`, r.status)
      const text = await r.text()
      return text ? JSON.parse(text) : null
    } catch (e) {
      if (e.name === 'AbortError') throw new JellyfinError('The server took too long to answer')
      throw e
    } finally {
      clearTimeout(timer)
    }
  })()
  if (key) {
    inflight.set(key, job)
    job.finally(() => inflight.delete(key)).catch(() => {})
  }
  return job
}

export const get = (path, query) => send('GET', path, { query })
export const post = (path, { query, body = {}, timeout, keepalive } = {}) => send('POST', path, { query, body, timeout, keepalive })
export const del = (path, query, keepalive = false) => send('DELETE', path, { query, keepalive })
const list = (j) => (Array.isArray(j) ? j : j?.Items || [])

// A few minutes' memory for what many pages ask for.
const memo = new Map()
async function remember(key, ms, load) {
  const hit = memo.get(key)
  if (hit && Date.now() - hit.at < ms) return hit.value
  const value = await load()
  memo.set(key, { at: Date.now(), value })
  return value
}
/** After watching or changing lists: forget what may now be out of date. */
export const forget = () => memo.clear()

// ---- auth ----

export async function login(username, password) {
  try {
    const j = await send('POST', '/Users/AuthenticateByName', { body: { Username: username, Pw: password }, timeout: 10000 })
    return { userId: j.User.Id, userName: j.User.Name, token: j.AccessToken }
  } catch (e) {
    if (e.status === 401) throw new JellyfinError('Wrong username or password', 401)
    throw e
  }
}

export async function logout() {
  try {
    await post('/Sessions/Logout')
  } catch {}
}

/** Approve a Quick Connect code shown on another device (a TV) for this account. */
export async function quickConnectApprove(code) {
  try {
    await post('/QuickConnect/Authorize', { query: { code: code.trim().toUpperCase(), userId: auth.userId } })
  } catch (e) {
    if (e.status === 404 || e.status === 400) throw new JellyfinError('That code is not valid or has expired')
    throw e
  }
}

// ---- browsing ----

export async function items({
  types = ['Movie', 'Series'], genre, sortBy = 'SortName', sortOrder = 'Ascending', filters, search, limit, startIndex,
  parentId, recursive = true, personIds, ids, fields = FIELDS,
} = {}) {
  return list(
    await get('/Items', {
      userId: auth.userId, recursive, includeItemTypes: types.join(','), genres: genre, sortBy, sortOrder, filters,
      searchTerm: search, limit, startIndex, parentId, personIds, ids, fields, enableImageTypes: IMAGES, imageTypeLimit: 1,
    }),
  )
}

export const item = (id) => get(`/Items/${id}`, { userId: auth.userId })

export async function resume(limit = 20) {
  return list(await get('/UserItems/Resume', { userId: auth.userId, limit, mediaTypes: 'Video', fields: FIELDS, enableImageTypes: IMAGES }))
}

export async function nextUp({ limit = 20, seriesId } = {}) {
  return list(await get('/Shows/NextUp', { userId: auth.userId, limit, seriesId, fields: FIELDS, enableResumable: false, enableRewatching: false }))
}

/** Newest additions; series are grouped so a new episode bumps its show. */
export async function latest(type, limit = 24) {
  return list(await get('/Items/Latest', { userId: auth.userId, includeItemTypes: type, limit, fields: FIELDS }))
}

export async function similar(id, limit = 20) {
  return list(await get(`/Items/${id}/Similar`, { userId: auth.userId, limit, fields: FIELDS }))
}

/** Movies and episodes watched most recently, newest first. */
export const recentlyWatched = (limit = 30) =>
  items({ types: ['Movie', 'Episode'], filters: 'IsPlayed', sortBy: 'DatePlayed', sortOrder: 'Descending', limit })

export async function genres(types = ['Movie', 'Series']) {
  return remember(`genres:${types}`, 10 * 60e3, async () =>
    list(await get('/Genres', { userId: auth.userId, recursive: true, includeItemTypes: types.join(','), sortBy: 'SortName' })).map((g) => ({ id: g.Id, name: g.Name })),
  )
}

export async function seasons(seriesId) {
  return list(await get(`/Shows/${seriesId}/Seasons`, { userId: auth.userId, fields: 'ChildCount,ImageBlurHashes' }))
}

export async function episodes(seriesId, seasonId) {
  return list(await get(`/Shows/${seriesId}/Episodes`, { userId: auth.userId, seasonId, fields: 'Overview,ProviderIds,ImageBlurHashes' }))
}

/** The episode after this one in the same show, if any. */
export async function nextEpisode(episode) {
  const all = list(await get(`/Shows/${episode.SeriesId}/Episodes`, { userId: auth.userId, startItemId: episode.Id, limit: 2 }))
  return all.length > 1 ? all[1] : null
}

/** Every film and series (with tags and genres), kept for a few minutes. */
export function everything() {
  return remember('everything', 5 * 60e3, async () =>
    list(
      await get('/Items', {
        userId: auth.userId, recursive: true, includeItemTypes: 'Movie,Series', collapseBoxSetItems: false,
        fields: FIELDS + ',OfficialRating', enableImageTypes: IMAGES, imageTypeLimit: 1,
      }),
    ),
  )
}

/** These items, in this order (missing ones left out). */
export async function itemsByIds(ids) {
  if (!ids.length) return []
  const got = list(await get('/Items', { userId: auth.userId, ids: ids.join(','), fields: FIELDS, enableImageTypes: IMAGES }))
  const by = Object.fromEntries(got.map((i) => [i.Id, i]))
  return ids.map((id) => by[id]).filter(Boolean)
}

export const setFavorite = (id, on) =>
  on ? post(`/UserFavoriteItems/${id}`, { query: { userId: auth.userId } }) : del(`/UserFavoriteItems/${id}`, { userId: auth.userId })
export const setPlayed = (id, on) =>
  on ? post(`/UserPlayedItems/${id}`, { query: { userId: auth.userId } }) : del(`/UserPlayedItems/${id}`, { userId: auth.userId })

// ---- collections and universes ----

/** Franchise collections: TMDb's "… Collection" ones and those tagged "franchise" (first). */
export function collections() {
  return remember('collections', 30 * 60e3, async () => {
    const all = (await items({ types: ['BoxSet'] })).filter((b) => b.Name.endsWith('Collection') || isUniverse(b))
    return [...all.filter(isUniverse), ...all.filter((b) => !isUniverse(b))]
  })
}

/** A collection's films (and series) by release, or in story order if [story]. */
export async function collectionItems(id, { story = false, name } = {}) {
  const films = list(
    await get('/Items', {
      userId: auth.userId, parentId: id, includeItemTypes: 'Movie,Series', sortBy: 'PremiereDate,ProductionYear,SortName',
      fields: FIELDS, enableImageTypes: IMAGES, imageTypeLimit: 1,
    }),
  )
  if (story && name) {
    // A stable sort: titles without a place keep their release order at the end.
    return films.map((f, n) => [storyPlace(f, name) ?? 9999, n, f]).sort((a, b) => a[0] - b[0] || a[1] - b[1]).map((x) => x[2])
  }
  return films
}

/** Every collection a film or series is in: its own franchise first, then any universe. */
export async function collectionsOf(id) {
  const owners = await remember('owners', 30 * 60e3, async () => {
    const all = await collections()
    const lists = await Promise.all(all.map((b) => items({ parentId: b.Id, limit: 100, fields: "Tags" })))
    const out = {}
    all.forEach((b, n) => lists[n].forEach((m) => (out[m.Id] ||= []).push(b)))
    for (const l of Object.values(out)) l.sort((a, b) => (isUniverse(a) ? 1 : 0) - (isUniverse(b) ? 1 : 0))
    return out
  })
  return owners[id] || []
}

/**
 * [box]'s path as stops, in story order, or by release unless [story]. The universe job can
 * spread a show over the story (a season, a cut of episodes, each its own stop); a collection
 * without its list, and titles it doesn't list (yet), get a stop per title.
 */
export async function universeStops(box, films, { story = false } = {}) {
  let entries = null
  try {
    entries = JSON.parse(providerIds(box).hevyfinstory || '').filter((s) => s && typeof s === 'object')
  } catch {}
  if (!entries?.length) return films.map((f) => makeStop(f, { group: groupOf(f, box.Name) }))
  const byId = Object.fromEntries(films.map((f) => [f.Id, f]))
  // The seasons' and cuts' episodes and their seasons (for their posters), in one go each.
  const parts = {}
  const want = [...new Set(entries.filter((s) => s.series).flatMap((s) => s.ids || []))]
  if (want.length) {
    const eps = list(await get('/Items', { userId: auth.userId, ids: want.join(','), fields: FIELDS }))
    const ss = [...new Set(eps.map((e) => e.SeasonId).filter(Boolean))]
    const seasonItems = ss.length ? list(await get('/Items', { userId: auth.userId, ids: ss.join(',') })) : []
    for (const i of [...eps, ...seasonItems]) parts[i.Id] = i
  }
  const stops = [], seen = new Set()
  for (const s of entries) {
    const ids = s.ids || []
    const it = byId[s.series ?? ids[0]]
    if (!it) continue
    seen.add(it.Id)
    const date = s.date ? new Date(s.date) : null
    const group = s.group ?? groupOf(it, box.Name)
    if (!s.series) {
      stops.push(makeStop(it, { group, date, box: box.Id, previously: s.previously }))
      continue
    }
    const eps = ids.map((id) => parts[id]).filter(Boolean)
    if (!eps.length) continue
    stops.push(
      makeStop(it, {
        parts: eps, season: s.kind === 'season' ? parts[eps[0].SeasonId] : null,
        art: s.art && typeof s.art.id === 'string' ? { id: s.art.id, tag: s.art.tag ?? null } : null,
        title: s.title, code: String(s.code ?? ''), group, date, mini: s.mini === true, box: box.Id, previously: s.previously,
      }),
    )
  }
  for (const f of films) if (!seen.has(f.Id)) stops.push(makeStop(f, { group: groupOf(f, box.Name) }))
  if (!story) {
    const t = (s) => s.date?.getTime() ?? 253402214400000
    return stops.map((s, n) => [s, n]).sort((a, b) => t(a[0]) - t(b[0]) || a[1] - b[1]).map((x) => x[0])
  }
  return stops
}

/** A stop on a universe's path; see the Flutter Stop class. */
export function makeStop(it, { parts, season = null, art = null, title, code = null, group = null, date, mini = false, box = null, previously = null } = {}) {
  return {
    item: it, parts: parts || [it], season, art, title: title || it.Name, code, group,
    date: date ?? (it.PremiereDate ? new Date(it.PremiereDate) : null), mini, box, previously: previously || null,
  }
}

export const isPart = (s) => s.code !== null && s.code !== undefined
export const stopPlayed = (s) => s.parts.every((p) => p.UserData?.Played)
/** A season's or cut's first episode still to watch, else its first. */
export const nextPart = (s) => s.parts.find((p) => !p.UserData?.Played) || s.parts[0]
/** Where a tap goes: the title's page (a season or cut: its season), on the path it's from. */
export const stopRoute = (s) => `/item/${isPart(s) ? s.parts[0].SeasonId || s.item.Id : s.item.Id}${s.box ? `?in=${s.box}` : ''}`

/**
 * [i] as a stop on the path of universe [boxId], opened from there: a film or show with its
 * stop ("Previously", and Play carrying on along the path); a season the path makes a mini
 * series as its show, narrowed to the stop's episodes, with the season's story and date.
 */
export async function onPath(i, boxId) {
  const box = await item(boxId)
  const stops = await universeStops(box, await collectionItems(boxId), { story: true })
  const stop = stops.find((s) => (isSeason(i) ? s.mini && s.parts[0].SeasonId === i.Id : !isPart(s) && s.item.Id === i.Id))
  if (!stop) return null
  if (!isSeason(i)) return { ...i, PathStop: stop }
  const show = await item(stop.item.Id), first = stop.parts[0]
  return {
    ...show, PathStop: stop, PremiereDate: first.PremiereDate, ProductionYear: first.ProductionYear,
    // A whole season has its own story; a cut of one keeps the show's.
    ...(stop.season && i.Overview ? { Overview: i.Overview } : {}),
  }
}

/** What follows [current] on the path of universe [boxId]; null when off it or at its end. */
export async function nextInUniverse(boxId, current, { story = false } = {}) {
  const box = await item(boxId)
  const stops = await universeStops(box, await collectionItems(boxId, { story, name: box.Name }), { story })
  const at = stops.findIndex((s) => s.parts.some((p) => p.Id === current.Id) || (!isPart(s) && s.item.Id === current.SeriesId))
  if (at < 0) return null
  const here = stops[at]
  if (isPart(here)) {
    const n = here.parts.findIndex((p) => p.Id === current.Id)
    if (n + 1 < here.parts.length) return here.parts[n + 1]
  } else if (isEpisode(current)) {
    const n = await nextEpisode(current)
    if (n) return n
  }
  const next = stops[at + 1]
  if (!next) return null
  if (isPart(next)) return nextPart(next)
  if (!isSeries(next.item)) return next.item
  return (await nextUp({ seriesId: next.item.Id, limit: 1 }))[0] || (await episodes(next.item.Id)).find((e) => (e.ParentIndexNumber ?? 0) > 0) || null
}

/** The film after [movie] in its own franchise (in story order if chosen), if any. */
export async function nextInCollection(movie, storyOrder = []) {
  const b = (await collectionsOf(movie.Id))[0]
  if (!b) return null
  const films = await collectionItems(b.Id, { story: storyOrder.includes(b.Id), name: b.Name })
  const n = films.findIndex((m) => m.Id === movie.Id)
  return n >= 0 && n + 1 < films.length ? films[n + 1] : null
}

// ---- images ----

export function img(id, type, { tag, width, index = 0, quality = 90 } = {}) {
  const path = type === 'Backdrop' ? `/Items/${id}/Images/Backdrop/${index}` : `/Items/${id}/Images/${type}`
  return url(path, { tag, maxWidth: width ? Math.round(width) : undefined, quality })
}

/** Portrait poster; an episode shows its series' poster. */
export function poster(i, width = 300) {
  if (isEpisode(i) && i.SeriesPrimaryImageTag) return img(i.SeriesId, 'Primary', { tag: i.SeriesPrimaryImageTag, width })
  if (isSeason(i) && !i.ImageTags?.Primary && i.SeriesId) return img(i.SeriesId, 'Primary', { width })
  const tag = i?.ImageTags?.Primary
  return tag ? img(i.Id, 'Primary', { tag, width }) : null
}

/** A stop's poster: a cut's own ("Box" image on its first episode), a season's, else its title's. */
export function stopPoster(s, width = 300) {
  if (s.art) return img(s.art.id, 'Box', { tag: s.art.tag, width })
  return poster(s.season || s.item, width)
}

/** Wide art: own backdrop, else the parent's (episodes, seasons). */
export function backdrop(i, width = 1920) {
  if (i?.BackdropImageTags?.length) return img(i.Id, 'Backdrop', { tag: i.BackdropImageTags[0], width })
  if (i?.ParentBackdropItemId && i.ParentBackdropImageTags?.length) return img(i.ParentBackdropItemId, 'Backdrop', { tag: i.ParentBackdropImageTags[0], width })
  return null
}

/** Landscape still: the episode frame, else thumb, else backdrop. */
export function thumb(i, width = 480) {
  if (isEpisode(i) && i.ImageTags?.Primary) return img(i.Id, 'Primary', { tag: i.ImageTags.Primary, width })
  if (i?.ImageTags?.Thumb) return img(i.Id, 'Thumb', { tag: i.ImageTags.Thumb, width })
  if (i?.ParentThumbItemId) return img(i.ParentThumbItemId, 'Thumb', { tag: i.ParentThumbImageTag, width })
  return backdrop(i, width)
}

export function logo(i, width = 600) {
  if (i?.ImageTags?.Logo) return img(i.Id, 'Logo', { tag: i.ImageTags.Logo, width })
  if (i?.ParentLogoItemId) return img(i.ParentLogoItemId, 'Logo', { tag: i.ParentLogoImageTag, width })
  return null
}

export const personImage = (p, width = 200) => (p.PrimaryImageTag ? img(p.Id, 'Primary', { tag: p.PrimaryImageTag, width }) : null)

/** The BlurHash Jellyfin keeps for an image, for a placeholder while it loads. */
export function blurHash(i, type = 'Primary') {
  const tag = type === 'Backdrop' ? i?.BackdropImageTags?.[0] : i?.ImageTags?.[type]
  return (tag && i?.ImageBlurHashes?.[type]?.[tag]) || null
}

// ---- small settings shared by all of a user's Hevyfin devices ----

async function sharedPrefs() {
  return (await get('/DisplayPreferences/hevyfin-shared', { userId: auth.userId, client: 'hevyfin' })) || {}
}

/** Audio and subtitle language chosen per show, on every device: {seriesId: {a, s}}. */
export async function showTracks() {
  try {
    return JSON.parse((await sharedPrefs()).CustomPrefs?.showTracks || '{}')
  } catch {
    return {}
  }
}

export async function saveShowTrack(seriesId, { audio, subtitle } = {}) {
  const j = await sharedPrefs()
  const prefs = { ...(j.CustomPrefs || {}) }
  let all = {}
  try {
    all = JSON.parse(prefs.showTracks || '{}')
  } catch {}
  all[seriesId] = { ...(all[seriesId] || {}), ...(audio !== undefined ? { a: audio } : {}), ...(subtitle !== undefined ? { s: subtitle } : {}) }
  prefs.showTracks = JSON.stringify(all)
  await post('/DisplayPreferences/hevyfin-shared', {
    query: { userId: auth.userId, client: 'hevyfin' },
    body: { ...j, Id: 'hevyfin-shared', Client: 'hevyfin', CustomPrefs: prefs },
  })
}

// ---- playback ----

export async function playbackInfo(id, { profile, maxBitrate, audioIndex, subtitleIndex, transcode = false }) {
  const j = await post(`/Items/${id}/PlaybackInfo`, {
    query: { userId: auth.userId },
    body: {
      UserId: auth.userId,
      MaxStreamingBitrate: maxBitrate || 1e9,
      ...(audioIndex != null ? { AudioStreamIndex: audioIndex } : {}),
      // Never let the server pick a subtitle by itself: it would burn it in.
      SubtitleStreamIndex: subtitleIndex ?? -1,
      ...(transcode ? { EnableDirectPlay: false } : {}),
      // A browser can't play a remuxed file; "direct stream" for it is the server's HLS
      // with the picture copied, which the transcoding profile allows.
      EnableDirectStream: false,
      DeviceProfile: profile,
    },
  })
  return { playSessionId: j.PlaySessionId || '', source: j.MediaSources[0] }
}

/** Plays the file as it is, or comes as the server's HLS (picture copied when it can be). */
export const isTranscode = (info) => !info.source.SupportsDirectPlay && !info.source.SupportsDirectStream && !!info.source.TranscodingUrl

export function streamUrl(id, info) {
  if (isTranscode(info)) return server + info.source.TranscodingUrl
  return url(`/Videos/${id}/stream`, { static: true, mediaSourceId: info.source.Id, ApiKey: auth.token, PlaySessionId: info.playSessionId })
}

/** Every text subtitle as WebVTT (the server converts SRT and ASS). */
export const subtitleUrl = (id, info, index) => url(`/Videos/${id}/${info.source.Id}/Subtitles/${index}/0/Stream.vtt`, { ApiKey: auth.token })

function progressBody(id, info, secs, paused) {
  return {
    ItemId: id, MediaSourceId: info.source.Id, PlaySessionId: info.playSessionId, PositionTicks: Math.round(secs * 1e7),
    IsPaused: paused, CanSeek: true, PlayMethod: isTranscode(info) ? 'Transcode' : 'DirectPlay',
  }
}
export const reportStart = (id, info, secs) => post('/Sessions/Playing', { body: progressBody(id, info, secs, false) })
export const reportProgress = (id, info, secs, paused) => post('/Sessions/Playing/Progress', { body: progressBody(id, info, secs, paused) })

/** [keepalive]: the page is closing, and the report still has to get there. */
export async function reportStop(id, info, secs, keepalive = false) {
  await post('/Sessions/Playing/Stopped', { body: progressBody(id, info, secs, false), keepalive })
  await endTranscode(info, keepalive)
}

/** Stop the server's transcode for a play session (also one never reported). */
export async function endTranscode(info, keepalive = false) {
  if (!isTranscode(info)) return
  try {
    await del('/Videos/ActiveEncodings', { deviceId: auth.deviceId, playSessionId: info.playSessionId }, keepalive)
  } catch {}
}

/** Scrub previews: frames every [interval] ms, packed in tiles of cols x rows. */
export async function trickplay(id, mediaSourceId) {
  try {
    const j = list(await get('/Items', { userId: auth.userId, ids: id, fields: 'Trickplay' }))[0]?.Trickplay || {}
    const bySource = j[mediaSourceId] || Object.values(j)[0]
    if (!bySource || !Object.keys(bySource).length) return null
    const w = Math.min(...Object.keys(bySource).map(Number))
    const t = bySource[w]
    return {
      width: t.Width, height: t.Height, cols: t.TileWidth, rows: t.TileHeight, count: t.ThumbnailCount, interval: t.Interval,
      url: (tile) => url(`/Videos/${id}/Trickplay/${w}/${tile}.jpg`, { mediaSourceId, ApiKey: auth.token }),
    }
  } catch {
    return null
  }
}

/** Intro, Recap and Outro segments, in seconds. */
export async function segments(id) {
  try {
    return list(await get(`/MediaSegments/${id}`)).map((s) => ({ type: s.Type, start: s.StartTicks / 1e7, end: s.EndTicks / 1e7 }))
  } catch {
    return []
  }
}

/** The video id of a title's trailer saved on the server (hidden Cinema library), if any. */
export async function libraryTrailer(i) {
  const tmdb = providerIds(i).tmdb
  if (!tmdb) return null
  const byName = await remember('trailers', 10 * 60e3, async () => {
    const all = list(await get('/Items', { userId: auth.userId, recursive: true, includeItemTypes: 'Video', fields: 'Path', enableImages: false }))
    const out = {}
    for (const v of all) if ((v.Path || '').includes('/Cinema/Library/')) out[v.Path.split('/').pop().split('.')[0]] = v.Id
    return out
  })
  return byName[`${isSeries(i) ? 'tv' : 'movie'}-${tmdb}`] || null
}
