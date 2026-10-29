import { describe, expect, it } from 'vitest'
import { cuesAt, parseVtt } from '../src/lib/vtt.js'

const VTT = `WEBVTT

1
00:00:01.000 --> 00:00:03.500
<i>Hello</i> &amp; welcome

2
00:01:02,250 --> 00:01:04,000
Two
lines

00:00:02.000 --> 00:00:05.000 align:start
Overlapping`

describe('parseVtt', () => {
  const cues = parseVtt(VTT)
  it('reads times (dots or commas), drops tags and entities, keeps them in order', () => {
    expect(cues.map((c) => c.start)).toEqual([1, 2, 62.25])
    expect(cues[0]).toEqual({ start: 1, end: 3.5, text: 'Hello & welcome' })
    expect(cues[2].text).toBe('Two\nlines')
  })
  it('finds every line showing at a moment, overlaps included', () => {
    expect(cuesAt(cues, 2.5)).toEqual(['Hello & welcome', 'Overlapping'])
    expect(cuesAt(cues, 10)).toEqual([])
    expect(cuesAt(cues, 63)).toEqual(['Two\nlines'])
  })
})
