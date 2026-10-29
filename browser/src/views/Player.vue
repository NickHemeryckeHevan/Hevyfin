<script setup>
// The player (port of lib/ui/player.dart for the browser). The file plays as it is when the
// browser can; otherwise the server's HLS, with the picture copied whenever it can be (see
// lib/playback.js). Another audio language, or a picture subtitle, is a new stream from the
// server; text subtitles are drawn here in the user's style. Resume, skip intro/recap, the
// credits countdown into what's next (also along a universe's path), "Still watching?",
// "Previously on", trickplay previews, keyboard, media keys and picture-in-picture.
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref, shallowRef } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import Icon from '../components/Icon.vue'
import * as jf from '../api/jellyfin.js'
import { clock, displayTitle, episodeCode, isEpisode, isMovie, lastPlayed, played, progress as itemProgress, resumeAt, scenesOf } from '../lib/item.js'
import { audioFor, audioStreams, deviceProfile, isTextSub, method, playingAudio, subtitleFor, subtitleStreams, trackName } from '../lib/playback.js'
import { cuesAt, loadCues } from '../lib/vtt.js'
import { bump, prefs, say } from '../state/session.js'

const props = defineProps({ id: String })
const route = useRoute()
const router = useRouter()
const trailer = route.query.trailer === '1'
const box = route.query.in || null

const root = ref(null)
const video = ref(null)
let hls = null
const item = shallowRef(null)
const info = shallowRef(null)
const error = ref('')
const st = reactive({ pos: 0, dur: 0, paused: true, waiting: true, volume: prefs.volume ?? 1, muted: false, buffered: 0 })
const next = shallowRef(null)
const segments = ref([])
const scenes = ref(null)
const trick = shallowRef(null)
const cues = shallowRef([])
const sub = ref(null) // subtitle index showing (text drawn here, or burnt in)
const burnt = ref(false)
const audio = ref(null)
const countdown = ref(null)
const creditsDismissed = ref(false)
const stillWatching = ref(false)
const recap = shallowRef(null)
const recapLeft = ref(20)
const panel = ref(null) // 'tracks' | 'episodes'
const episodes = shallowRef([])
const shown = ref(true)
const fullscreen = ref(false)
const hover = ref(null) // {x, t} over the seek bar
let hideTimer, progressTimer, countdownTimer, recapTimer
let reportedStart = false, autoAdvances = 0, leaving = false
const autoSkipped = new Set()
const maxBitrate = () => (prefs.maxMbps > 0 ? prefs.maxMbps * 1e6 : null)

// ---- starting ----

async function start(id, at = null) {
  error.value = ''
  stopTimers()
  try {
    const it = await jf.item(id)
    const profile = deviceProfile(maxBitrate())
    let inf = await jf.playbackInfo(id, { profile, maxBitrate: maxBitrate() })
    // This show's own choice (made on any device) beats the general one.
    const show = isEpisode(it) && it.SeriesId ? (await Promise.race([jf.showTracks(), new Promise((r) => setTimeout(() => r({}), 3000))]))[it.SeriesId] : null
    const audioLang = show?.a || prefs.audioLang
    const subLang = show?.s === 'off' ? '' : show?.s || prefs.subtitleLang
    // The browser plays a file's default sound only: another language comes from the server.
    const want = trailer ? null : audioFor(inf, audioLang)
    if (want !== null) inf = await jf.playbackInfo(id, { profile, maxBitrate: maxBitrate(), audioIndex: want, transcode: true })
    const begin = at ?? (resumeAt(it) > 30 && (itemProgress(it) ?? 0) < 0.95 ? resumeAt(it) : 0)
    // Back to a show after a while: a reminder of where it was, before it plays.
    const rc = id === props.id && !trailer && isEpisode(it) ? await recapFor(it, begin > 0) : null

    Object.assign(st, { pos: begin, dur: (it.RunTimeTicks || 0) / 1e7, waiting: true })
    item.value = it
    info.value = inf
    audio.value = want ?? playingAudio(inf)
    sub.value = null
    burnt.value = false
    cues.value = []
    next.value = null
    segments.value = []
    scenes.value = isMovie(it) ? scenesOf(it) : null
    trick.value = null
    countdown.value = null
    creditsDismissed.value = false
    stillWatching.value = false
    reportedStart = false
    recap.value = rc
    document.title = `${trailer ? route.query.name || 'Trailer' : displayTitle(it)} · Hevyfin`
    await open(inf, begin, !rc)
    if (rc) startRecap()
    mediaSession()

    const s = subtitleFor(inf, subLang)
    if (s && !trailer) showSubtitle(s)
    jf.trickplay(id, inf.source.Id).then((t) => (trick.value = t))
    if (!trailer) {
      jf.segments(id).then((s) => (segments.value = s.filter((x) => ['Intro', 'Recap', 'Outro'].includes(x.type))))
      findNext(it)
      progressTimer = setInterval(report, 10000)
    }
  } catch (e) {
    error.value = e.message || String(e)
  }
}

