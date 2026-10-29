import { describe, expect, it } from 'vitest'
import { audioFor, deviceProfile, method, playingAudio, subtitleFor } from '../src/lib/playback.js'

const FIREFOX = { h264: true, hevc: false, hevc10: false, av1: true, av1_10: true, vp9: true, aac: true, mp3: true, opus: true, flac: true, ac3: false, eac3: false, hdr: false }
const CHROME_HEVC = { ...FIREFOX, hevc: true, hevc10: true }
const hls = (reasons) => ({ source: { SupportsDirectPlay: false, TranscodingUrl: `/videos/x/master.m3u8?TranscodeReasons=${reasons}` } })

describe('deviceProfile', () => {
  it('direct-plays what the browser decodes and lets the server copy it into HLS', () => {
    const p = deviceProfile(null, CHROME_HEVC)
    expect(p.DirectPlayProfiles[0].VideoCodec).toBe('h264,hevc,av1,vp9')
    expect(p.TranscodingProfiles[0]).toMatchObject({ Container: 'mp4', Protocol: 'hls', VideoCodec: 'h264,hevc,av1' })
  })
  it('leaves HEVC out where the browser has none (the server converts it)', () => {
    const p = deviceProfile(null, FIREFOX)
    expect(p.TranscodingProfiles[0].VideoCodec).toBe('h264,av1')
    expect(p.DirectPlayProfiles[0].AudioCodec).not.toContain('eac3')
  })
  it('a quality cap means no direct play', () => {
    expect(deviceProfile(6e6, FIREFOX).DirectPlayProfiles).toEqual([])
    expect(deviceProfile(6e6, FIREFOX).MaxStreamingBitrate).toBe(6e6)
  })
  it('only an HDR screen gets HDR pictures', () => {
    const range = (c) => deviceProfile(null, c).CodecProfiles.find((x) => x.Codec === 'hevc').Conditions.find((x) => x.Property === 'VideoRangeType').Value
    expect(range(CHROME_HEVC)).toBe('SDR|DOVIWithSDR')
    expect(range({ ...CHROME_HEVC, hdr: true })).toContain('HDR10')
  })
  it('burns picture subtitles in and draws text ones', () => {
    const subs = Object.fromEntries(deviceProfile(null, FIREFOX).SubtitleProfiles.map((s) => [s.Format, s.Method]))
    expect(subs).toMatchObject({ srt: 'External', ass: 'External', pgssub: 'Encode', dvdsub: 'Encode' })
  })
})

describe('method', () => {
  it('names how a stream comes', () => {
    expect(method({ source: { SupportsDirectPlay: true } }).kind).toBe('direct')
    // An MKV with H.264 and E-AC3: repackaged, the picture copied, the sound converted.
    expect(method(hls('ContainerNotSupported,AudioCodecNotSupported'))).toMatchObject({ kind: 'copy', label: 'Converting the sound' })
    expect(method(hls('ContainerNotSupported')).label).toBe('Repackaged')
    // HEVC in Firefox, or a burnt-in subtitle: the picture is converted.
    expect(method(hls('VideoCodecNotSupported,AudioCodecNotSupported')).kind).toBe('video')
    expect(method(hls('SubtitleCodecNotSupported')).kind).toBe('video')
  })
})

describe('tracks', () => {
  const info = {
    source: {
      SupportsDirectPlay: true,
      MediaStreams: [
        { Type: 'Audio', Index: 1, Language: 'jpn', IsDefault: true },
        { Type: 'Audio', Index: 2, Language: 'eng' },
        { Type: 'Subtitle', Index: 3, Language: 'eng', IsTextSubtitleStream: false },
        { Type: 'Subtitle', Index: 4, Language: 'en', IsTextSubtitleStream: true },
      ],
    },
  }
  it('plays the default sound; another language means another stream', () => {
    expect(playingAudio(info)).toBe(1)
    expect(audioFor(info, 'eng')).toBe(2)
    expect(audioFor(info, 'jpn')).toBe(null)
  })
  it('picks a text subtitle in the language (eng also matches en)', () => {
    expect(subtitleFor(info, 'eng').Index).toBe(4)
    expect(subtitleFor(info, '')).toBe(null)
  })
})
