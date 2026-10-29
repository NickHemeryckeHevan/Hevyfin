// Pictures at the size they're shown (srcset for sharp screens) and a BlurHash placeholder
// painted while they load.
import { decode } from 'blurhash'

const cache = new Map()

/** A tiny image of the BlurHash, as a data URL (made once per hash). */
export function blurUrl(hash, w = 32, h = 32) {
  if (!hash) return null
  const key = `${hash}|${w}x${h}`
  if (cache.has(key)) return cache.get(key)
  let out = null
  try {
    const pixels = decode(hash, w, h)
    const c = document.createElement('canvas')
    c.width = w
    c.height = h
    const ctx = c.getContext('2d')
    const data = ctx.createImageData(w, h)
    data.data.set(pixels)
    ctx.putImageData(data, 0, 0)
    out = c.toDataURL()
  } catch {}
  if (cache.size > 400) cache.clear()
  cache.set(key, out)
  return out
}

/** "url 1x, url2 2x" from an image URL builder taking a width. */
export const srcset = (make, width) => {
  const a = make(width), b = make(Math.round(width * 2))
  return a && b ? `${a} 1x, ${b} 2x` : null
}