/** Plays [inf]'s stream from [at] seconds. */
async function open(inf, at, play = true) {
  const v = video.value
  hls?.destroy()
  hls = null
  const url = jf.streamUrl(item.value.Id, inf)
  if (jf.isTranscode(inf)) {
    const { default: Hls } = await import('hls.js/light')
    if (Hls.isSupported()) {
      hls = new Hls({ startPosition: at, maxBufferLength: 30, backBufferLength: 60, enableWorker: true })
      hls.on(Hls.Events.ERROR, (_, d) => {
        if (!d.fatal) return
        if (d.type === Hls.ErrorTypes.NETWORK_ERROR) hls.startLoad()
        else if (d.type === Hls.ErrorTypes.MEDIA_ERROR) hls.recoverMediaError()
        else error.value = `Playback stopped (${d.details})`
      })
      hls.loadSource(url)
      hls.attachMedia(v)
    } else v.src = url
  } else {
    v.src = url
    v.addEventListener('loadedmetadata', () => (v.currentTime = at), { once: true })
  }
  v.volume = st.volume
  if (play) v.play().catch(() => (st.paused = true))
}

async function findNext(it) {
  try {
    let n = box ? await jf.nextInUniverse(box, it, { story: prefs.storyOrder.includes(box) }).catch(() => null) : null
    // Off the path: the show's next episode; a film rolls into the next of its franchise.
    if (!n && isEpisode(it)) n = await jf.nextEpisode(it)
    if (!n && isMovie(it)) n = await jf.nextInCollection(it, prefs.storyOrder)
    if (item.value?.Id === it.Id) next.value = n
  } catch {}
}

/** The episode to recap before [ep] when the show was last watched a week or more ago. */
async function recapFor(ep, resuming) {
  try {
    const all = (await jf.episodes(ep.SeriesId)).filter((e) => (e.ParentIndexNumber ?? 1) > 0)
    const last = Math.max(0, ...all.map((e) => lastPlayed(e)?.getTime() || 0))
    if (!last || Date.now() - last < 7 * 864e5) return null
    if (resuming) return ep
    const n = all.findIndex((e) => e.Id === ep.Id)
    return n > 0 ? all[n - 1] : null
  } catch {
    return null
  }
}

function startRecap() {
  recapLeft.value = 20
  recapTimer = setInterval(() => (--recapLeft.value <= 0 ? endRecap() : null), 1000)
}
function endRecap() {
  clearInterval(recapTimer)
  recap.value = null
  video.value.play().catch(() => {})
}

// ---- tracks ----

async function showSubtitle(s) {
  try {
    const got = await loadCues(jf.subtitleUrl(item.value.Id, info.value, s.Index))
    sub.value = s.Index
    cues.value = got
  } catch (e) {
    say(e.message)
  }
}

/** Plays on from here with another audio track, or a picture subtitle burnt in (or not). */
async function reopen(audioIndex, burn) {
  const at = video.value.currentTime, old = info.value
  try {
    const inf = await jf.playbackInfo(item.value.Id, { profile: deviceProfile(maxBitrate()), maxBitrate: maxBitrate(), audioIndex, subtitleIndex: burn ?? -1, transcode: true })
    jf.endTranscode(old)
    info.value = inf
    audio.value = audioIndex
    burnt.value = burn !== null
    if (burnt.value) (sub.value = burn), (cues.value = [])
    await open(inf, at)
  } catch (e) {
    say(`Could not switch: ${e.message}`)
  }
}

function pickAudio(a) {
  panel.value = null
  if (a.Index === audio.value) return
  reopen(a.Index, burnt.value ? sub.value : null)
  if (item.value.SeriesId && a.Language) jf.saveShowTrack(item.value.SeriesId, { audio: a.Language }).catch(() => {})
}

function pickSubtitle(s) {
  panel.value = null
  if (s && !isTextSub(s)) reopen(audio.value, s.Index)
  else {
    if (burnt.value) reopen(audio.value, null)
    sub.value = null
    cues.value = []
    if (s) showSubtitle(s)
  }
  if (item.value.SeriesId) jf.saveShowTrack(item.value.SeriesId, { subtitle: s ? s.Language || 'off' : 'off' }).catch(() => {})
}

