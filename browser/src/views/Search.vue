<script setup>
// Search the library as you type; below it, what Seerr knows that isn't here yet (to request),
// and "Ask" (when a recommendation service is set up) for the words as a question. The query stays in the address (?q=).
import { onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import PosterCard from '../components/PosterCard.vue'
import SeerrCard from '../components/SeerrCard.vue'
import Icon from '../components/Icon.vue'
import * as jf from '../api/jellyfin.js'
import * as seerr from '../api/seerr.js'
import { enabled as niqlOn } from '../api/niql.js'

const route = useRoute()
const router = useRouter()
const q = ref(route.query.q || '')
const library = ref(null)
const elsewhere = ref(null)
const box = ref(null)
let timer, n = 0
document.title = 'Search · Hevyfin'

async function run(text) {
  const mine = ++n
  router.replace({ query: text ? { q: text } : {} })
  if (!text.trim()) return (library.value = elsewhere.value = null)
  const [lib, other] = await Promise.all([
    jf.items({ types: ['Movie', 'Series', 'BoxSet'], search: text, limit: 60 }).catch(() => []),
    seerr.seerrReady.value ? seerr.search(text).then((r) => r.filter((m) => seerr.status(m) !== 5)).catch(() => []) : Promise.resolve([]),
  ])
  if (mine !== n) return
  library.value = lib
  elsewhere.value = other
}

watch(q, (v) => {
  clearTimeout(timer)
  timer = setTimeout(() => run(v), 300)
})
onMounted(() => {
  box.value.focus()
  if (q.value) run(q.value)
})
</script>

<template>
  <main class="page">
    <label class="field">
      <Icon name="search" :size="24" />
      <input ref="box" v-model="q" placeholder="Titles, people, genres" aria-label="Search" />
      <button v-if="q" class="icon-btn" aria-label="Clear" @click="q = ''"><Icon name="close" /></button>
    </label>

    <router-link v-if="!q" to="/tonight" class="tonight">
      <Icon name="sparkle" :size="28" />
      <span><b>What should I watch tonight?</b><span class="dim">{{ niqlOn ? 'A few picks for your mood, or just ask' : 'A few picks for your mood' }}</span></span>
    </router-link>

    <template v-else>
      <router-link v-if="niqlOn" :to="`/tonight?ask=${encodeURIComponent(q)}`" class="btn ghost ask"><Icon name="sparkle" /> Ask: “{{ q }}”</router-link>
      <h2>In your library</h2>
      <div v-if="!library" class="center small-h"><span class="spinner" /></div>
      <p v-else-if="!library.length" class="dim">Nothing in your library matches “{{ q }}”.</p>
      <div v-else class="grid"><PosterCard v-for="i in library" :key="i.Id" :item="i" class="fill" /></div>
      <template v-if="seerr.seerrReady.value && elsewhere?.length">
        <h2>Not on Hevyfin yet – request it</h2>
        <div class="grid"><SeerrCard v-for="m in elsewhere" :key="m.id" :media="m" class="fill" /></div>
      </template>
    </template>
  </main>
</template>

<style scoped>
.field { display: flex; align-items: center; gap: 12px; border-bottom: 2px solid #555; padding: 6px 2px; margin-bottom: 24px; }
.field:focus-within { border-color: var(--orange); }
.field input { border: 0; background: none; font-size: 26px; font-weight: 600; padding: 6px 0; }
.tonight { display: flex; align-items: center; gap: 18px; padding: 22px; border-radius: 10px; background: linear-gradient(135deg, #2a1405, var(--surface)); border: 1px solid #3a2410; max-width: 560px; }
.tonight span { display: grid; gap: 2px; }
.tonight b { font-size: 20px; }
.ask { margin-bottom: 8px; }
h2 { font-size: 20px; margin: 24px 0 14px; }
.small-h { min-height: 160px; }
.fill { width: 100% !important; }
</style>
