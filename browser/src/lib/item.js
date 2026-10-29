// A Jellyfin item (BaseItemDto) is kept as it comes; these read it the way the Flutter app's
// Item class does (lib/api/jellyfin.dart). Times are in seconds.

export const TICKS = 1e7

export const isMovie = (i) => i?.Type === 'Movie'
export const isSeries = (i) => i?.Type === 'Series'
export const isEpisode = (i) => i?.Type === 'Episode'
export const isSeason = (i) => i?.Type === 'Season'
export const isCollection = (i) => i?.Type === 'BoxSet'

/** Collections made by hand or by a server script (a whole universe, a franchise) carry this tag. */
export const isUniverse = (i) => isCollection(i) && (i.Tags || []).includes('franchise')

/** What a card shows: the series for an episode, otherwise the item itself. */
export const displayTitle = (i) => (isEpisode(i) ? i.SeriesName || i.Name : i.Name) || ''

/** "S2:E5" for episodes. */
export const episodeCode = (i) => `S${i.ParentIndexNumber ?? '?'}:E${i.IndexNumber ?? '?'}`

/** Length in seconds; an unknown length (not yet aired, say) comes as 0 and reads as null. */
export const runtime = (i) => (i?.RunTimeTicks > 0 ? i.RunTimeTicks / TICKS : null)

const userData = (i) => i?.UserData || {}
export const played = (i) => userData(i).Played === true
export const favorite = (i) => userData(i).IsFavorite === true
export const resumeAt = (i) => (userData(i).PlaybackPositionTicks || 0) / TICKS
export const lastPlayed = (i) => (userData(i).LastPlayedDate ? new Date(userData(i).LastPlayedDate) : null)
export const unplayedCount = (i) => userData(i).UnplayedItemCount

/** Progress 0..1 for a resume bar, null when not started. */
export function progress(i) {
  const p = userData(i).PlayedPercentage
  if (p > 0) return Math.min(1, p / 100)
  const r = runtime(i), at = resumeAt(i)
  if (!r || !at) return null
  return Math.min(1, at / r)
}

/** Provider ids with lower-case keys (Tmdb, tmdb and TMDB all read as tmdb). */
export function providerIds(i) {
  const out = {}
  for (const [k, v] of Object.entries(i?.ProviderIds || {})) out[k.toLowerCase()] = String(v)
  return out
}
export const tmdbId = (i) => Number(providerIds(i).tmdb) || null

export const tagline = (i) => (i?.Taglines || [])[0] || null
export const year = (i) => i?.ProductionYear || null
export const premiere = (i) => (i?.PremiereDate ? new Date(i.PremiereDate) : null)

/** This title's place in a collection's story order (tags "story:COLLECTION:NN"). */
export function storyPlace(i, collection) {
  const prefix = `story:${collection}:`
  const t = (i?.Tags || []).find((t) => t.startsWith(prefix))
  return t ? Number(t.slice(prefix.length)) : null
}

/** Its chapter on a collection's path (tag "group:COLLECTION:chapter"). */
export function groupOf(i, collection) {
  const prefix = `group:${collection}:`
  const t = (i?.Tags || []).find((t) => t.startsWith(prefix))
  return t ? t.slice(prefix.length) : null
}

/** The trailer on YouTube, from TMDb (only on full item loads); "Official Trailer" first. */
export function remoteTrailer(i) {
  const yt = (i?.RemoteTrailers || []).filter((t) => String(t.Url).includes('youtu'))
  const official = (t) => (String(t.Name).toLowerCase().includes('official trailer') ? 0 : 1)
  return yt.sort((a, b) => official(a) - official(b))[0]?.Url || null
}

/** The streams of the item's first media source (or its own list). */
export const streams = (i) => i?.MediaSources?.[0]?.MediaStreams || i?.MediaStreams || []

/** "4K", "HD" or "SD" from the video width. */
export function quality(i) {
  const w = streams(i).find((s) => s.Type === 'Video')?.Width ?? i?.Width
  if (!w) return null
  return w >= 3200 ? '4K' : w >= 1200 ? 'HD' : 'SD'
}

/** Bonus scenes in a film's credits (the universe job's "HevyfinScenes"), seconds. */
export function scenesOf(i) {
  try {
    const m = JSON.parse(providerIds(i).hevyfinscenes || '')
    const scenes = (m.scenes || []).map((x) => ({ start: x.start, end: x.end, kind: String(x.kind), spoiler: x.spoiler === true }))
    return scenes.length ? { credits: m.credits, scenes } : null
  } catch {
    return null
  }
}

/** "1h 52m", "48m". */
export function duration(secs) {
  if (!secs) return ''
  const m = Math.round(secs / 60)
  return m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m}m`
}

/** 1:02:03 or 2:03, for the player. */
export function clock(secs) {
  secs = Math.max(0, Math.floor(secs || 0))
  const h = Math.floor(secs / 3600), m = Math.floor((secs % 3600) / 60), s = secs % 60
  return (h ? `${h}:${String(m).padStart(2, '0')}` : `${m}`) + `:${String(s).padStart(2, '0')}`
}

/** Audio/subtitle language codes that mean the same (ISO 639-2 and -1). */
export function langs(iso3) {
  return (
    { eng: 'eng,en', dut: 'dut,nld,nl', nld: 'dut,nld,nl', fre: 'fre,fra,fr', fra: 'fre,fra,fr', ger: 'ger,deu,de', deu: 'ger,deu,de', spa: 'spa,es', jpn: 'jpn,ja' }[iso3] ||
    iso3
  ).split(',')
}
export const langMatches = (lang, want) => !!lang && !!want && langs(want).includes(lang.toLowerCase())
