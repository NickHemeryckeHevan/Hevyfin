<script setup>
// One TMDb title through Seerr: what it is, whether it's here or asked for, and the request
// button, with a season picker for shows (port of SeerrDetailsPage in discover.dart).
import { computed, ref, watch } from 'vue'
import Icon from '../components/Icon.vue'
import Pic from '../components/Pic.vue'
import Row from '../components/Row.vue'
import SeerrCard from '../components/SeerrCard.vue'
import TrailerDialog from '../components/TrailerDialog.vue'
import DiscoverConnect from '../components/DiscoverConnect.vue'
import * as seerr from '../api/seerr.js'
import { duration } from '../lib/item.js'
import { bump, say } from '../state/session.js'

const props = defineProps({ type: String, tmdb: String })
const m = ref(null)
const error = ref('')
const chosen = ref(new Set())
const sending = ref(false)
const scores = ref({})
const trailer = ref(null)

async function load() {
  error.value = ''
  try {
    const got = await seerr.details(props.type, Number(props.tmdb))
    const st = seerr.seasonStatus(got)
    chosen.value = new Set(seerr.seasonNumbers(got).filter((n) => canAsk(st[n])))
    m.value = got
    document.title = `${seerr.title(got)} · Hevyfin`
  } catch (e) {
    error.value = e.message
  }
}

watch(() => [props.type, props.tmdb, seerr.seerrReady.value], ([type, tmdb, ready]) => {
  if (!ready) return
  m.value = null
  load()
  seerr.ratings(type, Number(tmdb)).then((r) => (scores.value = r))
}, { immediate: true })

/** A season that can be asked for: not here, not asked for yet (a partly-there one isn't). */
const canAsk = (s) => seerr.requestable(s ?? 1) && s !== 4
const status = computed(() => (m.value ? seerr.status(m.value) : 1))
const seasons = computed(() => (m.value ? seerr.seasonNumbers(m.value) : []))
const seasonState = computed(() => (m.value ? seerr.seasonStatus(m.value) : {}))
const requestable = computed(() => (seerr.isTv(m.value || {}) ? seasons.value.some((n) => canAsk(seasonState.value[n])) : seerr.requestable(status.value)))
const progress = computed(() => seerr.downloadProgress(m.value?.mediaInfo))
const cast = computed(() => (m.value?.credits?.cast || []).slice(0, 20))
const pillLabel = (s, p) => (p !== null && p !== undefined && s !== 5 ? `Downloading ${Math.round(p * 100)}%` : seerr.statusLabel(s))

function toggle(n) {
  const s = new Set(chosen.value)
  s.has(n) ? s.delete(n) : s.add(n)
  chosen.value = s
}

async function request() {
  sending.value = true
  try {
    const tv = seerr.isTv(m.value)
    const approved = await seerr.request(m.value, tv ? [...chosen.value].sort((a, b) => a - b) : undefined)
    const t = seerr.title(m.value)
    say(approved ? `${t} requested. It will show up in your library once it has downloaded.` : `${t} requested. It downloads once it has been approved.`)
    bump()
    await load()
  } catch (e) {
    say(`Request failed: ${e.message}`)
  }
  sending.value = false
}
</script>

