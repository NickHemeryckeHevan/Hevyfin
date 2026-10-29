<script setup>
// 16:9 still with the title under it: Continue watching, Next up. A click plays.
import { computed } from 'vue'
import Pic from './Pic.vue'
import Icon from './Icon.vue'
import * as jf from '../api/jellyfin.js'
import { displayTitle, episodeCode, isEpisode, progress } from '../lib/item.js'
import { srcset } from '../lib/images.js'

const props = defineProps({ item: Object, width: { type: Number, default: 300 }, to: String })
const sub = computed(() => (isEpisode(props.item) ? `${episodeCode(props.item)}  ${props.item.Name}` : String(props.item.ProductionYear || '')))
const p = computed(() => progress(props.item))
const hash = computed(() => jf.blurHash(props.item, isEpisode(props.item) ? 'Primary' : 'Backdrop'))
</script>

<template>
  <router-link :to="to || `/play/${item.Id}`" class="wide" :style="{ width: width + 'px' }">
    <Pic :src="jf.thumb(item, width)" :srcset="srcset((w) => jf.thumb(item, w), width)" :hash="hash" :fallback="displayTitle(item)" class="art">
      <span class="play"><Icon name="play" :size="24" /></span>
      <div v-if="p" class="bar"><i :style="{ width: p * 100 + '%' }" /></div>
    </Pic>
    <div class="t">{{ displayTitle(item) }}</div>
    <div v-if="sub" class="s">{{ sub }}</div>
  </router-link>
</template>

<style scoped>
.wide { display: block; }
.art { aspect-ratio: 16 / 9; transition: transform .2s; }
.wide:hover .art { transform: scale(1.04); }
.art::after { content: ''; position: absolute; inset: 0; background: linear-gradient(transparent 50%, rgba(0, 0, 0, .6)); }
.play { position: absolute; left: 50%; top: 50%; translate: -50% -50%; z-index: 1; width: 46px; height: 46px; border-radius: 50%; display: grid; place-items: center;
  background: rgba(0, 0, 0, .45); border: 1.5px solid rgba(255, 255, 255, .7); opacity: .85; transition: opacity .2s, background .2s; }
.wide:hover .play { opacity: 1; background: var(--orange); border-color: var(--orange); color: #000; }
.t { margin-top: 8px; font-weight: 700; font-size: 14px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.s { color: var(--dim); font-size: 12.5px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
</style>
