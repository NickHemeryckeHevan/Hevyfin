<script setup>
// Netflix's "Top 10": a huge outlined rank beside the poster.
import Pic from './Pic.vue'
import * as jf from '../api/jellyfin.js'
import { displayTitle } from '../lib/item.js'
defineProps({ item: Object, rank: Number })
</script>

<template>
  <router-link :to="`/item/${item.Id}`" class="top10" :class="{ ten: rank === 10 }">
    <span class="rank">{{ rank }}</span>
    <Pic :src="jf.poster(item, 280)" :hash="jf.blurHash(item)" :fallback="displayTitle(item)" class="art" />
  </router-link>
</template>

<style scoped>
.top10 { position: relative; display: block; width: 230px; height: 210px; transition: transform .2s; }
.top10.ten { width: 270px; }
.top10:hover { transform: scale(1.04); }
.rank { position: absolute; left: 0; bottom: -30px; font-size: 200px; font-weight: 900; line-height: 1; letter-spacing: -18px; color: var(--bg);
  -webkit-text-stroke: 4px var(--orange); }
.art { position: absolute; right: 0; top: 0; height: 100%; aspect-ratio: 2 / 3; }
</style>
