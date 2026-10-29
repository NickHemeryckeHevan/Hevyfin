<script setup>
// Shows or Movies: a billboard, a genre picker, then new, top 10, not started, and a row per genre.
import { onMounted, ref } from 'vue'
import Billboard from '../components/Billboard.vue'
import Row from '../components/Row.vue'
import PosterCard from '../components/PosterCard.vue'
import Top10Card from '../components/Top10Card.vue'
import Icon from '../components/Icon.vue'
import * as jf from '../api/jellyfin.js'

const props = defineProps({ kind: String }) // 'Series' | 'Movie'
const label = props.kind === 'Series' ? 'Shows' : 'Movies'
const billboard = ref(null)
const genres = ref([])
const picker = ref(false)

onMounted(async () => {
  document.title = `${label} · Hevyfin`
  jf.genres([props.kind]).then((g) => (genres.value = g)).catch(() => {})
  const pool = (await jf.items({ types: [props.kind], sortBy: 'Random', limit: 20 })).filter((i) => i.BackdropImageTags?.length)
  billboard.value = pool[Math.floor(Math.random() * pool.length)] || null
})

const notStarted = async () =>
  props.kind === 'Series'
    ? (await jf.items({ types: ['Series'], filters: 'IsUnplayed', sortBy: 'Random', limit: 40 })).filter((i) => !i.UserData?.PlayedPercentage).slice(0, 20)
    : jf.items({ types: ['Movie'], filters: 'IsUnplayed', sortBy: 'Random', limit: 20 })
</script>

<template>
  <main class="browse">
    <div class="picker" @click.stop>
      <h1>{{ label }}</h1>
      <button class="genres" @click="picker = !picker">Genres <Icon name="down" :size="16" /></button>
      <div v-if="picker" class="menu cols" @click="picker = false">
        <router-link v-for="g in genres" :key="g.id" :to="`/genre/${encodeURIComponent(g.name)}?type=${kind}`">{{ g.name }}</router-link>
      </div>
    </div>
    <Billboard v-if="billboard" :item="billboard" :eyebrow="kind === 'Series' ? 'Series' : 'Film'" />
    <div v-else class="spacer" />
    <div class="rows">
      <Row :title="`New ${label}`" :cache-key="`new-${kind}`" :load="() => jf.latest(kind, 24)" v-slot="{ item }"><PosterCard :item="item" /></Row>
      <Row :title="`Top 10 ${label}`" :cache-key="`top-${kind}`" :load="() => jf.items({ types: [kind], sortBy: 'CommunityRating', sortOrder: 'Descending', limit: 10 })"
           shape="top10" v-slot="{ item, index }"><Top10Card :item="item" :rank="index + 1" /></Row>
      <Row :title="kind === 'Series' ? `Shows You Haven't Started` : `Movies You Haven't Seen`" :load="notStarted" v-slot="{ item }"><PosterCard :item="item" /></Row>
      <Row v-for="g in genres" :key="g.id" :title="g.name" :min-items="3" :more="`/genre/${encodeURIComponent(g.name)}?type=${kind}`"
           :load="() => jf.items({ types: [kind], genre: g.name, sortBy: 'Random', limit: 24 })" v-slot="{ item }"><PosterCard :item="item" /></Row>
    </div>
  </main>
</template>

<style scoped>
.browse { padding-bottom: 60px; }
.picker { position: absolute; top: calc(var(--bar) + 4px); left: var(--pad); z-index: 5; display: flex; align-items: center; gap: 22px; }
.picker h1 { font-size: 34px; font-weight: 800; text-shadow: 0 2px 10px #000; }
.genres { display: inline-flex; align-items: center; gap: 6px; background: rgba(0, 0, 0, .7); border: 1px solid #fff; padding: 4px 12px; cursor: pointer; font-weight: 600; }
.cols { left: 130px; right: auto; top: 46px; display: grid; grid-template-columns: repeat(3, 180px); }
.spacer { height: calc(var(--bar) + 80px); }
.rows { position: relative; z-index: 1; }
</style>
