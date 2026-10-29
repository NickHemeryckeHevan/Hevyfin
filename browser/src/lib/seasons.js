// Home rows for a time of year, from the library's genres and TMDb keywords (port of
// lib/state/seasons.dart): Halloween all October, Christmas 1–26 December, Valentine's 1–14
// February, summer blockbusters in July and August.
const words = (i) => [...(i.Tags || []), ...(i.Genres || []), i.Name].join(' | ').toLowerCase()
const scary = (i) => (i.Genres || []).includes('Horror') || /horror|halloween|slasher/.test(words(i))
const SPOOKY = ['witch', 'ghost', 'vampire', 'werewolf', 'monster', 'haunted', 'wizard', 'zombie', 'skeleton', 'spooky', 'supernatural']

export function seasonalRows(d = new Date()) {
  const m = d.getMonth() + 1, day = d.getDate()
  if (m === 10)
    return [
      { title: 'Halloween Frights', subtitle: 'Lights off:', pick: scary },
      { title: 'Spooky, Not Scary', subtitle: 'For the whole family:', pick: (i) => !scary(i) && SPOOKY.some((w) => words(i).includes(w)) },
    ]
  if (m === 12 && day <= 26) return [{ title: 'Christmas Movies', subtitle: 'Cosy up:', pick: (i) => /christmas|xmas/.test(words(i)) }]
  if (m === 2 && day <= 14) return [{ title: "Valentine's Night", subtitle: 'Date night:', pick: (i) => (i.Genres || []).includes('Romance') || words(i).includes('valentine') }]
  if (m === 7 || m === 8)
    return [{ title: 'Summer Blockbusters', pick: (i) => i.Type === 'Movie' && ['Action', 'Adventure'].some((g) => (i.Genres || []).includes(g)) && (i.CommunityRating || 0) >= 7 }]
  return []
}

export const shuffle = (a) => {
  a = [...a]
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1))
    ;[a[i], a[j]] = [a[j], a[i]]
  }
  return a
}
