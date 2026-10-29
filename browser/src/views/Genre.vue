<script setup>
// Everything in one genre, sorted how you like.
import { ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import PosterCard from '../components/PosterCard.vue'
import * as jf from '../api/jellyfin.js'

const props = defineProps({ name: String })
const route = useRoute()
const SORTS = { Random: 'Surprise me', DateCreated: 'Recently added', PremiereDate: 'Release date', CommunityRating: 'Rating', SortName: 'A–Z' }
const sort = ref('Random')
const items = ref(null)
document.title = `${props.name} · Hevyfin`
watch(sort, async (s) => {
  items.value = null
  const types = route.query.type ? [route.query.type] : ['Movie', 'Series']
  items.value = await jf.items({ types, genre: props.name, sortBy: s, sortOrder: s === 'SortName' ? 'Ascending' : 'Descending' })
}, { immediate: true })
</script>

<template>
  <main class="page">
    <div class="head">
      <h1 class="page-title">{{ name }}</h1>
      <select v-model="sort" class="sort"><option v-for="(l, k) in SORTS" :key="k" :value="k">{{ l }}</option></select>
    </div>
    <div v-if="!items" class="center"><span class="spinner" /></div>
    <p v-else-if="!items.length" class="empty">Nothing here yet.</p>
    <div v-else class="grid"><PosterCard v-for="i in items" :key="i.Id" :item="i" class="fill" /></div>
  </main>
</template>

<style scoped>
.head { display: flex; align-items: center; gap: 20px; }
.head h1 { margin: 0; }
.sort { width: auto; min-height: 36px; padding: 4px 10px; }
.grid { margin-top: 20px; }
.fill { width: 100% !important; }
</style>
