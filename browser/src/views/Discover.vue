<script setup>
// New & Popular: browse TMDb through Seerr and request what isn't on the server yet (port of
// lib/ui/pages/discover.dart). The tab is in the address (?tab=requests opens My Requests);
// the grids load the next page as the end comes into view.
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import SeerrCard from '../components/SeerrCard.vue'
import Pic from '../components/Pic.vue'
import DiscoverConnect from '../components/DiscoverConnect.vue'
import * as seerr from '../api/seerr.js'

const TABS = { trending: 'Trending', movies: 'Movies', shows: 'Shows', upcoming: 'Coming Soon', requests: 'My Requests' }
const route = useRoute()
const router = useRouter()
const tab = computed(() => (TABS[route.query.tab] ? route.query.tab : 'trending'))
const genre = ref(null)
const genres = ref([])
const items = ref([])
const loading = ref(false)
const error = ref('')
const requests = ref(null)
const end = ref(null)
let page = 0, done = false, seen = new Set(), run = 0, watcher
document.title = 'New & Popular · Hevyfin'

const pick = (t) => router.replace({ query: t === 'trending' ? {} : { tab: t } })

/** Coming soon: films and shows taking turns. */
async function upcoming(p) {
  const [m, t] = await Promise.all([seerr.upcomingMovies(p), seerr.upcomingTv(p)])
  const out = []
  for (let i = 0; i < 20; i++) {
    if (m[i]) out.push(m[i])
    if (t[i]) out.push(t[i])
  }
  return out
}

function load(p) {
  if (tab.value === 'trending') return seerr.trending(p)
  if (tab.value === 'movies') return seerr.popularMovies(p, genre.value ?? undefined)
  if (tab.value === 'shows') return seerr.popularTv(p, genre.value ?? undefined)
  return upcoming(p)
}

async function more() {
  if (loading.value || done || tab.value === 'requests') return
  const mine = run
  loading.value = true
  try {
    const next = await load(page + 1)
    if (mine !== run) return
    page++
    if (!next.length || page >= 10) done = true
    for (const m of next) {
      const key = seerr.mediaType(m) + m.id
      if (!seen.has(key)) seen.add(key), items.value.push(m)
    }
    error.value = ''
  } catch (e) {
    if (mine === run) error.value = e.message
  }
  if (mine === run) loading.value = false
  // Still room on the screen: the next page straight away.
  if (mine === run && !done && end.value && end.value.getBoundingClientRect().top < innerHeight + 600) more()
}

async function loadRequests() {
  requests.value = null
  const list = await seerr.myRequests().catch(() => [])
  await Promise.all(list.map(async (r) => (r.details = await seerr.details(r.type, r.media.tmdbId).catch(() => null))))
  requests.value = list
}

async function loadGenres(type) {
  genres.value = []
  genres.value = await seerr.genres(type).catch(() => [])
}

function reset() {
  run++
  page = 0
  done = false
  seen = new Set()
  items.value = []
  loading.value = false
  error.value = ''
}

watch([tab, () => seerr.seerrReady.value], ([t, ready], old) => {
  if (!ready) return
  if (!old || t !== old[0]) genre.value = null
  reset()
  if (t === 'requests') return loadRequests()
  if (t === 'movies' || t === 'shows') loadGenres(t === 'movies' ? 'movie' : 'tv')
  more()
}, { immediate: true })
watch(genre, () => {
  reset()
  more()
})

watch(end, (el) => {
  watcher?.disconnect()
  if (!el) return
  watcher = new IntersectionObserver((e) => e[0].isIntersecting && more(), { rootMargin: '800px 0px' })
  watcher.observe(el)
})
onBeforeUnmount(() => watcher?.disconnect())

const ago = (s) => {
  const m = Math.round((Date.now() - new Date(s)) / 60000)
  return m >= 1440 ? `${Math.round(m / 1440)}d ago` : m >= 60 ? `${Math.round(m / 60)}h ago` : `${m}m ago`
}
const what = (r) => (r.type === 'tv' ? (r.seasons?.length ? `Season${r.seasons.length > 1 ? 's' : ''} ${r.seasons.map((s) => s.seasonNumber).join(', ')}` : 'Series') : 'Movie')
const colour = (label) => ({ Available: 'good', 'Partly available': 'good', Downloading: 'busy', Declined: 'bad', Failed: 'bad' })[label] || 'wait'
const link = (r) => (r.details && seerr.status(r.details) === 5 && seerr.jellyfinId(r.details) ? `/item/${seerr.jellyfinId(r.details)}` : `/request/${r.type}/${r.media.tmdbId}`)
</script>

