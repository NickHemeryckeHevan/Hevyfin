<script setup>
// Every franchise as a poster wall, universes first, with how far you are in each.
import { ref } from 'vue'
import PosterCard from '../components/PosterCard.vue'
import * as jf from '../api/jellyfin.js'

const boxes = ref(null)
document.title = 'Collections · Hevyfin'
jf.collections().then((l) => (boxes.value = l))
</script>

<template>
  <main class="page">
    <h1 class="page-title">Collections</h1>
    <div v-if="!boxes" class="center"><span class="spinner" /></div>
    <div v-else class="grid"><PosterCard v-for="b in boxes" :key="b.Id" :item="b" class="fill" /></div>
  </main>
</template>

<style scoped>
.fill { width: 100% !important; }
</style>
