import { beforeEach, describe, expect, it, vi } from 'vitest'
import * as jf from '../src/api/jellyfin.js'

// A small universe in the universe job's format (server/universes.py, "HevyfinStory"): a
// film, a show's season as a mini series, a cut of another season with its own poster, and a
// film the list doesn't mention yet.
const story = [
  { ids: ['m1'], title: 'Film One', date: '2010-05-01', group: 'Phase One' },
  { series: 's1', kind: 'season', ids: ['e1', 'e2'], title: 'Leviathan', code: 'Season 1', date: '2015-01-06', mini: true, previously: 'Earlier on…', group: 'TV' },
  { series: 's1', kind: 'cut', ids: ['e3'], title: 'The Cut', code: 'S2 · E1', date: '2005-02-01', art: { id: 'e3', tag: 'box' } },
]
const box = { Id: 'box', Name: 'Test Universe', Type: 'BoxSet', ProviderIds: { HevyfinStory: JSON.stringify(story) } }
const films = [
  { Id: 'm1', Name: 'Film One', Type: 'Movie', PremiereDate: '2010-05-01' },
  { Id: 's1', Name: 'Show', Type: 'Series', PremiereDate: '2004-01-01' },
  { Id: 'm2', Name: 'Film Two', Type: 'Movie', PremiereDate: '2020-01-01', Tags: ['group:Test Universe:Phase Two'] },
]
const items = {
  e1: { Id: 'e1', SeasonId: 'season1', Type: 'Episode', UserData: { Played: true } },
  e2: { Id: 'e2', SeasonId: 'season1', Type: 'Episode', UserData: { Played: false } },
  e3: { Id: 'e3', SeasonId: 'season2', Type: 'Episode' },
  season1: { Id: 'season1', Type: 'Season', Overview: 'Season one.' },
  season2: { Id: 'season2', Type: 'Season' },
}

beforeEach(() => {
  globalThis.fetch = vi.fn(async (url) => {
    const ids = new URL(url).searchParams.get('ids')?.split(',') || []
    return { ok: true, status: 200, text: async () => JSON.stringify({ Items: ids.map((i) => items[i]).filter(Boolean) }) }
  })
})

describe('universeStops', () => {
  it('in story order: the list as it goes, then titles it does not mention', async () => {
    const stops = await jf.universeStops(box, films, { story: true })
    expect(stops.map((s) => s.title)).toEqual(['Film One', 'Leviathan', 'The Cut', 'Film Two'])
    expect(stops[3].group).toBe('Phase Two') // from the title's own tag
  })

  it('by release: sorted by each stop’s date', async () => {
    const stops = await jf.universeStops(box, films, { story: false })
    expect(stops.map((s) => s.title)).toEqual(['The Cut', 'Film One', 'Leviathan', 'Film Two'])
  })

  it('a season stop is a mini series of its own episodes; a cut keeps its own poster', async () => {
    const [, season, cut] = await jf.universeStops(box, films, { story: true })
    expect(jf.isPart(season)).toBe(true)
    expect(season).toMatchObject({ mini: true, previously: 'Earlier on…', group: 'TV', box: 'box' })
    expect(season.season.Id).toBe('season1')
    expect(jf.nextPart(season).Id).toBe('e2') // the first one not watched
    expect(jf.stopPlayed(season)).toBe(false)
    expect(jf.stopRoute(season)).toBe('/item/season1?in=box')
    expect(cut.art).toEqual({ id: 'e3', tag: 'box' })
    expect(jf.stopPoster(cut)).toContain('/Items/e3/Images/Box?tag=box')
  })

  it('a collection without a list gets a stop per title', async () => {
    const plain = { ...box, ProviderIds: {} }
    const stops = await jf.universeStops(plain, films)
    expect(stops.map((s) => s.item.Id)).toEqual(['m1', 's1', 'm2'])
    expect(stops.every((s) => !jf.isPart(s))).toBe(true)
  })
})
