// What this browser can play, told to Jellyfin as a device profile, and how a stream came
// out. Built from what the browser itself says it decodes (Firefox and Chrome differ: HEVC,
// for one, depends on the machine), instead of a fixed list.
//
//  - Direct play: an MP4 or WebM file the browser plays as it is.
//  - Otherwise the server's HLS (fMP4 segments). It copies the picture whenever the browser
//    decodes it (an MKV with H.264 or HEVC: only the sound is converted, if at all), and
//    converts the picture only when it has to (an unsupported codec, a burnt-in subtitle).
import { langMatches } from './item.js'

let caps

/** The codecs this browser decodes (worked out once). */
export function capabilities() {
  if (caps) return caps
  const v = typeof document === 'undefined' ? null : document.createElement('video')
  const mse = (t) => (typeof MediaSource !== 'undefined' && MediaSource.isTypeSupported(t)) || false
  const can = (t) => mse(t) || v?.canPlayType(t) === 'probably'
  caps = {
    h264: can('video/mp4; codecs="avc1.640029"'),
    hevc: can('video/mp4; codecs="hvc1.1.6.L120.90"') || can('video/mp4; codecs="hev1.1.6.L120.90"'),
    hevc10: can('video/mp4; codecs="hvc1.2.4.L120.90"') || can('video/mp4; codecs="hev1.2.4.L120.90"'),
    av1: can('video/mp4; codecs="av01.0.08M.08"'),
    av1_10: can('video/mp4; codecs="av01.0.08M.10"'),
    vp9: can('video/mp4; codecs="vp09.00.10.08"') || can('video/webm; codecs="vp9"'),
    aac: can('audio/mp4; codecs="mp4a.40.2"'),
    mp3: can('audio/mp4; codecs="mp4a.69"') || can('audio/mpeg'),
    opus: can('audio/mp4; codecs="opus"') || can('audio/webm; codecs="opus"'),
    flac: can('audio/mp4; codecs="flac"'),
    ac3: can('audio/mp4; codecs="ac-3"'),
    eac3: can('audio/mp4; codecs="ec-3"'),
    hdr: typeof matchMedia !== 'undefined' && matchMedia('(dynamic-range: high)').matches,
  }
  return caps
}

const pick = (c, names) => names.filter((n) => c[n === 'hevc' ? 'hevc' : n]).join(',')

/** The device profile sent with every PlaybackInfo. [maxBitrate] (bit/s) forces conversion. */
export function deviceProfile(maxBitrate, c = capabilities()) {
  const video = pick(c, ['h264', 'hevc', 'av1', 'vp9'])
  const audio = pick(c, ['aac', 'mp3', 'opus', 'flac', 'ac3', 'eac3'])
  // HDR pictures only to a screen that shows them; otherwise the server tone-maps.
  const ranges = c.hdr ? 'SDR|HDR10|HDR10Plus|HLG|DOVIWithHDR10|DOVIWithHLG|DOVIWithSDR' : 'SDR|DOVIWithSDR'
  const range = { Condition: 'EqualsAny', Property: 'VideoRangeType', Value: ranges, IsRequired: false }
  const depth8 = { Condition: 'LessThanEqual', Property: 'VideoBitDepth', Value: '8', IsRequired: false }
  return {
    MaxStreamingBitrate: maxBitrate || 1e9,
    MaxStaticBitrate: maxBitrate || 1e9,
    DirectPlayProfiles: maxBitrate
      ? []
      : [
          { Container: 'mp4,m4v', Type: 'Video', VideoCodec: video, AudioCodec: audio },
          { Container: 'webm', Type: 'Video', VideoCodec: pick(c, ['vp9', 'av1']) || 'vp8', AudioCodec: 'vorbis,opus' },
        ],
    TranscodingProfiles: [
      {
        Container: 'mp4', Type: 'Video', Protocol: 'hls', Context: 'Streaming', VideoCodec: pick(c, ['h264', 'hevc', 'av1']) || 'h264',
        AudioCodec: pick(c, ['aac', 'mp3', 'opus', 'flac', 'ac3', 'eac3']) || 'aac', MaxAudioChannels: '6', MinSegments: 1, BreakOnNonKeyFrames: true,
      },
    ],
    CodecProfiles: [
      { Type: 'Video', Codec: 'h264', Conditions: [depth8] },
      { Type: 'Video', Codec: 'hevc', Conditions: [range, ...(c.hevc10 ? [] : [depth8])] },
      { Type: 'Video', Codec: 'av1', Conditions: [range, ...(c.av1_10 ? [] : [depth8])] },
      { Type: 'Video', Codec: 'vp9', Conditions: [range] },
    ],
    // Text subtitles come as WebVTT and Hevyfin draws them; picture ones are burnt in.
    SubtitleProfiles: [
      ...['vtt', 'webvtt', 'srt', 'subrip', 'ass', 'ssa', 'mov_text'].map((f) => ({ Format: f, Method: 'External' })),
      ...['pgssub', 'pgs', 'dvdsub', 'dvbsub'].map((f) => ({ Format: f, Method: 'Encode' })),
    ],
    ResponseProfiles: [{ Type: 'Video', Container: 'm4v', MimeType: 'video/mp4' }],
  }
}

const VIDEO_REASONS = /Video|RefFrames|Anamorphic|Interlaced|SubtitleCodec|ContainerBitrate|DirectPlayError/

/** How a stream comes: 'direct' (the file), 'copy' (picture copied, sound maybe converted) or 'video' (picture converted). */
export function method(info) {
  const s = info.source
  if (s.SupportsDirectPlay || !s.TranscodingUrl) return { kind: 'direct', label: 'Direct play', reasons: [] }
  const q = new URL(s.TranscodingUrl, location.origin).searchParams
  const reasons = (q.get('TranscodeReasons') || '').split(',').filter(Boolean)
  const audio = reasons.some((r) => r.startsWith('Audio'))
  if (reasons.some((r) => VIDEO_REASONS.test(r))) return { kind: 'video', label: 'Converting the picture', reasons }
  return { kind: 'copy', label: audio ? 'Converting the sound' : 'Repackaged', reasons }
}

export const audioStreams = (info) => (info.source.MediaStreams || []).filter((s) => s.Type === 'Audio')
export const subtitleStreams = (info) => (info.source.MediaStreams || []).filter((s) => s.Type === 'Subtitle')
export const isTextSub = (s) => s.IsTextSubtitleStream === true

/** The audio track a stream plays: the server's pick for its HLS, else the file's default. */
export function playingAudio(info) {
  const a = audioStreams(info)
  if (info.source.TranscodingUrl && !info.source.SupportsDirectPlay) return info.source.DefaultAudioStreamIndex ?? a[0]?.Index ?? null
  return (a.find((s) => s.IsDefault) || a[0])?.Index ?? null
}

/** The track in [lang], if it isn't the one playing already. */
export function audioFor(info, lang) {
  const want = audioStreams(info).find((s) => langMatches(s.Language, lang))
  return want && want.Index !== playingAudio(info) ? want.Index : null
}

/** The first text subtitle in [lang]. */
export const subtitleFor = (info, lang) => (lang ? subtitleStreams(info).find((s) => isTextSub(s) && langMatches(s.Language, lang)) || null : null)

export const trackName = (s) => s.DisplayTitle || s.Title || s.Language || `Track ${s.Index}`
