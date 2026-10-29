<script setup>
// "What tonight?": ask the recommendation service (if any) in your own words, or tap a few choices and get three ideas from
// the library (port of lib/ui/pages/tonight.dart and lib/state/tonight.dart). ?ask= from
// Search puts the question to it straight away.
import { nextTick, onMounted, reactive, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import Icon from '../components/Icon.vue'
import Pic from '../components/Pic.vue'
import * as jf from '../api/jellyfin.js'
import { ask as askNiql, enabled as niqlOn } from '../api/niql.js'
import { isMovie, isSeries, played, runtime } from '../lib/item.js'
import { shuffle } from '../lib/seasons.js'
import { playRoute } from '../lib/play.js'
import { say } from '../state/session.js'

const route = useRoute()
const router = useRouter()
const KINDS = { any: 'Anything', film: 'A film', series: 'A series' }
const LENGTHS = { any: 'Any length', short: 'Under 1½ hours', medium: 'Under 2 hours', long: 'A long one' }
const MOODS = {
  any: 'Anything', funny: 'Funny', exciting: 'Exciting', scary: 'Scary', feelGood: 'Feel-good', mindBending: 'Mind-bending', magical: 'Magical', real: 'True stories',
}
const choice = reactive({ kind: 'any', length: 'any', mood: 'any', kids: false, unseen: true })
const question = ref(route.query.ask || '')
const picks = ref(null)
const why = ref({})
const niqlSays = ref(null)
const asking = ref(false)
const results = ref(null)
document.title = 'What tonight? · Hevyfin'

const has = (i, names) => (i.Genres || []).some((g) => names.includes(g))
const tagText = (i) => (i.Tags || []).join('|').toLowerCase()
const FITS = {
  any: () => true,
  funny: (i) => has(i, ['Comedy']),
  exciting: (i) => has(i, ['Action', 'Adventure', 'Thriller', 'Action & Adventure', 'War', 'Crime']),
  scary: (i) => has(i, ['Horror']) || tagText(i).includes('horror'),
  feelGood: (i) => has(i, ['Family', 'Romance', 'Music', 'Animation']) && !has(i, ['Horror']),
  mindBending: (i) => has(i, ['Science Fiction', 'Mystery', 'Sci-Fi & Fantasy']) || tagText(i).includes('time travel'),
  magical: (i) => has(i, ['Fantasy', 'Sci-Fi & Fantasy']) || tagText(i).includes('magic'),
  real: (i) => has(i, ['Documentary', 'History']) || tagText(i).includes('based on true story'),
}
/** Ratings fine for children (US, UK and Dutch/Belgian labels). */
const KIDS = new Set(['G', 'PG', 'TV-Y', 'TV-Y7', 'TV-G', 'TV-PG', 'U', 'AL', 'KT', '6', '9', 'NL-AL', 'NL-6', 'NL-9', 'BE-AL', 'BE-6', 'BE-9'])
function kidSafe(i) {
  const r = i.OfficialRating?.trim()
  if (r) return KIDS.has(r.toUpperCase())
  return has(i, ['Family', 'Kids']) || (has(i, ['Animation']) && !has(i, ['Horror']))
}

function fits(i) {
  if (choice.kind === 'film' && !isMovie(i)) return false
  if (choice.kind === 'series' && !isSeries(i)) return false
  if (choice.unseen && played(i)) return false
  if (choice.kids && !kidSafe(i)) return false
  // A series counts by its episodes, so "short" means short episodes.
  const m = runtime(i) ? runtime(i) / 60 : null
  const ok = { any: true, short: m !== null && m <= 90, medium: m !== null && m <= 120, long: m !== null && m > 120 }[choice.length]
  return ok && FITS[choice.mood](i)
}

/** Up to three that fit, at random, each preferring a main genre the others don't have. */
function pickTonight(all) {
  const pool = shuffle(all.filter(fits))
  const out = [], seen = new Set()
  for (const i of pool) {
    if (out.length === 3) break
    const g = (i.Genres || [])[0]
    if (g && seen.has(g)) continue
    out.push(i)
    if (g) seen.add(g)
  }
  for (const i of pool) if (out.length < 3 && !out.includes(i)) out.push(i)
  return out
}

async function showResults() {
  await nextTick()
  results.value?.scrollIntoView({ behavior: 'smooth', block: 'start' })
}

async function surprise() {
  try {
    picks.value = pickTonight(await jf.everything())
    why.value = {}
    niqlSays.value = null
    showResults()
  } catch (e) {
    say(e.message)
  }
}

async function ask() {
  const q = question.value.trim()
  if (!q || asking.value) return
  asking.value = true
  router.replace({ query: { ask: q } })
  try {
    const a = await askNiql(q)
    picks.value = await jf.itemsByIds(a.picks.map((p) => p.id))
    why.value = Object.fromEntries(a.picks.map((p) => [p.id, p.why]))
    niqlSays.value = a.answer
    showResults()
  } catch (e) {
    say(e.message)
  }
  asking.value = false
}

async function play(i) {
  try {
    const to = await playRoute(i)
    to ? router.push(to) : say('Nothing to play yet')
  } catch (e) {
    say(e.message)
  }
}

function meta(i) {
  const m = runtime(i) ? Math.round(runtime(i) / 60) : null
  const len = m ? (isSeries(i) ? `${m}m episodes` : m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m}m`) : null
  return [i.ProductionYear, len, ...(i.Genres || []).slice(0, 2)].filter(Boolean).join('  ·  ')
}

onMounted(() => niqlOn && question.value && ask())
</script>

<template>
  <main class="page tonight">
    <h1>What tonight?</h1>
    <p class="dim">{{ niqlOn ? 'Ask in your own words, or pick a few things below.' : 'Pick a few things below.' }}</p>

    <form v-if="niqlOn" class="askbox" @submit.prevent="ask">
      <Icon name="sparkle" :size="22" class="spark" />
      <input v-model="question" placeholder="Something funny we haven’t seen, under two hours" aria-label="Ask" />
      <button class="btn orange" :disabled="asking">{{ asking ? 'Asking…' : 'Ask' }}</button>
    </form>

    <h3>WHAT</h3>
    <div class="chips"><button v-for="(l, k) in KINDS" :key="k" class="chip" :class="{ on: choice.kind === k }" @click="choice.kind = k">{{ l }}</button></div>
    <h3>HOW LONG</h3>
    <div class="chips"><button v-for="(l, k) in LENGTHS" :key="k" class="chip" :class="{ on: choice.length === k }" @click="choice.length = k">{{ l }}</button></div>
    <h3>MOOD</h3>
    <div class="chips"><button v-for="(l, k) in MOODS" :key="k" class="chip" :class="{ on: choice.mood === k }" @click="choice.mood = k">{{ l }}</button></div>
    <h3>WHO’S WATCHING</h3>
    <div class="chips">
      <button class="chip" :class="{ on: !choice.kids }" @click="choice.kids = false">Grown-ups</button>
      <button class="chip" :class="{ on: choice.kids }" @click="choice.kids = true">With kids</button>
    </div>
    <label class="unseen"><input v-model="choice.unseen" type="checkbox" /> Only things not seen yet</label>
    <button class="btn surprise" @click="surprise">🎲 {{ picks === null || niqlSays !== null ? 'Surprise me' : 'Shuffle again' }}</button>

    <div ref="results" class="results">
      <p v-if="niqlSays" class="says"><Icon name="sparkle" :size="20" class="spark" /> {{ niqlSays }}</p>
      <p v-if="picks && !picks.length" class="dim">Nothing in the library fits all of that. Try fewer choices.</p>
      <div v-if="picks?.length" :key="picks.map((p) => p.Id).join()" class="picks">
        <div v-for="p in picks" :key="p.Id" class="pick">
          <router-link :to="`/item/${p.Id}`" class="still">
            <Pic :src="jf.thumb(p, 900)" :hash="jf.blurHash(p, 'Backdrop')" :fallback="p.Name" class="art" />
            <b>{{ p.Name }}</b>
          </router-link>
          <span class="dim small meta">{{ meta(p) }}</span>
          <p v-if="why[p.Id]" class="why">“{{ why[p.Id] }}”</p>
          <p v-else class="dim overview">{{ p.Overview }}</p>
          <div class="acts">
            <button class="btn" @click="play(p)"><Icon name="play" /> Play</button>
            <router-link :to="`/item/${p.Id}`" class="btn ghost">More info</router-link>
          </div>
        </div>
      </div>
    </div>
  </main>
</template>

<style scoped>
.tonight { max-width: 1160px; }
h1 { font-size: 40px; font-weight: 900; letter-spacing: -.5px; }
.askbox { display: flex; gap: 10px; align-items: center; margin: 18px 0 8px; position: relative; }
.askbox input { padding-left: 42px; }
.askbox .spark { position: absolute; left: 12px; color: var(--orange); }
h3 { font-size: 13px; letter-spacing: 2px; font-weight: 800; color: var(--mute); margin: 18px 0 8px; }
.unseen { display: flex; align-items: center; gap: 10px; margin: 16px 0; }
.surprise { padding: 14px 22px; }
.results { padding-top: 26px; scroll-margin-top: calc(var(--bar) + 10px); }
.says { display: flex; gap: 10px; font-size: 16.5px; font-weight: 600; margin-bottom: 16px; }
.says .spark { color: var(--orange); flex: none; margin-top: 2px; }
.picks { display: grid; grid-template-columns: repeat(3, 1fr); gap: 18px; animation: fade .4s; }
.pick { display: grid; gap: 8px; align-content: start; }
.still { position: relative; display: block; border-radius: var(--radius); overflow: hidden; transition: transform .2s; }
.still:hover { transform: scale(1.03); }
.art { aspect-ratio: 16 / 9; }
.still::after { content: ''; position: absolute; inset: 0; background: linear-gradient(transparent 45%, rgba(0, 0, 0, .85)); }
.still b { position: absolute; left: 14px; right: 14px; bottom: 12px; z-index: 1; font-size: 20px; font-weight: 900; line-height: 1.1; text-shadow: 0 0 10px #000; }
.meta { font-weight: 600; }
.why { font-style: italic; line-height: 1.4; }
.overview { font-size: 14px; line-height: 1.4; display: -webkit-box; -webkit-line-clamp: 3; line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; }
.acts { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 4px; }
@media (max-width: 860px) { .picks { grid-template-columns: 1fr; } }
</style>
