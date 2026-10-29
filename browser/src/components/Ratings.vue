<script setup>
// IMDb and Rotten Tomatoes scores, from Seerr.
import { ref } from 'vue'
import * as seerr from '../api/seerr.js'
import { isSeries, tmdbId } from '../lib/item.js'

const props = defineProps({ item: Object })
const r = ref({})
if (seerr.seerrReady.value && tmdbId(props.item)) seerr.ratings(isSeries(props.item) ? 'tv' : 'movie', tmdbId(props.item)).then((x) => (r.value = x))
</script>

<template>
  <div v-if="r.imdb || r.critics || r.audience" class="ratings">
    <a v-if="r.imdb" :href="r.imdbUrl" target="_blank" rel="noopener" class="score"><span class="imdb">IMDb</span> <b>{{ Number(r.imdb).toFixed(1) }}</b></a>
    <span v-if="r.critics" class="score"><span>🍅</span> <b>{{ r.critics }}%</b> <span class="mute small">critics</span></span>
    <span v-if="r.audience" class="score"><span>🍿</span> <b>{{ r.audience }}%</b> <span class="mute small">audience</span></span>
  </div>
</template>

<style scoped>
.ratings { display: flex; gap: 18px; flex-wrap: wrap; animation: fade .3s; }
.score { display: inline-flex; gap: 6px; align-items: center; }
.imdb { background: #f5c518; color: #000; font-weight: 900; font-size: 12px; border-radius: 3px; padding: 0 5px; letter-spacing: -.3px; }
</style>
