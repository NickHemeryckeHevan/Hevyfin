// What a collection's page shows, worked out from its titles and its path (port of the _Data
// class in lib/ui/pages/collection.dart). Times are in seconds.
import * as jf from '../api/jellyfin.js'
import { played, resumeAt, runtime } from './item.js'

/** The collection's titles (with their people, for the faces) and its path of stops. */
export async function loadCollection(box, story) {
  const films = await jf.collectionItems(box.Id, { story, name: box.Name })
  const full = await jf.get('/Items', {
    userId: jf.auth.userId, parentId: box.Id, includeItemTypes: 'Movie,Series',
    fields: 'People,Genres,CommunityRating,CriticRating,RunTimeTicks,ProductionYear',
  })
  const byId = Object.fromEntries((full?.Items || []).map((i) => [i.Id, i]))
  for (const f of films) if (byId[f.Id]) Object.assign(f, { People: byId[f.Id].People, CriticRating: byId[f.Id].CriticRating })
  const stops = await jf.universeStops(box, films, { story })
  return { box, films, stops }
}

const sum = (l, f) => l.reduce((s, x) => s + f(x), 0)
export const stopRuntime = (s) => sum(s.parts, (p) => runtime(p) || 0)
export const stopLeft = (s) => sum(s.parts.filter((p) => !played(p)), (p) => (runtime(p) || 0) - resumeAt(p))
export const stopResume = (s) => sum(s.parts.filter((p) => !played(p)), resumeAt)

export function stats(d) {
  const years = d.films.map((f) => f.ProductionYear).filter(Boolean).sort((a, b) => a - b)
  const scores = d.films.map((f) => f.CriticRating ?? (f.CommunityRating ? f.CommunityRating * 10 : null)).filter((x) => x !== null && x !== undefined)
  const genreCount = {}
  for (const f of d.films) for (const g of f.Genres || []) genreCount[g] = (genreCount[g] || 0) + 1
  return {
    spread: d.stops.some(jf.isPart),
    watchedStops: d.stops.filter(jf.stopPlayed),
    stopsLeft: sum(d.stops, stopLeft),
    stopsTotal: sum(d.stops, stopRuntime),
    total: sum(d.films, (f) => runtime(f) || 0),
    watched: d.films.filter(played),
    left: sum(d.films.filter((f) => !played(f)), (f) => (runtime(f) || 0) - resumeAt(f)),
    years,
    score: scores.length ? Math.round(scores.reduce((a, b) => a + b) / scores.length) : null,
    genres: Object.entries(genreCount).sort((a, b) => b[1] - a[1]).slice(0, 6).map((e) => e[0]),
    faces: faces(d.films),
    groups: new Set(d.stops.map((s) => s.group).filter(Boolean)).size,
  }
}

/** Actors in more than one title, the most frequent first, with the part they play most. */
function faces(films) {
  const count = {}, who = {}, roles = {}
  for (const f of films) {
    for (const p of (f.People || []).filter((p) => p.Type === 'Actor').slice(0, 12)) {
      count[p.Id] = (count[p.Id] || 0) + 1
      who[p.Id] ||= p
      const r = (p.Role || '').trim()
      if (r) (roles[p.Id] ||= {})[r] = (roles[p.Id][r] || 0) + 1
    }
  }
  return Object.entries(count)
    .filter(([, n]) => n > 1)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 18)
    .map(([id, n]) => ({ person: who[id], n, role: Object.entries(roles[id] || {}).sort((a, b) => b[1] - a[1])[0]?.[0] || null }))
}

/** "3h 20m". */
export function hours(secs) {
  const m = Math.round(secs / 60)
  if (m < 60) return `${m}m`
  return m % 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m / 60}h`
}

const WORDS = ['no', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve']
export const count = (n) => (n < 13 ? WORDS[n] : String(n))

/** A few things worth knowing, from the titles themselves. */
export function trivia(d, s) {
  const timed = d.films.filter((f) => runtime(f)).sort((a, b) => runtime(a) - runtime(b))
  const score = (f) => f.CriticRating ?? (f.CommunityRating ? f.CommunityRating * 10 : -1)
  const rated = d.films.filter((f) => score(f) >= 0).sort((a, b) => score(b) - score(a))
  const byYear = [...d.films].sort((a, b) => (a.ProductionYear || 0) - (b.ProductionYear || 0))
  const out = []
  if (byYear[0]?.ProductionYear) out.push(['🏁', `It started with ${byYear[0].Name} in ${byYear[0].ProductionYear}.`])
  const last = byYear.at(-1)
  if (last?.ProductionYear && last.Id !== byYear[0].Id) out.push(['✨', `The latest here is ${last.Name} (${last.ProductionYear}).`])
  if (timed.length > 1) out.push(['⏳', `${timed.at(-1).Name} is the longest at ${hours(runtime(timed.at(-1)))}; ${timed[0].Name} the shortest at ${hours(runtime(timed[0]))}.`])
  if (rated.length) out.push(['🏆', `${rated[0].Name} is the best reviewed${rated[0].CriticRating ? ` (${rated[0].CriticRating}% with critics)` : ''}.`])
  const h = Math.floor(s.total / 3600)
  out.push(h >= 24 ? ['🌙', `Back to back it runs ${Math.floor(h / 24)} day${Math.floor(h / 24) === 1 ? '' : 's'} and ${h % 24} hours, without sleep.`] : ['🛋️', `Back to back it runs ${hours(s.total)}: one long weekend on the sofa.`])
  return out
}

/** A custom design for a collection's page (provider id "HevyfinPage"), if it has one. */
export function pageDesign(box) {
  const raw = box?.ProviderIds?.HevyfinPage
  if (typeof raw !== 'string' || !raw) return null
  try {
    return JSON.parse(raw)
  } catch {
    return null
  }
}

export const accentOf = (page) => (/^#?[0-9a-f]{6}$/i.test(String(page?.accent || '')) ? '#' + String(page.accent).replace('#', '') : '#ff7a1a')
