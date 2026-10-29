<script setup>
// A collection's films in order (release or story), numbered, with what's been watched.
import { computed, ref, watch } from 'vue'
import Pic from './Pic.vue'
import Icon from './Icon.vue'
import * as jf from '../api/jellyfin.js'
import { duration, played, progress, runtime, storyPlace } from '../lib/item.js'
import { prefs } from '../state/session.js'

const props = defineProps({ collection: Object, current: String })
const films = ref(null)
const story = computed(() => prefs.storyOrder.includes(props.collection.Id))
const hasStory = computed(() => films.value?.some((m) => storyPlace(m, props.collection.Name) !== null))
const next = computed(() => films.value?.find((m) => !played(m)))

watch(story, async () => (films.value = await jf.collectionItems(props.collection.Id, { story: story.value, name: props.collection.Name })), { immediate: true })

function order(on) {
  prefs.storyOrder = on ? [...new Set([...prefs.storyOrder, props.collection.Id])] : prefs.storyOrder.filter((x) => x !== props.collection.Id)
}
</script>

<template>
  <div>
    <div v-if="hasStory" class="chips order">
      <button class="chip" :class="{ on: !story }" @click="order(false)">Release order</button>
      <button class="chip" :class="{ on: story }" @click="order(true)">Story order</button>
      <span class="mute small">{{ story ? 'In the order the story happens' : 'In the order they came out' }}</span>
    </div>
    <router-link v-if="current" :to="`/item/${collection.Id}`" class="whole dim">{{ collection.Name }} →</router-link>
    <router-link v-for="(m, n) in films || []" :key="m.Id" :to="`/item/${m.Id}`" class="film" :class="{ here: m.Id === current }">
      <span class="n">{{ n + 1 }}</span>
      <Pic :src="jf.poster(m, 120)" :hash="jf.blurHash(m)" :fallback="m.Name" class="p" />
      <div class="t">
        <b>{{ m.Name }}</b>
        <span class="dim small">{{ [m.ProductionYear, duration(runtime(m))].filter(Boolean).join('  ·  ') }}</span>
        <div v-if="progress(m) && !played(m)" class="prog"><i :style="{ width: progress(m) * 100 + '%' }" /></div>
      </div>
      <Icon v-if="played(m)" name="check" class="done" :size="22" />
      <span v-else-if="m.Id === next?.Id" class="up">UP NEXT</span>
    </router-link>
  </div>
</template>

<style scoped>
.order { align-items: center; margin-bottom: 14px; }
.whole { display: inline-block; margin-bottom: 12px; font-weight: 700; }
.film { display: grid; grid-template-columns: 44px 52px 1fr auto; gap: 14px; align-items: center; padding: 8px; margin-bottom: 8px; border-radius: 8px;
  background: var(--surface); border: 1px solid transparent; transition: background .15s; }
.film:hover { background: var(--hover); }
.film.here { background: rgba(255, 122, 26, .12); border-color: var(--orange); }
.n { font-size: 26px; font-weight: 300; color: var(--dim); text-align: center; }
.p { width: 52px; height: 78px; }
.t { display: grid; gap: 3px; min-width: 0; }
.t b { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.prog { width: 160px; height: 4px; background: rgba(255, 255, 255, .2); margin-top: 4px; }
.prog i { display: block; height: 100%; background: var(--orange); }
.done { color: var(--orange); margin: 0 10px; }
.up { color: var(--orange); font-weight: 800; font-size: 12px; letter-spacing: 1.5px; margin: 0 10px; }
</style>
