<script setup>
// A portrait poster; a tap opens the title (or [to], a universe stop's page on its path).
import { computed } from 'vue'
import Pic from './Pic.vue'
import Icon from './Icon.vue'
import * as jf from '../api/jellyfin.js'
import { displayTitle, isSeries, played, progress, unplayedCount } from '../lib/item.js'
import { srcset } from '../lib/images.js'
import { myList } from '../state/session.js'

const props = defineProps({ item: Object, to: String, width: { type: Number, default: 170 }, src: String })
const link = computed(() => props.to || `/item/${props.item.Id}`)
const p = computed(() => progress(props.item))
</script>

<template>
  <router-link :to="link" class="poster" :style="{ width: width + 'px' }" :title="displayTitle(item)">
    <Pic :src="src || jf.poster(item, width)" :srcset="src ? null : srcset((w) => jf.poster(item, w), width)" :hash="jf.blurHash(item)"
         :fallback="displayTitle(item)" class="art">
      <span v-if="played(item)" class="badge tick"><Icon name="check" :size="13" /></span>
      <span v-else-if="isSeries(item) && unplayedCount(item) > 0" class="badge">{{ unplayedCount(item) }}</span>
      <span v-if="myList.has(item.Id)" class="mine"><Icon name="bookmark" :size="13" /></span>
      <div v-if="p" class="bar"><i :style="{ width: p * 100 + '%' }" /></div>
    </Pic>
  </router-link>
</template>

<style scoped>
.poster { display: block; transition: transform .2s; }
.poster:hover { transform: scale(1.05); z-index: 2; }
.art { aspect-ratio: 2 / 3; }
.mine { position: absolute; top: 6px; left: 6px; background: var(--orange); color: #000; border-radius: 50%; padding: 3px; display: grid; }
</style>