// ---- what shows over the picture ----

const activeSegment = computed(() => segments.value.find((s) => s.type !== 'Outro' && st.pos >= s.start && st.pos < s.end - 2) || null)

/** In a film's credits: the button for the bonus scene coming up (or past a spoiler). */
const sceneSkip = computed(() => {
  const s = scenes.value
  if (!s || st.pos < s.credits) return null
  for (const sc of s.scenes) {
    if (st.pos >= sc.end) continue
    if (sc.spoiler) return { label: 'Skip spoiler', to: sc.end }
    if (st.pos >= sc.start - 1) return null
    return { label: sc.kind === 'mid' ? 'Skip to mid-credits scene' : 'Skip to post-credits scene', to: sc.start }
  }
  return null
})

const nearEnd = computed(() => {
  if (!next.value || !st.dur) return false
  // A film's bonus scenes come before what's next.
  if (scenes.value) return st.pos >= scenes.value.scenes.at(-1).end
  const outro = segments.value.find((s) => s.type === 'Outro')
  if (outro) return st.pos >= outro.start
  return st.dur - st.pos < 45
})

const lines = computed(() => (cues.value.length ? cuesAt(cues.value, st.pos) : []))
const how = computed(() => (info.value ? method(info.value) : null))
const title = computed(() => (trailer ? route.query.name || 'Trailer' : item.value ? displayTitle(item.value) : ''))
const subtitle = computed(() => (trailer ? 'Trailer' : item.value && isEpisode(item.value) ? `${episodeCode(item.value)}  “${item.value.Name}”` : ''))

function onTime() {
  const v = video.value
  st.pos = v.currentTime
  if (v.duration && isFinite(v.duration)) st.dur = v.duration
  if (v.buffered.length) st.buffered = v.buffered.end(v.buffered.length - 1)
  const seg = activeSegment.value
  // Skipping by itself (Settings): once per intro, so going back to watch it works.
  if (seg && prefs.autoSkip && !v.paused && !autoSkipped.has(`${item.value.Id}@${Math.floor(seg.start)}`)) {
    autoSkipped.add(`${item.value.Id}@${Math.floor(seg.start)}`)
    seek(seg.end)
    say(seg.type === 'Recap' ? 'Skipped the recap' : 'Skipped the intro')
  }
  // The credits are rolling: count down to what's next over them.
  if (nearEnd.value && countdown.value === null && !creditsDismissed.value && !stillWatching.value && !v.paused) startCountdown(10)
}

function startCountdown(seconds) {
  if (autoAdvances >= 3) return (stillWatching.value = true)
  countdown.value = seconds
  clearInterval(countdownTimer)
  countdownTimer = setInterval(() => {
    if (countdown.value <= 1) {
      clearInterval(countdownTimer)
      autoNext()
    } else countdown.value--
  }, 1000)
}

function autoNext() {
  if (autoAdvances >= 3) {
    clearInterval(countdownTimer)
    video.value.pause()
    countdown.value = null
    stillWatching.value = true
    return
  }
  autoAdvances++
  playNext(true)
}

function watchCredits() {
  clearInterval(countdownTimer)
  countdown.value = null
  creditsDismissed.value = true
}

function onEnded() {
  if (!next.value) return leave()
  if (countdown.value !== null && !creditsDismissed.value) return autoNext()
  creditsDismissed.value = false
  startCountdown(8)
}

async function playNext(auto = false) {
  const n = next.value
  if (!n) return
  if (!auto) autoAdvances = 0
  clearInterval(countdownTimer)
  await stopReport()
  // A new address, so Back and a reload land on what's playing now.
  router.replace({ path: `/play/${n.Id}`, query: box ? { in: box } : {} })
}

async function playEpisode(e) {
  panel.value = null
  if (e.Id === item.value.Id) return
  await stopReport()
  router.replace({ path: `/play/${e.Id}`, query: box ? { in: box } : {} })
}

async function openEpisodes() {
  panel.value = panel.value === 'episodes' ? null : 'episodes'
  if (panel.value && item.value.SeriesId) episodes.value = await jf.episodes(item.value.SeriesId, item.value.SeasonId)
}

// ---- telling Jellyfin ----

function onPlaying() {
  st.paused = false
  st.waiting = false
  if (!reportedStart && !trailer && info.value) {
    reportedStart = true
    jf.reportStart(item.value.Id, info.value, video.value.currentTime).catch(() => {})
  }
  report()
}

