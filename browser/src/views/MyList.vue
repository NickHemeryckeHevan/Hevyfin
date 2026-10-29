<script setup>
// My List: Jellyfin favourites, newest first.
import { ref } from 'vue'
import PosterCard from '../components/PosterCard.vue'
import * as jf from '../api/jellyfin.js'

const items = ref(null)
document.title = 'My List · Hevyfin'
jf.items({ filters: 'IsFavorite', sortBy: 'DateCreated', sortOrder: 'Descending' }).then((l) => (items.value = l))
</script>

<template>
  <main class="page">
    <h1 class="page-title">My List</h1>
    <div v-if="!items" class="center"><span class="spinner" /></div>
    <p v-else-if="!items.length" class="empty">Nothing in your list yet. Add films and shows with + on their page.</p>
    <div v-else class="grid"><PosterCard v-for="i in items" :key="i.Id" :item="i" class="fill" /></div>
  </main>
</template>

<style scoped>
.fill { width: 100% !important; }
</style>
