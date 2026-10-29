<script setup>
// A TMDb poster from Seerr, with whether it's in the library or asked for.
import { computed } from 'vue'
import Pic from './Pic.vue'
import * as seerr from '../api/seerr.js'

const props = defineProps({ media: Object, width: { type: Number, default: 170 } })
const s = computed(() => seerr.status(props.media))
const pct = computed(() => seerr.downloadProgress(props.media.mediaInfo))
const to = computed(() =>
  s.value === 5 && seerr.jellyfinId(props.media) ? `/item/${seerr.jellyfinId(props.media)}` : `/request/${seerr.mediaType(props.media)}/${props.media.id}`,
)
</script>

<template>
  <router-link :to="to" class="sc" :style="{ width: width + 'px' }" :title="seerr.title(media)">
    <Pic :src="seerr.image(media.posterPath)" :fallback="seerr.title(media)" class="art">
      <span class="type">{{ seerr.isTv(media) ? 'SERIES' : 'FILM' }}</span>
      <span v-if="s > 1" class="state" :class="`s${s}`">{{ pct !== null && s !== 5 ? Math.round(pct * 100) + '%' : seerr.statusLabel(s) }}</span>
    </Pic>
  </router-link>
</template>

<style scoped>
.sc { display: block; transition: transform .2s; }
.sc:hover { transform: scale(1.05); }
.art { aspect-ratio: 2 / 3; }
.type { position: absolute; top: 6px; left: 6px; background: rgba(0, 0, 0, .7); border-radius: 3px; padding: 2px 6px; font-size: 9.5px; font-weight: 800; letter-spacing: 1px; }
.state { position: absolute; top: 6px; right: 6px; background: rgba(0, 0, 0, .8); border: 1px solid #b98cff; color: #b98cff; border-radius: 20px; padding: 2px 7px;
  font-size: 10.5px; font-weight: 700; max-width: 75%; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.state.s3 { border-color: var(--orange); color: var(--orange); }
.state.s4, .state.s5 { border-color: #2ecc71; color: #2ecc71; }
</style>