function report() {
  if (!reportedStart || !info.value) return
  jf.reportProgress(item.value.Id, info.value, video.value.currentTime, video.value.paused).catch(() => {})
}

async function stopReport(keepalive = false) {
  const inf = info.value, it = item.value
  if (!inf || !it) return
  info.value = null
  try {
    // Never started (backed out of "Previously on"): only the server's conversion to stop.
    reportedStart && !trailer ? await jf.reportStop(it.Id, inf, video.value?.currentTime ?? st.pos, keepalive) : await jf.endTranscode(inf, keepalive)
  } catch {}
}

async function leave() {
  if (leaving) return
  leaving = true
  await stopReport()
  bump()
  if (document.fullscreenElement) document.exitFullscreen().catch(() => {})
  router.options.history.state.back ? router.back() : router.replace(item.value ? `/item/${item.value.SeriesId || item.value.Id}` : '/')
}

// ---- controls ----

function poke() {
  shown.value = true
  autoAdvances = 0
  clearTimeout(hideTimer)
  hideTimer = setTimeout(() => (shown.value = panel.value !== null || video.value?.paused), 3000)
}

const toggle = () => (video.value.paused ? video.value.play() : video.value.pause())
function seek(t) {
  const v = video.value
  v.currentTime = Math.max(0, Math.min(t, st.dur || v.duration || t))
  st.pos = v.currentTime
}
const seekBy = (s) => (seek(video.value.currentTime + s), poke())
function setVolume(v) {
  st.volume = Math.max(0, Math.min(1, v))
  video.value.volume = st.volume
  video.value.muted = st.muted = st.volume === 0
  prefs.volume = st.volume
}
const mute = () => (video.value.muted = st.muted = !st.muted)

async function toggleFullscreen() {
  if (document.fullscreenElement) await document.exitFullscreen()
  else await root.value.requestFullscreen().catch(() => {})
}
const onFullscreen = () => (fullscreen.value = !!document.fullscreenElement)

const canPip = typeof document !== 'undefined' && document.pictureInPictureEnabled
async function pip() {
  try {
    document.pictureInPictureElement ? await document.exitPictureInPicture() : await video.value.requestPictureInPicture()
  } catch {}
}

function barTime(e) {
  const r = e.currentTarget.getBoundingClientRect()
  return { x: e.clientX - r.left, t: Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)) * st.dur, w: r.width }
}
function scrubTo(e) {
  seek(barTime(e).t)
  poke()
}

/** The trickplay frame for [t]: its tile image and where the frame sits in it. */
function frame(t) {
  const tp = trick.value
  if (!tp) return null
  const n = Math.max(0, Math.min(tp.count - 1, Math.floor((t * 1000) / tp.interval)))
  const per = tp.cols * tp.rows, at = n % per
  return {
    width: tp.width + 'px', height: tp.height + 'px',
    backgroundImage: `url(${tp.url(Math.floor(n / per))})`,
    backgroundSize: `${tp.cols * tp.width}px ${tp.rows * tp.height}px`,
    backgroundPosition: `-${(at % tp.cols) * tp.width}px -${Math.floor(at / tp.cols) * tp.height}px`,
  }
}

function onKey(e) {
  if (e.target.closest?.('input, select, textarea')) return
  if (recap.value && (e.key === 'Enter' || e.key === ' ')) return e.preventDefault(), endRecap()
  const k = e.key.toLowerCase()
  const keys = {
    ' ': toggle, k: toggle, arrowleft: () => seekBy(-10), j: () => seekBy(-10), arrowright: () => seekBy(10), l: () => seekBy(10),
    arrowup: () => setVolume(st.volume + 0.05), arrowdown: () => setVolume(st.volume - 0.05), m: mute, f: toggleFullscreen,
    c: () => (sub.value !== null && !burnt.value ? pickSubtitle(null) : quickSubtitle()),
    escape: () => (panel.value ? (panel.value = null) : document.fullscreenElement ? null : leave()),
  }
  if (e.shiftKey && k === 'n' && next.value) return playNext()
  if (keys[k] && !e.ctrlKey && !e.metaKey && !e.altKey) {
    e.preventDefault()
    keys[k]()
    poke()
  }
}

/** C with subtitles off: the preferred language, else the first text subtitle. */
function quickSubtitle() {
  const s = subtitleFor(info.value, prefs.subtitleLang || 'eng') || subtitleStreams(info.value).find(isTextSub)
  s ? pickSubtitle(s) : say('No subtitles for this one')
}