<template>
  <DiscoverConnect v-if="!seerr.seerrReady.value" />
  <div v-else-if="error" class="center"><p class="danger">{{ error }} <button class="btn flat" @click="load">Try again</button></p></div>
  <div v-else-if="!m" class="center"><span class="spinner" /></div>
  <main v-else class="sd">
    <section class="hero">
      <img v-if="m.backdropPath" class="art" :src="seerr.image(m.backdropPath, 'w1280')" alt="" />
      <div class="fade" />
    </section>
    <div class="body">
      <Pic class="poster" :src="seerr.image(m.posterPath, 'w500')" :fallback="seerr.title(m)" eager />
      <div class="info">
        <h1>{{ seerr.title(m) }}</h1>
        <div class="meta">
          <span v-if="m.voteAverage > 0" class="match">{{ Math.round(m.voteAverage * 10) }}% match</span>
          <span v-if="seerr.year(m)">{{ seerr.year(m) }}</span>
          <span class="tag">{{ seerr.isTv(m) ? 'SERIES' : 'FILM' }}</span>
          <span v-if="seerr.isTv(m) && seasons.length">{{ seasons.length }} Season{{ seasons.length > 1 ? 's' : '' }}</span>
          <span v-if="!seerr.isTv(m) && m.runtime > 0">{{ duration(m.runtime * 60) }}</span>
          <span v-if="status > 1" class="pill" :class="`s${status}`">{{ pillLabel(status, progress) }}</span>
        </div>
        <div v-if="scores.imdb || scores.critics || scores.audience" class="ratings">
          <a v-if="scores.imdb" :href="scores.imdbUrl" target="_blank" rel="noopener"><span class="imdb">IMDb</span> <b>{{ Number(scores.imdb).toFixed(1) }}</b></a>
          <span v-if="scores.critics">🍅 <b>{{ scores.critics }}%</b> <span class="mute small">critics</span></span>
          <span v-if="scores.audience">🍿 <b>{{ scores.audience }}%</b> <span class="mute small">audience</span></span>
        </div>
        <p v-if="seerr.genreNames(m).length" class="dim">{{ seerr.genreNames(m).join('  •  ') }}</p>
        <p v-if="m.tagline" class="tagline">{{ m.tagline }}</p>
        <p class="overview">{{ m.overview }}</p>
        <div class="acts">
          <router-link v-if="seerr.jellyfinId(m) && (status === 5 || status === 4)" :to="`/item/${seerr.jellyfinId(m)}`" class="btn">
            <Icon name="play" :size="24" /> Watch on Hevyfin
          </router-link>
          <button v-if="seerr.trailerUrl(m)" class="btn ghost" @click="trailer = seerr.trailerUrl(m)"><Icon name="trailer" /> Trailer</button>
          <button v-if="requestable" class="btn orange" :disabled="sending || (seerr.isTv(m) && !chosen.size)" @click="request">
            <Icon name="plus" /> {{ sending ? 'Requesting…' : seerr.isTv(m) ? `Request ${chosen.size} season${chosen.size === 1 ? '' : 's'}` : 'Request' }}
          </button>
        </div>

        <template v-if="seerr.isTv(m) && seasons.length">
          <h2>Seasons</h2>
          <div class="seasons">
            <label v-for="n in seasons" :key="n" class="season" :class="{ off: !canAsk(seasonState[n]) }">
              <input type="checkbox" :checked="canAsk(seasonState[n]) ? chosen.has(n) : true" :disabled="!canAsk(seasonState[n])" @change="toggle(n)" />
              <b>Season {{ n }}</b>
              <span v-if="(seasonState[n] ?? 1) > 1" class="pill" :class="`s${seasonState[n]}`">{{ seerr.statusLabel(seasonState[n]) }}</span>
            </label>
          </div>
        </template>

        <template v-if="cast.length">
          <h2>Cast</h2>
          <div class="cast">
            <router-link v-for="p in cast" :key="p.id" :to="`/person/tmdb/${p.id}?name=${encodeURIComponent(p.name || '')}`" class="person">
              <Pic :src="seerr.image(p.profilePath, 'w185')" :fallback="(p.name || '').split(' ').map((s) => s[0]).join('')" class="face" />
              <b>{{ p.name }}</b>
              <span class="dim small">{{ p.character }}</span>
            </router-link>
          </div>
        </template>
      </div>
    </div>
    <Row title="More like this" :load="() => seerr.recommendations(type, Number(tmdb))" v-slot="{ item }"><SeerrCard :media="item" /></Row>
    <TrailerDialog v-if="trailer" :url="trailer" @close="trailer = null" />
  </main>
</template>

<style scoped>
.sd { padding-bottom: 60px; }
.hero { position: relative; height: clamp(340px, 40vw, 62vh); }
.art { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; object-position: top center; animation: fade .5s; }
.fade { position: absolute; inset: 0; background: linear-gradient(transparent 0, rgba(14, 14, 14, .4) 50%, var(--bg)); }
.body { display: flex; gap: 36px; padding: 0 var(--pad) 30px; }
.poster { width: 220px; aspect-ratio: 2 / 3; flex: none; margin-top: -120px; box-shadow: 0 10px 40px rgba(0, 0, 0, .6); }
.info { display: grid; gap: 12px; align-content: start; min-width: 0; flex: 1; }
h1 { font-size: 44px; font-weight: 900; }
h2 { font-size: 20px; margin-top: 18px; }
.meta { display: flex; flex-wrap: wrap; gap: 8px 12px; align-items: center; color: var(--dim); font-weight: 600; }
.match { color: var(--orange); font-weight: 800; }
.tag { border: 1px solid rgba(255, 255, 255, .45); border-radius: 3px; padding: 0 6px; font-size: 12px; line-height: 20px; }
.pill { border: 1px solid #b98cff; color: #b98cff; border-radius: 20px; padding: 2px 10px; font-size: 12.5px; font-weight: 700; }
.pill.s3 { border-color: var(--orange); color: var(--orange); }
.pill.s4, .pill.s5 { border-color: #2ecc71; color: #2ecc71; }
.ratings { display: flex; gap: 18px; flex-wrap: wrap; align-items: center; }
.imdb { background: #f5c518; color: #000; font-weight: 900; font-size: 12px; border-radius: 3px; padding: 0 5px; }
.tagline { font-style: italic; color: var(--dim); }
.overview { font-size: 16px; line-height: 1.5; max-width: 760px; }
.acts { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 8px; }
.seasons { display: grid; gap: 4px; max-width: 520px; }
.season { display: flex; align-items: center; gap: 12px; padding: 8px 4px; border-bottom: 1px solid var(--line); cursor: pointer; }
.season input { width: 18px; height: 18px; }
.season b { flex: 1; }
.season.off { cursor: default; color: var(--dim); }
.cast { display: flex; gap: 12px; overflow-x: auto; padding-bottom: 8px; }
.person { width: 90px; flex: none; display: grid; gap: 4px; text-align: center; }
.face { width: 80px; height: 80px; border-radius: 50%; justify-self: center; }
.person:hover .face { outline: 3px solid var(--orange); }
.person b { font-size: 12.5px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.person .small { display: -webkit-box; -webkit-line-clamp: 2; line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
@media (max-width: 800px) { .poster { display: none; } }
</style>
