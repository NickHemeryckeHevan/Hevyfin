<script setup>
// The big picture at the top of Home, Shows and Movies: logo, story, Play and More info.
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import Icon from './Icon.vue'
import MetaLine from './MetaLine.vue'
import Wordmark from './Wordmark.vue'
import * as jf from '../api/jellyfin.js'
import { displayTitle } from '../lib/item.js'
import { playRoute } from '../lib/play.js'
import { say } from '../state/session.js'

const props = defineProps({ item: Object, eyebrow: String })
const router = useRouter()
const logoFailed = ref(false)
const starting = ref(false)

async function play() {
  starting.value = true
  try {
    const to = await playRoute(props.item)
    to ? router.push(to) : say('Nothing to play yet')
  } catch (e) {
    say(e.message)
  }
  starting.value = false
}
</script>

<template>
  <section class="billboard">
    <img class="art" :src="jf.backdrop(item, 1920)" :srcset="`${jf.backdrop(item, 1280)} 1280w, ${jf.backdrop(item, 1920)} 1920w, ${jf.backdrop(item, 2560)} 2560w`"
         sizes="100vw" alt="" fetchpriority="high" />
    <div class="fade" />
    <div class="body">
      <div v-if="eyebrow" class="eyebrow"><Wordmark :size="13" /> {{ eyebrow.toUpperCase() }}</div>
      <img v-if="jf.logo(item) && !logoFailed" class="logo" :src="jf.logo(item, 700)" :alt="displayTitle(item)" @error="logoFailed = true" />
      <h1 v-else class="title">{{ displayTitle(item) }}</h1>
      <MetaLine :item="item" />
      <p v-if="item.Overview" class="story">{{ item.Overview }}</p>
      <div class="buttons">
        <button class="btn" :disabled="starting" @click="play"><Icon name="play" :size="22" /> Play</button>
        <router-link class="btn ghost" :to="`/item/${item.Id}`"><Icon name="info" :size="22" /> More info</router-link>
      </div>
    </div>
  </section>
</template>

<style scoped>
.billboard { position: relative; height: clamp(440px, 56vw, 88vh); margin-bottom: -6vw; }
.art { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; object-position: top center; animation: fade .6s; }
.fade { position: absolute; inset: 0; background: linear-gradient(transparent 50%, rgba(14, 14, 14, .3) 70%, var(--bg)), linear-gradient(90deg, rgba(0, 0, 0, .9), transparent 55%); }
.body { position: absolute; left: var(--pad); bottom: 22%; width: clamp(380px, 40vw, 620px); display: grid; gap: 14px; animation: fade .6s; }
.eyebrow { display: flex; align-items: center; gap: 8px; letter-spacing: 3px; font-weight: 700; font-size: 12px; color: var(--dim); }
.logo { max-height: 150px; max-width: 460px; object-fit: contain; object-position: left bottom; filter: drop-shadow(0 2px 12px rgba(0, 0, 0, .5)); }
.title { font-size: clamp(36px, 4.4vw, 64px); font-weight: 900; text-shadow: 0 2px 16px rgba(0, 0, 0, .6); }
.story { font-size: 16px; line-height: 1.4; text-shadow: 0 1px 8px #000; display: -webkit-box; -webkit-line-clamp: 3; line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; }
.buttons { display: flex; gap: 10px; margin-top: 6px; }
</style>