/** Media keys, headphones and the system's media controls. */
function mediaSession() {
  if (!('mediaSession' in navigator) || !item.value) return
  const it = item.value
  navigator.mediaSession.metadata = new MediaMetadata({
    title: isEpisode(it) ? `${episodeCode(it)} ${it.Name}` : it.Name,
    artist: isEpisode(it) ? it.SeriesName : 'Hevyfin',
    artwork: [{ src: jf.poster(it, 512) || '', sizes: '512x768', type: 'image/jpeg' }],
  })
  const set = (a, f) => {
    try {
      navigator.mediaSession.setActionHandler(a, f)
    } catch {}
  }
  set('play', () => video.value.play())
  set('pause', () => video.value.pause())
  set('seekbackward', () => seekBy(-10))
  set('seekforward', () => seekBy(10))
  set('seekto', (d) => seek(d.seekTime))
  set('nexttrack', () => (next.value ? playNext() : null))
}

const subStyle = computed(() => ({
  fontSize: `calc(clamp(18px, 2.6vw, 44px) * ${prefs.subSize})`,
  color: prefs.subColor === 'yellow' ? '#ffe14d' : '#fff',
}))

function stopTimers() {
  clearInterval(progressTimer)
  clearInterval(countdownTimer)
  clearInterval(recapTimer)
}

const onPageHide = () => stopReport(true)

onMounted(() => {
  addEventListener('keydown', onKey)
  addEventListener('pagehide', onPageHide)
  document.addEventListener('fullscreenchange', onFullscreen)
  poke()
  const t = Number(route.query.t)
  start(props.id, Number.isFinite(t) && t > 0 ? t : null)
})

onBeforeUnmount(() => {
  removeEventListener('keydown', onKey)
  removeEventListener('pagehide', onPageHide)
  document.removeEventListener('fullscreenchange', onFullscreen)
  stopTimers()
  clearTimeout(hideTimer)
  if (!leaving) stopReport()
  hls?.destroy()
  if ('mediaSession' in navigator) navigator.mediaSession.metadata = null
  document.title = 'Hevyfin'
})
</script>

