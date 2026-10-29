// What "Play" starts (port of playTarget/playItem in lib/ui/widgets/billboard.dart).
import * as jf from '../api/jellyfin.js'
import { isCollection, isSeries } from './item.js'
import { prefs } from '../state/session.js'

/** A film itself; a show's half-watched episode, then its next one, then its first; a
 *  universe's first stop not watched yet; a mini series' next episode. */
export async function playTarget(item) {
  const mini = item.PathStop?.mini ? item.PathStop : null
  if (mini) return jf.nextPart(mini)
  if (isCollection(item)) {
    const story = prefs.storyOrder.includes(item.Id)
    const stops = await jf.universeStops(item, await jf.collectionItems(item.Id, { story, name: item.Name }), { story })
    const stop = stops.find((s) => !jf.stopPlayed(s)) || stops[0]
    if (!stop) return null
    if (jf.isPart(stop)) return jf.nextPart(stop)
    return isSeries(stop.item) ? playTarget(stop.item) : stop.item
  }
  if (!isSeries(item)) return item
  return (
    (await jf.resume(50)).find((e) => e.SeriesId === item.Id) ||
    (await jf.nextUp({ seriesId: item.Id, limit: 1 }))[0] ||
    (await jf.episodes(item.Id)).find((e) => (e.ParentIndexNumber ?? 0) > 0) ||
    null
  )
}

/** The player's address for [item]: carrying on along a universe's path when opened from one. */
export async function playRoute(item) {
  const box = item.PathStop?.box
  const target = await playTarget(item)
  if (!target) return null
  return `/play/${target.Id}${box ? `?in=${box}` : ''}`
}
