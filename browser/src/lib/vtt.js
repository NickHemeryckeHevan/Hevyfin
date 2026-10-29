// Subtitles as cues Hevyfin draws itself (the user's size, colour and box), from the WebVTT
// the server makes of every text subtitle (port of lib/ui/web_player.dart).

const TIME = /(?:(\d+):)?(\d{1,2}):(\d{2})[.,](\d{3})/

function seconds(s) {
  const m = TIME.exec(s)
  if (!m) return null
  return Number(m[1] || 0) * 3600 + Number(m[2]) * 60 + Number(m[3]) + Number(m[4]) / 1000
}

/** The cues of a WebVTT (or SRT) file, in order, with styling tags taken out. */
export function parseVtt(body) {
  const cues = []
  for (const block of body.replace(/\r\n?/g, '\n').split(/\n\s*\n/)) {
    const lines = block.split('\n').filter((l) => l.trim())
    const at = lines.findIndex((l) => l.includes('-->'))
    if (at < 0) continue
    const [a, b] = lines[at].split('-->')
    const start = seconds(a), end = seconds(b)
    if (start === null || end === null) continue
    const text = lines
      .slice(at + 1)
      .join('\n')
      .replace(/<[^>]*>/g, '')
      .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&nbsp;/g, ' ')
      .trim()
    if (text) cues.push({ start, end, text })
  }
  return cues.sort((x, y) => x.start - y.start)
}

export async function loadCues(url) {
  const r = await fetch(url)
  if (!r.ok) throw new Error(`Subtitles unavailable (${r.status})`)
  return parseVtt(await r.text())
}

/** The lines showing at [t] (cues may overlap). */
export function cuesAt(cues, t) {
  const out = []
  // Cues are sorted by start; a binary search finds the last that started.
  let lo = 0, hi = cues.length
  while (lo < hi) {
    const mid = (lo + hi) >> 1
    cues[mid].start <= t ? (lo = mid + 1) : (hi = mid)
  }
  for (let i = lo - 1; i >= 0 && i >= lo - 8; i--) if (cues[i].end > t) out.unshift(cues[i].text)
  return out
}