<template>
  <div ref="root" class="player" :class="{ hide: !shown && !panel && !st.paused }" @mousemove="poke" @click.self="toggle">
    <video ref="video" class="video" playsinline @click="toggle(), poke()" @dblclick="toggleFullscreen" @timeupdate="onTime" @playing="onPlaying"
           @pause="(st.paused = true), report(), poke()" @waiting="st.waiting = true" @canplay="st.waiting = false" @ended="onEnded"
           @volumechange="st.muted = video.muted" />

    <div v-if="lines.length && !burnt" class="cues" :class="{ up: shown || st.paused }">
      <span v-for="(l, n) in lines" :key="n" :class="{ box: prefs.subBox }" :style="subStyle">{{ l }}</span>
    </div>

    <div v-if="(st.waiting || !item) && !error && !recap" class="loading"><span class="spinner" /></div>

    <div v-if="error" class="error">
      <p>Couldn't play this: {{ error }}</p>
      <div class="row-btns"><button class="btn" @click="start(id)">Try again</button><button class="btn ghost" @click="leave">Back</button></div>
    </div>

    <!-- Controls -->
    <div class="top">
      <button class="icon-btn" title="Back (Esc)" @click="leave"><Icon name="back" :size="30" /></button>
      <div class="name"><b>{{ title }}</b><span v-if="subtitle" class="dim">{{ subtitle }}</span></div>
      <span v-if="how" class="how" :class="how.kind" :title="how.reasons.join(', ')">{{ how.label }}</span>
    </div>

    <div class="bottom" @click.stop>
      <div class="scrub" @click="scrubTo" @mousemove="hover = barTime($event)" @mouseleave="hover = null">
        <div class="track">
          <i class="buf" :style="{ width: (st.dur ? (st.buffered / st.dur) * 100 : 0) + '%' }" />
          <i class="done" :style="{ width: (st.dur ? (st.pos / st.dur) * 100 : 0) + '%' }" />
          <i v-for="s in segments" :key="s.start" class="seg" :style="{ left: (s.start / st.dur) * 100 + '%', width: ((s.end - s.start) / st.dur) * 100 + '%' }" />
        </div>
        <div v-if="hover" class="preview" :style="{ left: Math.max(90, Math.min(hover.w - 90, hover.x)) + 'px' }">
          <div v-if="frame(hover.t)" class="frame" :style="frame(hover.t)" />
          <span>{{ clock(hover.t) }}</span>
        </div>
      </div>
      <div class="buttons">
        <button class="icon-btn" :title="st.paused ? 'Play (Space)' : 'Pause (Space)'" @click="toggle"><Icon :name="st.paused ? 'play' : 'pause'" :size="30" /></button>
        <button class="icon-btn" title="Back 10 seconds (←)" @click="seekBy(-10)"><Icon name="back10" :size="28" /></button>
        <button class="icon-btn" title="Forward 10 seconds (→)" @click="seekBy(10)"><Icon name="fwd10" :size="28" /></button>
        <div class="vol">
          <button class="icon-btn" title="Mute (M)" @click="mute"><Icon :name="st.muted || !st.volume ? 'mute' : 'volume'" :size="27" /></button>
          <input type="range" min="0" max="1" step="0.02" :value="st.muted ? 0 : st.volume" aria-label="Volume" @input="setVolume(Number($event.target.value))" />
        </div>
        <span class="time">{{ clock(st.pos) }} / {{ clock(st.dur) }}</span>
        <span class="spacer" />
        <button v-if="next" class="icon-btn" title="Next (Shift+N)" @click="playNext()"><Icon name="next" :size="26" /></button>
        <button v-if="item && isEpisode(item)" class="icon-btn" :class="{ on: panel === 'episodes' }" title="Episodes" @click="openEpisodes"><Icon name="episodes" :size="27" /></button>
        <button v-if="info" class="icon-btn" :class="{ on: panel === 'tracks' }" title="Audio & subtitles (C)" @click="panel = panel === 'tracks' ? null : 'tracks'">
          <Icon name="subs" :size="27" />
        </button>
        <button v-if="canPip" class="icon-btn" title="Picture-in-picture" @click="pip"><Icon name="pip" :size="26" /></button>
        <button class="icon-btn" :title="fullscreen ? 'Exit full screen (F)' : 'Full screen (F)'" @click="toggleFullscreen"><Icon :name="fullscreen ? 'unfull' : 'full'" :size="26" /></button>
      </div>
    </div>

    <!-- Audio & subtitles -->
    <div v-if="panel === 'tracks' && info" class="panel tracks" @click.stop>
      <div>
        <h3>Audio</h3>
        <button v-for="a in audioStreams(info)" :key="a.Index" :class="{ on: a.Index === audio }" @click="pickAudio(a)">
          <Icon v-if="a.Index === audio" name="check" :size="18" /> {{ trackName(a) }}
        </button>
      </div>
      <div>
        <h3>Subtitles</h3>
        <button :class="{ on: sub === null }" @click="pickSubtitle(null)"><Icon v-if="sub === null" name="check" :size="18" /> Off</button>
        <button v-for="s in subtitleStreams(info)" :key="s.Index" :class="{ on: s.Index === sub }" @click="pickSubtitle(s)">
          <Icon v-if="s.Index === sub" name="check" :size="18" /> {{ trackName(s) }}<span v-if="!isTextSub(s)" class="mute small"> (burnt in)</span>
        </button>
      </div>
    </div>

    <!-- Episodes -->
    <div v-if="panel === 'episodes'" class="panel eps" @click.stop>
      <h3>{{ item.SeriesName }} · {{ item.SeasonName || `Season ${item.ParentIndexNumber}` }}</h3>
      <button v-for="e in episodes" :key="e.Id" :class="{ on: e.Id === item.Id }" @click="playEpisode(e)">
        <img :src="jf.thumb(e, 240)" alt="" loading="lazy" />
        <span><b>{{ e.IndexNumber }}. {{ e.Name }}</b><span class="dim small">{{ e.Overview }}</span></span>
        <Icon v-if="played(e)" name="check" class="ok" />
      </button>
    </div>

    <!-- Skip and next -->
    <div class="corner" @click.stop>
      <button v-if="activeSegment && !recap" class="btn ghost skip" @click="seek(activeSegment.end)">{{ activeSegment.type === 'Recap' ? 'Skip Recap' : 'Skip Intro' }}</button>
      <button v-else-if="sceneSkip" class="btn ghost skip" @click="seek(sceneSkip.to)">{{ sceneSkip.label }}</button>
      <div v-else-if="countdown !== null && next && !st.paused && nearEnd" class="credits">
        <img :src="jf.thumb(next, 480)" alt="" />
        <i class="fill" :style="{ animationDuration: '10s' }" />
        <small>{{ isEpisode(next) ? 'NEXT EPISODE' : 'NEXT MOVIE' }} IN {{ countdown }}</small>
        <b>{{ isEpisode(next) ? `${episodeCode(next)}  ${next.Name}` : next.Name }}</b>
        <div class="row-btns"><button class="btn flat" @click="watchCredits">Watch credits</button><button class="btn" @click="playNext()"><Icon name="play" /> Play now</button></div>
      </div>
      <button v-else-if="nearEnd && countdown === null && !stillWatching" class="btn" @click="playNext()"><Icon name="next" /> {{ isEpisode(next) ? 'Next Episode' : 'Next Movie' }}</button>
    </div>

    <!-- After the end: a short countdown over the whole screen -->
    <div v-if="countdown !== null && next && !nearEnd" class="cover">
      <small class="eyebrow">{{ isEpisode(next) ? 'Next episode' : 'Next movie' }} in {{ countdown }}</small>
      <h2>{{ isEpisode(next) ? `${next.SeriesName}: ${next.Name}` : next.Name }}</h2>
      <div class="row-btns"><button class="btn" @click="playNext()"><Icon name="play" /> Play now</button><button class="btn ghost" @click="leave">Back to browse</button></div>
    </div>

    <div v-if="stillWatching" class="cover">
      <h2>{{ item?.SeriesName ? `Are you still watching ${item.SeriesName}?` : 'Are you still watching?' }}</h2>
      <div class="row-btns"><button class="btn" @click="(autoAdvances = 0), (stillWatching = false), playNext()"><Icon name="play" /> Continue watching</button>
        <button class="btn ghost" @click="leave">Back to browse</button></div>
    </div>

    <!-- "Previously on" -->
    <div v-if="recap" class="recap" :style="{ backgroundImage: `url(${jf.thumb(recap, 1600)})` }">
      <div class="in">
        <small class="eyebrow">{{ recap.Id === item?.Id ? 'WHERE YOU LEFT OFF' : 'PREVIOUSLY ON' }}</small>
        <h2>{{ recap.SeriesName }}</h2>
        <p class="dim"><b>{{ episodeCode(recap) }}  “{{ recap.Name }}”</b></p>
        <p>{{ recap.Overview || 'No summary for this one.' }}</p>
        <div class="row-btns"><button class="btn" @click="endRecap"><Icon name="play" /> {{ recap.Id === item?.Id ? 'Resume' : 'Play episode' }} ({{ recapLeft }})</button>
          <button class="btn ghost" @click="leave">Back</button></div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.player { position: fixed; inset: 0; background: #000; color: #fff; overflow: hidden; user-select: none; }
.player.hide { cursor: none; }
.video { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: contain; }
.loading { position: absolute; inset: 0; display: grid; place-items: center; pointer-events: none; }
.error { position: absolute; inset: 0; display: grid; place-content: center; gap: 18px; text-align: center; background: #000; font-size: 18px; z-index: 6; }
.row-btns { display: flex; gap: 10px; justify-content: center; }

.top, .bottom { position: absolute; left: 0; right: 0; z-index: 3; transition: opacity .35s; }
.hide .top, .hide .bottom, .hide .corner .skip { opacity: 0; pointer-events: none; }
.top { top: 0; display: flex; align-items: center; gap: 14px; padding: 18px 28px 60px; background: linear-gradient(rgba(0, 0, 0, .75), transparent); }
.name { display: grid; flex: 1; }
.name b { font-size: 19px; }
.how { font-size: 12px; font-weight: 700; padding: 3px 10px; border-radius: 20px; border: 1px solid rgba(255, 255, 255, .3); color: var(--dim); }
.how.direct { border-color: rgba(70, 211, 105, .6); color: var(--good); }
.how.video { border-color: rgba(255, 122, 26, .7); color: var(--orange-hi); }
.bottom { bottom: 0; padding: 70px 28px 18px; background: linear-gradient(transparent, rgba(0, 0, 0, .85)); }
.buttons { display: flex; align-items: center; gap: 6px; }
.buttons .icon-btn.on { color: var(--orange); }
.spacer { flex: 1; }
.time { font-variant-numeric: tabular-nums; font-size: 14px; color: var(--dim); margin-left: 8px; }
.vol { display: flex; align-items: center; }
.vol input { width: 0; opacity: 0; transition: width .2s, opacity .2s; }
.vol:hover input, .vol input:focus { width: 90px; opacity: 1; }

.scrub { position: relative; height: 22px; display: flex; align-items: center; cursor: pointer; margin-bottom: 4px; }
.track { position: relative; width: 100%; height: 4px; background: rgba(255, 255, 255, .25); border-radius: 2px; transition: height .15s; }
.scrub:hover .track { height: 7px; }
.track i { position: absolute; top: 0; bottom: 0; left: 0; border-radius: 2px; }
.buf { background: rgba(255, 255, 255, .35); }
.done { background: var(--orange); }
.done::after { content: ''; position: absolute; right: -7px; top: 50%; width: 14px; height: 14px; margin-top: -7px; border-radius: 50%; background: var(--orange); transform: scale(0); transition: transform .15s; }
.scrub:hover .done::after { transform: scale(1); }
.seg { background: rgba(255, 255, 255, .35); }
.preview { position: absolute; bottom: 26px; transform: translateX(-50%); display: grid; justify-items: center; gap: 6px; pointer-events: none; }
.frame { border: 2px solid #fff; border-radius: 4px; background-repeat: no-repeat; box-shadow: 0 4px 20px #000; }
.preview span { font-weight: 700; font-size: 14px; text-shadow: 0 1px 4px #000; }

.cues { position: absolute; left: 6%; right: 6%; bottom: 7%; display: flex; flex-direction: column; align-items: center; gap: 4px; z-index: 2; transition: bottom .3s;
  pointer-events: none; text-align: center; }
.cues.up { bottom: 17%; }
.cues span { font-weight: 600; line-height: 1.25; white-space: pre-line; text-shadow: 0 0 8px #000, 0 0 3px #000, 1px 1px 2px #000; }
.cues span.box { background: rgba(0, 0, 0, .7); padding: 2px 10px; text-shadow: none; }

.panel { position: absolute; right: 28px; bottom: 110px; z-index: 5; background: rgba(20, 20, 20, .96); border: 1px solid #333; border-radius: 8px; padding: 16px;
  max-height: 60vh; overflow: auto; box-shadow: 0 10px 40px #000; }
.panel h3 { font-size: 15px; margin: 0 0 8px; color: var(--dim); }
.panel button { display: flex; align-items: center; gap: 8px; width: 100%; text-align: left; background: none; border: 0; padding: 8px 10px; border-radius: 4px; cursor: pointer; }
.panel button:hover { background: var(--hover); }
.panel button.on { color: var(--orange-hi); font-weight: 700; }
.tracks { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; min-width: 520px; }
.eps { width: 480px; display: grid; gap: 4px; }
.eps button { align-items: flex-start; }
.eps img { width: 140px; aspect-ratio: 16 / 9; object-fit: cover; border-radius: 4px; flex: none; }
.eps span { display: grid; gap: 4px; }
.eps .small { display: -webkit-box; -webkit-line-clamp: 2; line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
.eps .ok { color: var(--orange); flex: none; }

.corner { position: absolute; right: 40px; bottom: 120px; z-index: 4; }
.skip { background: rgba(30, 30, 30, .75); border: 1px solid rgba(255, 255, 255, .5); font-size: 16px; }
.credits { width: 340px; background: rgba(20, 20, 20, .92); border-radius: 8px; overflow: hidden; display: grid; gap: 4px; padding-bottom: 10px; position: relative; }
.credits img { width: 100%; aspect-ratio: 16 / 9; object-fit: cover; }
.credits .fill { position: absolute; top: calc(340px * 9 / 16 - 3px); left: 0; height: 3px; background: var(--orange); animation: grow linear forwards; }
.credits small { padding: 6px 12px 0; color: var(--orange); font-weight: 800; letter-spacing: 1.5px; font-size: 12px; }
.credits b { padding: 0 12px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.credits .row-btns { justify-content: space-between; padding: 6px 12px 0; }
@keyframes grow { from { width: 0; } to { width: 100%; } }

.cover { position: absolute; inset: 0; z-index: 6; background: rgba(0, 0, 0, .85); display: grid; place-content: center; gap: 18px; text-align: center; padding: 40px; }
.cover h2 { font-size: 34px; font-weight: 900; }
.eyebrow { color: var(--orange); font-weight: 800; letter-spacing: 2.5px; font-size: 13px; text-transform: uppercase; }
.recap { position: absolute; inset: 0; z-index: 7; background: #000 center / cover; display: flex; align-items: center; }
.recap::before { content: ''; position: absolute; inset: 0; background: linear-gradient(90deg, rgba(0, 0, 0, .95), rgba(0, 0, 0, .7), rgba(0, 0, 0, .3)); }
.recap .in { position: relative; max-width: 620px; margin-left: 72px; display: grid; gap: 12px; }
.recap h2 { font-size: 40px; font-weight: 900; }
.recap p { font-size: 17px; line-height: 1.5; }
.recap .row-btns { justify-content: flex-start; margin-top: 10px; }
</style>
