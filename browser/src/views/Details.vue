<script setup>
// A film or a show: art, Play, the actions, the story and credits, then Episodes / Collection
// / More Like This / Cast (port of lib/ui/pages/details.dart). A collection gets its own page.
// Opened from a universe's path (?in=box), a stop shows what came before, and a season the
// path makes a mini series opens as one.
import { computed, defineAsyncComponent, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import Icon from '../components/Icon.vue'
import MetaLine from '../components/MetaLine.vue'
import Ratings from '../components/Ratings.vue'
import Episodes from '../components/Episodes.vue'
import CollectionList from '../components/CollectionList.vue'
import PosterCard from '../components/PosterCard.vue'
import Pic from '../components/Pic.vue'
import TrailerDialog from '../components/TrailerDialog.vue'
import * as jf from '../api/jellyfin.js'
import * as seerr from '../api/seerr.js'
import { isCollection, isEpisode, isMovie, isSeason, isSeries, isUniverse, played, remoteTrailer, resumeAt, tagline, tmdbId } from '../lib/item.js'
import { playRoute } from '../lib/play.js'
import { bump, myList, say, toggleMyList } from '../state/session.js'

const CollectionPage = defineAsyncComponent(() => import('../components/CollectionPage.vue'))
const props = defineProps({ id: String })
const route = useRoute()
const router = useRouter()
const item = ref(null)
const error = ref('')
const tab = ref('')
const franchise = ref(null)
const partOf = ref([])
const similar = ref(null)
const localTrailer = ref(null)
const youtube = ref(null)
const missing = ref(null)
const logoFailed = ref(false)

onMounted(async () => {
  try {
    let i = await jf.item(props.id)
    const box = route.query.in
    const onPath = box ? await jf.onPath(i, box).catch(() => null) : null
    if (onPath) i = onPath
    // An episode or season opens its show, on that season.
    else if ((isEpisode(i) || isSeason(i)) && i.SeriesId) i = { ...(await jf.item(i.SeriesId)), OpenSeasonId: isSeason(i) ? i.Id : i.SeasonId }
    item.value = i
    document.title = `${i.Name} · Hevyfin`
    if (isCollection(i)) return
    tab.value = isSeries(i) ? 'Episodes' : 'More Like This'
    jf.collectionsOf(i.Id).then((l) => {
      partOf.value = l
      if (isMovie(i) && l[0]) franchise.value = l[0]
    }).catch(() => {})
    jf.similar(i.Id, 18).then((s) => (similar.value = s)).catch(() => (similar.value = []))
    jf.libraryTrailer(i).then((t) => (localTrailer.value = t)).catch(() => {})
    if (isSeries(i) && !i.PathStop?.mini && seerr.seerrReady.value && tmdbId(i)) missingSeasons(i)
  } catch (e) {
    error.value = e.message
  }
})

const mini = computed(() => (item.value?.PathStop?.mini ? item.value.PathStop : null))
const cast = computed(() => (item.value?.People || []).filter((p) => p.Type === 'Actor'))
const tabs = computed(() => {
  const i = item.value
  if (!i) return []
  return [isSeries(i) && 'Episodes', franchise.value && 'Collection', 'More Like This', cast.value.length && 'Cast'].filter(Boolean)
})
const credits = computed(() => {
  const ppl = item.value?.People || [], names = (t, n = 9) => ppl.filter((p) => t.includes(p.Type)).slice(0, n).map((p) => p.Name)
  return [
    ['Cast', names(['Actor'], 5)],
    ['Genres', item.value?.Genres || []],
    isSeries(item.value) ? ['Creators', names(['Writer', 'Creator'], 3)] : ['Director', names(['Director'])],
    isSeries(item.value) && item.value.Status ? ['Status', [item.value.Status === 'Continuing' ? 'Still airing' : 'Ended']] : null,
  ].filter((x) => x && x[1].length)
})
const watched = computed(() => (mini.value ? jf.stopPlayed(mini.value) : played(item.value)))
const resumable = computed(() => !isSeries(item.value) && resumeAt(item.value) > 0 && !played(item.value))
const trailer = computed(() => localTrailer.value || remoteTrailer(item.value))

async function play() {
  try {
    const to = await playRoute(item.value)
    to ? router.push(to) : say('Nothing to play yet')
  } catch (e) {
    say(e.message)
  }
}

function openTrailer() {
  if (localTrailer.value) router.push(`/play/${localTrailer.value}?trailer=1&name=${encodeURIComponent(item.value.Name)}`)
  else youtube.value = remoteTrailer(item.value)
}

async function myListToggle() {
  try {
    await toggleMyList(item.value.Id)
  } catch (e) {
    say(`Could not update My List: ${e.message}`)
  }
}

async function setWatched() {
  const on = !watched.value
  await Promise.all((mini.value?.parts || [item.value]).map((p) => jf.setPlayed(p.Id, on)))
  bump()
}

/** "Request season 3" when Seerr knows seasons the library is missing. */
async function missingSeasons(i) {
  try {
    const m = await seerr.details('tv', tmdbId(i))
    const st = seerr.seasonStatus(m)
    const miss = seerr.seasonNumbers(m).filter((n) => seerr.requestable(st[n] ?? 1) && st[n] !== 4)
    const pend = seerr.seasonNumbers(m).filter((n) => st[n] === 2 || st[n] === 3)
    if (!miss.length && !pend.length) return
    const s = (l) => (l.length > 1 ? 's' : '')
    missing.value = miss.length
      ? `Request season${s(miss)} ${miss.length > 4 ? `${miss[0]}–${miss.at(-1)}` : miss.join(', ')}`
      : `Season${s(pend)} ${pend.join(', ')} on the way`
  } catch {}
}
</script>

<template>
  <div v-if="error" class="center"><p class="danger">{{ error }}</p></div>
  <div v-else-if="!item" class="center"><span class="spinner" /></div>
  <CollectionPage v-else-if="isCollection(item)" :box="item" :universe="isUniverse(item)" />
  <main v-else class="details">
    <section class="hero">
      <img v-if="jf.backdrop(item)" class="art" :src="jf.backdrop(item, 1920)" alt="" fetchpriority="high" />
      <div class="fade" />
      <div class="head">
        <img v-if="jf.logo(item) && !logoFailed" class="logo" :src="jf.logo(item, 700)" :alt="item.Name" @error="logoFailed = true" />
        <h1 v-else class="title">{{ item.Name }}</h1>
        <div v-if="mini" class="mini">{{ (mini.title !== mini.item.Name ? `${mini.title} · ${mini.code}` : mini.code || '').toUpperCase() }}</div>
      </div>
      <Pic v-if="mini?.season" class="season" :src="jf.poster(mini.season, 460)" :fallback="mini.season.Name" />
    </section>

    <div class="body">
      <div class="acts">
        <button class="btn" @click="play"><Icon name="play" :size="24" /> {{ resumable ? 'Resume' : 'Play' }}</button>
        <button v-if="trailer" class="round" title="Trailer" @click="openTrailer"><Icon name="trailer" /></button>
        <button class="round" :class="{ on: myList.has(item.Id) }" :title="myList.has(item.Id) ? 'In My List' : 'Add to My List'" @click="myListToggle">
          <Icon :name="myList.has(item.Id) ? 'check' : 'plus'" />
        </button>
        <button class="round" :class="{ on: watched }" :title="watched ? 'Watched' : 'Mark watched'" @click="setWatched"><Icon name="check" /></button>
        <router-link v-if="missing" :to="`/request/tv/${tmdbId(item)}`" class="btn ghost request">{{ missing }}</router-link>
      </div>

      <div class="about">
        <div class="story">
          <MetaLine :item="item" />
          <Ratings :item="item" />
          <p v-if="tagline(item)" class="tagline">{{ tagline(item) }}</p>
          <div v-if="item.PathStop?.previously" class="previously">
            <b>PREVIOUSLY</b>
            <p>{{ item.PathStop.previously }}</p>
          </div>
          <p class="overview">{{ item.Overview }}</p>
          <div v-if="partOf.length" class="partof">
            <span class="mute small">Part of</span>
            <router-link v-for="b in partOf" :key="b.Id" :to="`/item/${b.Id}`" class="pill" :class="{ uni: isUniverse(b) }">{{ b.Name }} ›</router-link>
          </div>
        </div>
        <div class="credits">
          <p v-for="[k, v] in credits" :key="k"><span class="mute">{{ k }}: </span>{{ v.join(', ') }}</p>
        </div>
      </div>

      <nav class="tabs">
        <button v-for="t in tabs" :key="t" :class="{ on: tab === t }" @click="tab = t">{{ t }}</button>
      </nav>
      <Episodes v-if="tab === 'Episodes'" :series="item" />
      <CollectionList v-else-if="tab === 'Collection'" :collection="franchise" :current="item.Id" />
      <div v-else-if="tab === 'Cast'" class="cast">
        <router-link v-for="p in cast.slice(0, 30)" :key="p.Id" :to="`/person/${p.Id}?name=${encodeURIComponent(p.Name)}`" class="person">
          <Pic :src="jf.personImage(p, 300)" :fallback="p.Name.split(' ').map((s) => s[0]).join('')" class="face" />
          <b>{{ p.Name }}</b>
          <span class="dim small">{{ p.Role }}</span>
        </router-link>
      </div>
      <template v-else>
        <p v-if="similar && !similar.length" class="mute">Nothing similar in your library yet.</p>
        <div v-else class="grid"><PosterCard v-for="i in similar || []" :key="i.Id" :item="i" :width="200" class="fill" /></div>
      </template>
    </div>
    <TrailerDialog v-if="youtube" :url="youtube" @close="youtube = null" />
  </main>
</template>

<style scoped>
.details { padding-bottom: 80px; }
.hero { position: relative; height: clamp(380px, 45vw, 72vh); }
.art { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; object-position: top center; animation: fade .5s; }
.fade { position: absolute; inset: 0; background: linear-gradient(transparent 0, rgba(14, 14, 14, .3) 50%, var(--bg)), linear-gradient(90deg, rgba(0, 0, 0, .9), transparent 60%); }
.head { position: absolute; left: var(--pad); right: var(--pad); bottom: 8px; }
.logo { max-height: 140px; max-width: 440px; object-fit: contain; object-position: left bottom; filter: drop-shadow(0 2px 12px rgba(0, 0, 0, .5)); }
.title { font-size: 52px; font-weight: 900; letter-spacing: -1px; text-shadow: 0 2px 16px #000; max-width: 70%; }
.mini { margin-top: 10px; color: var(--orange); font-weight: 800; letter-spacing: 2.5px; font-size: 15px; }
.season { position: absolute; right: var(--pad); bottom: 8px; width: clamp(120px, 14vw, 230px); aspect-ratio: 2 / 3; box-shadow: 0 8px 24px rgba(0, 0, 0, .6); }
.body { padding: 14px var(--pad) 0; }
.acts { display: flex; flex-wrap: wrap; gap: 12px; align-items: center; }
.acts .btn { min-width: 150px; font-size: 17px; }
.request { border: 1px solid var(--orange); color: var(--orange); background: none; }
.about { display: grid; grid-template-columns: 3fr 2fr; gap: 48px; margin: 22px 0 30px; }
.story { display: grid; gap: 12px; align-content: start; }
.tagline { font-style: italic; color: var(--dim); }
.previously { background: var(--surface-high); border-left: 3px solid var(--orange); border-radius: var(--radius); padding: 10px 14px 12px; }
.previously b { color: var(--orange); letter-spacing: 2.2px; font-size: 12px; }
.previously p { color: var(--dim); font-size: 14.5px; margin-top: 6px; }
.overview { font-size: 16px; line-height: 1.5; max-width: 820px; }
.partof { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
.pill { border: 1px solid var(--line); background: var(--surface-high); border-radius: 20px; padding: 6px 12px; font-weight: 700; font-size: 13px; }
.pill.uni { border-color: var(--orange); background: rgba(255, 122, 26, .14); }
.pill:hover { border-color: #fff; }
.credits { display: grid; gap: 10px; align-content: start; font-size: 14px; }
.tabs { display: flex; border-top: 1px solid var(--line); margin-bottom: 18px; }
.tabs button { position: relative; background: none; border: 0; padding: 16px 14px 8px; font-weight: 800; font-size: 15px; color: var(--mute); cursor: pointer; }
.tabs button:hover { color: #ddd; }
.tabs button.on { color: #fff; }
.tabs button.on::before { content: ''; position: absolute; left: 0; right: 0; top: -1px; height: 4px; background: var(--orange); }
.grid { grid-template-columns: repeat(auto-fill, minmax(170px, 1fr)); }
.fill { width: 100% !important; }
.cast { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 18px 12px; }
.person { display: grid; gap: 4px; text-align: center; }
.face { aspect-ratio: 1; border-radius: 50%; }
.person:hover .face { outline: 3px solid var(--orange); }
.person b { font-size: 13px; }
@media (max-width: 900px) { .about { grid-template-columns: 1fr; gap: 16px; } }
</style>
