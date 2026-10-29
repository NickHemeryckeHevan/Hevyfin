<script setup>
// Home: a billboard, then rows (port of lib/ui/pages/home.dart). Rows load as they come near
// the screen; the ones from last time show at once.
import { onMounted, ref } from 'vue'
import Billboard from '../components/Billboard.vue'
import Row from '../components/Row.vue'
import PosterCard from '../components/PosterCard.vue'
import WideCard from '../components/WideCard.vue'
import Top10Card from '../components/Top10Card.vue'
import SeerrCard from '../components/SeerrCard.vue'
import * as jf from '../api/jellyfin.js'
import * as seerr from '../api/seerr.js'
import { cached, keep } from '../state/rows.js'
import { seasonalRows, shuffle } from '../lib/seasons.js'
import { isEpisode, isSeries, played, tmdbId } from '../lib/item.js'

const billboard = ref(null)
const because = ref([])
const genres = ref([])

onMounted(async () => {
  // A pick from the last pool shows at once; the pool is refreshed for next time.
  const pool = (cached('billboard') || []).filter((i) => i.BackdropImageTags?.length)
  const fresh = Promise.all([jf.latest('Movie', 12), jf.latest('Series', 12)]).then(([m, s]) => {
    const all = [...m, ...s].filter((i) => i.BackdropImageTags?.length)
    keep('billboard', all)
    return all
  })
  const usable = pool.length ? pool : await fresh.catch(() => [])
  billboard.value = usable[Math.floor(Math.random() * usable.length)] || null
  becauseYouWatched().catch(() => {})
  jf.genres().then((g) => (genres.value = shuffle(g).slice(0, 6))).catch(() => {})
})

/** The last three distinct things watched: a film, or the show an episode belongs to. */
async function becauseYouWatched() {
  const recent = [...(await jf.resume(10)), ...(await jf.recentlyWatched(40))]
  const seen = new Set(), sources = []
  for (const i of recent) {
    const key = isEpisode(i) ? i.SeriesId : i.Id
    if (!key || seen.has(key)) continue
    seen.add(key)
    sources.push(isEpisode(i) ? await jf.item(key) : i)
    if (sources.length === 3) break
  }
  because.value = sources
}

const newest = async () => {
  const [m, s] = await Promise.all([jf.latest('Movie', 20), jf.latest('Series', 20)])
  return [...m, ...s].sort((a, b) => String(b.DateCreated).localeCompare(String(a.DateCreated)))
}
const top10 = (type) => () => jf.items({ types: [type], sortBy: 'CommunityRating', sortOrder: 'Descending', limit: 10 })
const recommend = (src) => async () =>
  (await seerr.recommendations(isSeries(src) ? 'tv' : 'movie', tmdbId(src))).filter((m) => seerr.requestable(seerr.status(m)) && m.posterPath).slice(0, 20)
</script>

<template>
  <main class="home">
    <Billboard v-if="billboard" :item="billboard" :eyebrow="isSeries(billboard) ? 'Series' : 'Film'" />
    <div v-else class="spacer" />
    <div class="rows">
      <Row title="Continue Watching" cache-key="resume" :load="() => jf.resume()" shape="wide" v-slot="{ item }"><WideCard :item="item" /></Row>
      <Row title="Next Up" cache-key="nextup" :load="() => jf.nextUp()" shape="wide" v-slot="{ item }"><WideCard :item="item" /></Row>
      <Row title="New on Hevyfin" cache-key="new" :load="newest" v-slot="{ item }"><PosterCard :item="item" /></Row>
      <Row v-for="r in seasonalRows()" :key="r.title" :title="r.title" :subtitle="r.subtitle" :min-items="3"
           :load="async () => shuffle((await jf.everything()).filter(r.pick))" v-slot="{ item }"><PosterCard :item="item" /></Row>
      <Row title="Collections" cache-key="collections" :load="() => jf.collections()" more="/collections" v-slot="{ item }"><PosterCard :item="item" /></Row>
      <template v-for="(src, n) in because" :key="src.Id">
        <Row subtitle="Because you watched" :title="src.Name" :min-items="3"
             :load="async () => (await jf.similar(src.Id, 24)).filter((i) => !played(i))" v-slot="{ item }"><PosterCard :item="item" /></Row>
        <Row v-if="seerr.seerrReady.value && tmdbId(src) && n < 2" :subtitle="`More like ${src.Name}`" title="– request it" :load="recommend(src)" v-slot="{ item }">
          <SeerrCard :media="item" />
        </Row>
      </template>
      <Row title="Top 10 Movies in Your Library" cache-key="top-movies" :load="top10('Movie')" shape="top10" v-slot="{ item, index }"><Top10Card :item="item" :rank="index + 1" /></Row>
      <Row v-for="g in genres.slice(0, 3)" :key="g.id" :title="g.name" :min-items="4" :more="`/genre/${encodeURIComponent(g.name)}`"
           :load="() => jf.items({ genre: g.name, sortBy: 'Random', limit: 24 })" v-slot="{ item }"><PosterCard :item="item" /></Row>
      <Row title="Top 10 Shows in Your Library" cache-key="top-shows" :load="top10('Series')" shape="top10" v-slot="{ item, index }"><Top10Card :item="item" :rank="index + 1" /></Row>
      <Row subtitle="Watch it again:" title="Back on the Shelf" :load="() => jf.items({ types: ['Movie'], filters: 'IsPlayed', sortBy: 'Random', limit: 20 })" v-slot="{ item }">
        <PosterCard :item="item" />
      </Row>
      <Row v-for="g in genres.slice(3)" :key="g.id" :title="g.name" :min-items="4" :more="`/genre/${encodeURIComponent(g.name)}`"
           :load="() => jf.items({ genre: g.name, sortBy: 'Random', limit: 24 })" v-slot="{ item }"><PosterCard :item="item" /></Row>
      <Row v-if="seerr.seerrReady.value" title="Trending Now – Not on Hevyfin Yet" more="/new"
           :load="async () => (await seerr.trending()).filter((m) => seerr.status(m) !== 5)" v-slot="{ item }"><SeerrCard :media="item" /></Row>
    </div>
  </main>
</template>

<style scoped>
.home { padding-bottom: 60px; }
.spacer { height: calc(var(--bar) + 30px); }
.rows { position: relative; z-index: 1; }
</style>