<template>
  <DiscoverConnect v-if="!seerr.seerrReady.value" />
  <main v-else class="page">
    <h1 class="page-title">New & Popular</h1>
    <div class="chips">
      <button v-for="(label, t) in TABS" :key="t" class="chip" :class="{ on: tab === t }" @click="pick(t)">{{ label }}</button>
    </div>
    <div v-if="(tab === 'movies' || tab === 'shows') && genres.length" class="chips genres">
      <button class="chip small" :class="{ on: genre === null }" @click="genre = null">All</button>
      <button v-for="g in genres" :key="g.id" class="chip small" :class="{ on: genre === g.id }" @click="genre = g.id">{{ g.name }}</button>
    </div>

    <template v-if="tab === 'requests'">
      <div v-if="!requests" class="center"><span class="spinner" /></div>
      <p v-else-if="!requests.length" class="empty">You haven't requested anything yet.</p>
      <div v-else class="requests">
        <router-link v-for="r in requests" :key="r.id" :to="link(r)" class="req">
          <Pic :src="seerr.image(r.details?.posterPath, 'w185')" :fallback="r.details ? seerr.title(r.details) : '?'" class="p" />
          <div class="t">
            <b>{{ r.details ? seerr.title(r.details) : `TMDB ${r.media.tmdbId}` }}</b>
            <span class="dim">{{ [r.details && seerr.year(r.details), what(r), r.createdAt && `requested ${ago(r.createdAt)}`].filter(Boolean).join('  •  ') }}</span>
            <div class="state">
              <span class="pill" :class="colour(seerr.requestLabel(r))">
                {{ seerr.requestLabel(r) === 'Downloading' && seerr.downloadProgress(r.media) !== null
                  ? `Downloading ${Math.round(seerr.downloadProgress(r.media) * 100)}%` : seerr.requestLabel(r) }}
              </span>
              <div v-if="seerr.requestLabel(r) === 'Downloading' && seerr.downloadProgress(r.media) !== null" class="prog">
                <i :style="{ width: seerr.downloadProgress(r.media) * 100 + '%' }" />
              </div>
            </div>
          </div>
        </router-link>
      </div>
    </template>

    <template v-else>
      <p v-if="error && !items.length" class="empty danger">{{ error }} <button class="btn flat" @click="more">Try again</button></p>
      <div class="grid"><SeerrCard v-for="m in items" :key="seerr.mediaType(m) + m.id" :media="m" class="fill" /></div>
      <div ref="end" class="end"><span v-if="loading" class="spinner" /></div>
    </template>
  </main>
</template>

<style scoped>
.genres { margin-top: 12px; }
.chip.small { padding: 4px 12px; font-size: 13px; background: none; }
.chip.small.on { background: #fff; }
.grid { margin-top: 20px; }
.fill { width: 100% !important; }
.end { display: grid; place-items: center; min-height: 80px; }
.requests { display: grid; gap: 10px; margin-top: 20px; max-width: 900px; }
.req { display: flex; gap: 16px; height: 120px; background: var(--surface); border-radius: var(--radius); overflow: hidden; }
.req:hover { background: var(--hover); }
.p { width: 80px; flex: none; border-radius: 0; }
.t { display: flex; flex-direction: column; gap: 4px; padding: 12px 16px 12px 0; flex: 1; min-width: 0; }
.t b { font-size: 17px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.t .dim { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.state { margin-top: auto; display: flex; align-items: center; gap: 12px; }
.pill { padding: 3px 10px; border-radius: 20px; font-weight: 700; font-size: 12.5px; color: #b98cff; background: rgba(185, 140, 255, .15); white-space: nowrap; }
.pill.good { color: #2ecc71; background: rgba(46, 204, 113, .15); }
.pill.busy { color: var(--orange); background: rgba(255, 122, 26, .15); }
.pill.bad { color: var(--danger); background: rgba(255, 84, 112, .15); }
.prog { flex: 1; max-width: 300px; height: 4px; background: rgba(255, 255, 255, .2); border-radius: 2px; overflow: hidden; }
.prog i { display: block; height: 100%; background: var(--orange); }
</style>
