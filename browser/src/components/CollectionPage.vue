<script setup>
// A collection's page (port of lib/ui/pages/collection.dart and universe.dart). One with a custom
// design (provider id "HevyfinPage": an accent, an eyebrow and tagline, sections in order)
// is laid out that way: a hero with the titles' art drifting and counters, then intro, quote,
// progress ring, the path (release or story order), chapters, heroes, facts, and what's
// missing or coming. Any other collection gets the standard page.
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import Icon from './Icon.vue'
import Pic from './Pic.vue'
import PosterCard from './PosterCard.vue'
import CollectionList from './CollectionList.vue'
import Elsewhere from './Elsewhere.vue'
import * as jf from '../api/jellyfin.js'
import { played, storyPlace, tagline } from '../lib/item.js'
import { accentOf, count, hours, loadCollection, pageDesign, stats, stopResume, trivia } from '../lib/collection.js'
import { playTarget } from '../lib/play.js'
import { myList, prefs, say, toggleMyList } from '../state/session.js'

const props = defineProps({ box: Object, universe: Boolean })
const router = useRouter()
const page = pageDesign(props.box)
const accent = accentOf(page)
const story = computed(() => prefs.storyOrder.includes(props.box.Id))
const d = ref(null)
const s = computed(() => d.value && stats(d.value))
document.title = `${props.box.Name} · Hevyfin`

watch(story, async () => (d.value = await loadCollection(props.box, story.value)), { immediate: true })

function setOrder(on) {
  prefs.storyOrder = on ? [...new Set([...prefs.storyOrder, props.box.Id])] : prefs.storyOrder.filter((x) => x !== props.box.Id)
}

// ---- the hero's art: each title's backdrop in turn, cross-fading every 7 seconds ----
const art = computed(() => (d.value?.films || []).filter((f) => f.BackdropImageTags?.length).map((f) => jf.backdrop(f, Math.min(1920, Math.ceil(innerWidth * devicePixelRatio / 320) * 320))))
const shown = ref(0)
const timer = setInterval(() => {
  if (art.value.length < 2) return
  shown.value = (shown.value + 1) % art.value.length
  // The next one loads now, so it's ready to fade in.
  new Image().src = art.value[(shown.value + 1) % art.value.length]
}, 7000)
onBeforeUnmount(() => clearInterval(timer))

const started = computed(() => s.value && (s.value.watchedStops.length || d.value.stops.some((x) => stopResume(x) > 0)))
const done = computed(() => d.value?.stops.length && s.value.watchedStops.length === d.value.stops.length)
const next = computed(() => d.value?.stops.find((x) => !jf.stopPlayed(x)) || null)
const hasStory = computed(() => s.value && (s.value.spread || d.value.films.some((m) => storyPlace(m, props.box.Name) !== null)))
const sections = computed(() => (page?.sections || []).filter((x) => x && typeof x === 'object'))
const ratio = computed(() => (d.value?.stops.length ? s.value.watchedStops.length / d.value.stops.length : 0))
const chapters = computed(() => {
  const g = new Map()
  for (const x of d.value?.stops || []) (g.get(x.group || 'More') || g.set(x.group || 'More', []).get(x.group || 'More')).push(x)
  return g.size < 2 && g.has('More') ? [] : [...g.entries()]
})
const span = computed(() => {
  const y = s.value?.years || []
  return !y.length ? '' : y[0] === y.at(-1) ? `${y[0]}` : `${y[0]}–${y.at(-1)}`
})
const fallbackOverview = computed(() => {
  const n = d.value.films.length, w = count(n)
  return `${w[0].toUpperCase()}${w.slice(1)} ${n === 1 ? 'film' : 'films'}${span.value ? ` from ${span.value}` : ''}, about ${hours(s.value.total)} of watching in all.`
})

async function play() {
  try {
    const t = await playTarget(props.box)
    // Started from here, it plays on along this collection's path.
    t ? router.push(`/play/${t.Id}?in=${props.box.Id}`) : say('Nothing to play yet')
  } catch (e) {
    say(e.message)
  }
}

/** Counters tick up when they first show. */
const tick = ref(0)
const ticker = setInterval(() => (tick.value >= 1 ? clearInterval(ticker) : (tick.value = Math.min(1, tick.value + 0.04))), 30)
onBeforeUnmount(() => clearInterval(ticker))
const up = (n) => Math.round(n * (1 - Math.pow(1 - tick.value, 3)))
const paras = (t) => String(t || '').split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean)
</script>

<template>
  <div v-if="!d" class="center"><span class="spinner" /></div>

  <!-- custom design (HevyfinPage) -->
  <main v-else-if="page" class="uni" :style="{ '--accent': accent }">
    <section class="uhero">
      <div class="drift">
        <!-- Only the picture showing is on the page (the one fading out while it goes). -->
        <TransitionGroup name="xfade"><img v-if="art.length" :key="art[shown]" :src="art[shown]" alt="" /></TransitionGroup>
        <img v-if="!art.length && jf.backdrop(box)" :src="jf.backdrop(box)" alt="" />
      </div>
      <div class="glow" />
      <div class="text">
        <div v-if="page.eyebrow" class="eyebrow">{{ page.eyebrow }}</div>
        <h1>{{ box.Name }}</h1>
        <i class="rule" />
        <p v-if="page.tagline || tagline(box)" class="tag">{{ page.tagline || tagline(box) }}</p>
        <div class="counters">
          <span><b>{{ up(d.stops.length) }}</b>{{ s.spread ? 'stops' : 'titles' }}</span>
          <span><b>{{ up(Math.floor(s.stopsTotal / 3600)) }}</b>hours</span>
          <span v-if="s.groups > 1"><b>{{ up(s.groups) }}</b>chapters</span>
          <span v-else-if="s.years.length > 1"><b>{{ up(s.years.at(-1) - s.years[0] + 1) }}</b>years</span>
          <span><b>{{ up(s.watchedStops.length) }}</b>watched</span>
        </div>
        <div class="acts">
          <button class="btn accent" @click="play"><Icon name="play" :size="24" /> {{ done ? 'Watch again' : started ? 'Continue' : 'Start from the beginning' }}</button>
          <button class="round" :class="{ on: myList.has(box.Id) }" title="My List" @click="toggleMyList(box.Id)"><Icon :name="myList.has(box.Id) ? 'check' : 'plus'" /></button>
        </div>
      </div>
    </section>

    <div class="sections">
      <template v-for="(x, n) in sections" :key="n">
        <section v-if="x.type === 'intro' || x.type === 'text'" class="prose" :class="{ intro: x.type === 'intro' }">
          <div v-if="x.title" class="uhead"><i /><h2>{{ x.title }}</h2></div>
          <p v-for="(p, i) in paras(x.text)" :key="i">{{ p }}</p>
        </section>

        <section v-else-if="x.type === 'quote'" class="quote">
          <span class="mark">“</span>
          <p>{{ x.text }}</p>
          <b v-if="x.by">— {{ x.by }}</b>
        </section>

        <section v-else-if="x.type === 'progress'" class="progress">
          <svg viewBox="0 0 130 130" class="ring">
            <circle cx="65" cy="65" r="59" class="bg" />
            <circle cx="65" cy="65" r="59" class="fg" :style="{ strokeDasharray: `${2 * Math.PI * 59 * ratio * tick} 999` }" />
            <text x="65" y="66" class="pct">{{ Math.round(ratio * 100 * tick) }}%</text>
            <text x="65" y="86" class="of">{{ s.watchedStops.length }} of {{ d.stops.length }}</text>
          </svg>
          <router-link v-if="next" :to="jf.stopRoute(next)" class="upnext" :style="{ backgroundImage: `url(${jf.backdrop(next.item, 900)})` }">
            <small>UP NEXT</small>
            <b>{{ next.title }}</b>
            <span class="dim small">{{ next.code ? `${next.code} · ` : '' }}{{ hours(s.stopsLeft) }} to go after this one starts</span>
          </router-link>
          <p v-else class="alldone">You have seen all of it. Time for a rewatch?</p>
        </section>

        <section v-else-if="x.type === 'timeline'">
          <div class="uhead"><i /><h2>{{ x.title || 'The path' }}</h2></div>
          <div v-if="hasStory" class="chips order">
            <button class="chip" :class="{ on: !story }" @click="setOrder(false)">Release order</button>
            <button class="chip" :class="{ on: story }" @click="setOrder(true)">Story order</button>
          </div>
          <div class="strip flush path">
            <router-link v-for="(f, i) in d.stops" :key="i" :to="jf.stopRoute(f)" class="stop" :class="{ seen: jf.stopPlayed(f), next: f === next }">
              <Pic :src="jf.stopPoster(f, 260)" :fallback="f.title" class="p" />
              <span class="line" :class="{ first: i === 0, last: i === d.stops.length - 1 }"><i class="dot" /></span>
              <b>{{ i + 1 }}</b>
              <span class="code" :class="{ part: jf.isPart(f) }">{{ f.code || f.item.ProductionYear || '' }}</span>
              <span v-if="jf.isPart(f) && f.title !== f.item.Name" class="sub">{{ f.title }}</span>
            </router-link>
          </div>
        </section>

        <section v-else-if="x.type === 'groups' && chapters.length">
          <div class="uhead"><i /><h2>{{ x.title || 'Chapters' }}</h2></div>
          <template v-for="[name, list] in chapters" :key="name">
            <div class="chapter">
              <b>{{ name.toUpperCase() }}</b>
              <span class="cbar"><i :style="{ width: (list.filter(jf.stopPlayed).length / list.length) * 100 + '%' }" /></span>
              <span class="dim small">{{ list.filter(jf.stopPlayed).length }} of {{ list.length }}</span>
            </div>
            <div class="strip flush">
              <template v-for="(f, i) in list" :key="i">
                <router-link v-if="jf.isPart(f)" :to="jf.stopRoute(f)" class="part" :title="f.title">
                  <Pic :src="jf.stopPoster(f, 260)" :fallback="f.title" class="p">
                    <div v-if="!f.art" class="label"><b v-if="f.title !== f.item.Name">{{ f.title }}</b><span>{{ f.code }}</span></div>
                    <span v-if="jf.stopPlayed(f)" class="badge tick"><Icon name="check" :size="13" /></span>
                  </Pic>
                </router-link>
                <PosterCard v-else :item="f.item" :to="jf.stopRoute(f)" :width="128" />
              </template>
            </div>
          </template>
        </section>

        <section v-else-if="x.type === 'heroes' && s.faces.length">
          <div class="uhead"><i /><h2>{{ x.title || 'Heroes' }}</h2></div>
          <div class="strip flush">
            <router-link v-for="f in s.faces" :key="f.person.Id" :to="`/person/${f.person.Id}?name=${encodeURIComponent(f.person.Name)}`" class="hero">
              <Pic :src="jf.personImage(f.person, 260)" :fallback="f.person.Name.split(' ').map((w) => w[0]).join('')" class="face" />
              <b>{{ f.person.Name }}</b>
              <span v-if="f.role" class="dim small">as {{ f.role }}</span>
              <span class="n">{{ f.n }} films</span>
            </router-link>
          </div>
        </section>

        <section v-else-if="x.type === 'facts'">
          <div class="uhead"><i /><h2>{{ x.title || 'Did you know' }}</h2></div>
          <div v-if="x.items?.length" class="facts">
            <div v-for="(f, i) in x.items" :key="i" class="fact"><b>{{ String(i + 1).padStart(2, '0') }}</b><span>{{ f }}</span></div>
          </div>
          <ul v-else class="trivia"><li v-for="([icon, text], i) in trivia(d, s)" :key="i"><span>{{ icon }}</span>{{ text }}</li></ul>
        </section>

        <section v-else-if="x.type === 'missing' || x.type === 'upcoming'">
          <Elsewhere :box="box" :accent="accent" :upcoming="x.type === 'upcoming'" :title="x.title" :items="x.items" />
        </section>
      </template>
    </div>
  </main>

  <!-- The standard page -->
  <main v-else class="coll">
    <section class="chero">
      <img v-if="jf.backdrop(box) || jf.backdrop(d.films[Math.floor(d.films.length / 2)] || {})" :src="jf.backdrop(box) || jf.backdrop(d.films[Math.floor(d.films.length / 2)])" alt="" />
      <div class="fade" />
      <div class="text">
        <div class="eyebrow">{{ [universe ? 'UNIVERSE' : 'COLLECTION', `${d.films.length} ${d.films.length === 1 ? 'TITLE' : 'TITLES'}`, span].filter(Boolean).join('  ·  ') }}</div>
        <h1>{{ box.Name }}</h1>
        <p v-if="tagline(box)" class="tag">{{ tagline(box) }}</p>
      </div>
    </section>
    <div class="cbody">
      <div class="acts">
        <button class="btn" @click="play"><Icon name="play" :size="24" /> {{ done ? 'Watch again' : started ? 'Continue' : 'Start from the beginning' }}</button>
        <button class="round" :class="{ on: myList.has(box.Id) }" title="My List" @click="toggleMyList(box.Id)"><Icon :name="myList.has(box.Id) ? 'check' : 'plus'" /></button>
      </div>
      <p class="overview">{{ (box.Overview || '').trim() || fallbackOverview }}</p>
      <div v-if="s.genres.length" class="chips"><span v-for="g in s.genres" :key="g" class="chip">{{ g }}</span></div>
      <div class="pbox">
        <div class="pline"><b>{{ s.watched.length }}</b><span class="dim"> of {{ d.films.length }} watched</span><span class="right" :class="{ done }">{{ done ? 'All done' : `${hours(s.left)} to go` }}</span></div>
        <div class="cbar big"><i :style="{ width: (d.films.length ? (s.watched.length / d.films.length) * 100 : 0) + '%' }" /></div>
        <p v-if="!done && d.films.find((f) => !played(f))"><small class="up">UP NEXT</small> <b>{{ d.films.find((f) => !played(f)).Name }}</b></p>
      </div>
      <div class="tiles">
        <div><b>{{ d.films.length }}</b><span>{{ d.films.length === 1 ? 'title' : 'titles' }}</span></div>
        <div><b>{{ hours(s.total) }}</b><span>to watch them all</span></div>
        <div v-if="s.years.length > 1"><b>{{ s.years.at(-1) - s.years[0] + 1 }}</b><span>years of releases</span></div>
        <div v-if="s.score !== null"><b>{{ s.score }}%</b><span>average score</span></div>
      </div>
      <h2>In order</h2>
      <CollectionList :collection="box" />
      <template v-if="s.faces.length">
        <h2>Familiar faces</h2>
        <p class="dim">Who keeps coming back</p>
        <div class="strip flush faces">
          <router-link v-for="f in s.faces" :key="f.person.Id" :to="`/person/${f.person.Id}?name=${encodeURIComponent(f.person.Name)}`" class="hero">
            <Pic :src="jf.personImage(f.person, 240)" :fallback="f.person.Name.split(' ').map((w) => w[0]).join('')" class="face" />
            <b>{{ f.person.Name }}</b>
            <span class="n">in {{ f.n }} films</span>
          </router-link>
        </div>
      </template>
      <template v-if="d.films.length > 1">
        <h2>Did you know</h2>
        <ul class="trivia"><li v-for="([icon, text], i) in trivia(d, s)" :key="i"><span>{{ icon }}</span>{{ text }}</li></ul>
      </template>
    </div>
  </main>
</template>

<style scoped>
/* custom design (HevyfinPage) */
.uni { --accent: var(--orange); padding-bottom: 90px; }
.uhero { position: relative; height: clamp(460px, 86vh, 900px); overflow: hidden; }
.drift { position: absolute; inset: 0; animation: drift 48s ease-in-out infinite alternate; }
.drift img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; object-position: top center; }
@keyframes drift { from { transform: scale(1.06) translateX(-1.5%); } to { transform: scale(1.12) translateX(1.5%); } }
.xfade-enter-active, .xfade-leave-active { transition: opacity 1.4s; }
.xfade-enter-from, .xfade-leave-to { opacity: 0; }
.glow { position: absolute; inset: 0;
  background: linear-gradient(rgba(0, 0, 0, .33), rgba(14, 14, 14, .2) 50%, var(--bg)),
    radial-gradient(ellipse at 15% 80%, color-mix(in srgb, var(--accent) 38%, transparent), color-mix(in srgb, var(--accent) 8%, transparent) 45%, transparent 75%),
    linear-gradient(90deg, rgba(0, 0, 0, .9), transparent 75%); }
.text { position: absolute; left: var(--pad); right: var(--pad); bottom: 18px; display: grid; justify-items: start; gap: 10px; }
.eyebrow { color: var(--accent); font-weight: 800; letter-spacing: 3.5px; font-size: 14px; text-transform: uppercase; }
.uhero h1 { font-size: clamp(44px, 6vw, 76px); font-weight: 900; letter-spacing: -2.4px; line-height: .98; max-width: 900px; }
.rule { width: 120px; height: 4px; border-radius: 2px; background: var(--accent); }
.tag { font-size: 22px; color: var(--dim); font-weight: 300; max-width: 800px; }
.counters { display: flex; gap: 40px; margin-top: 12px; }
.counters span { display: grid; color: var(--accent); font-size: 11px; font-weight: 800; letter-spacing: 2px; text-transform: uppercase; }
.counters b { color: #fff; font-size: 38px; font-weight: 300; letter-spacing: 0; font-variant-numeric: tabular-nums; line-height: 1.1; }
.acts { display: flex; gap: 12px; align-items: center; margin-top: 12px; }
.btn.accent { background: var(--accent); color: #000; }
.sections { padding: 8px 0 0 var(--pad); }
.sections > section { margin-top: 40px; padding-right: var(--pad); }
.sections > section:has(.flush) { padding-right: 0; }
.prose { max-width: 860px; }
.prose p { font-size: 15.5px; line-height: 1.55; color: #dadada; margin-bottom: 12px; }
.prose.intro p:first-of-type { font-size: 19px; color: #fff; }
.quote { text-align: center; padding: 26px 40px; display: grid; justify-items: center; }
.quote .mark { color: var(--accent); font-size: 90px; line-height: .6; font-weight: 900; }
.quote p { font-size: 32px; font-weight: 300; font-style: italic; line-height: 1.3; max-width: 1000px; }
.quote b { color: var(--accent); letter-spacing: 1px; margin-top: 14px; }
.progress { display: flex; gap: 28px; align-items: center; }
.ring { width: 130px; flex: none; }
.ring circle { fill: none; stroke-width: 8; }
.ring .bg { stroke: rgba(255, 255, 255, .1); }
.ring .fg { stroke: var(--accent); stroke-linecap: round; transform: rotate(-90deg); transform-origin: center; }
.ring .pct { fill: #fff; font-size: 28px; font-weight: 300; text-anchor: middle; }
.ring .of { fill: var(--dim); font-size: 12px; text-anchor: middle; }
.upnext { flex: 1; height: 150px; border-radius: 10px; background: center / cover; position: relative; overflow: hidden; display: flex; flex-direction: column; justify-content: flex-end;
  padding: 18px; gap: 2px; transition: transform .2s; }
.upnext::before { content: ''; position: absolute; inset: 0; background: linear-gradient(90deg, rgba(0, 0, 0, .93), rgba(0, 0, 0, .13)); }
.upnext > * { position: relative; }
.upnext:hover { transform: scale(1.01); }
.upnext small { color: var(--accent); font-weight: 800; letter-spacing: 2px; font-size: 12px; }
.upnext b { font-size: 22px; }
.alldone { font-size: 18px; font-weight: 700; }
.order { margin-bottom: 14px; }
.path { gap: 0; }
.stop { width: 132px; display: grid; justify-items: center; text-align: center; padding-top: 4px; }
.stop .p { width: 114px; aspect-ratio: 2 / 3; opacity: .62; border: 3px solid transparent; transition: transform .2s, opacity .2s; }
.stop.seen .p, .stop.next .p, .stop:hover .p { opacity: 1; }
.stop.next .p { border-color: var(--accent); }
.stop:hover .p { transform: scale(1.04); }
.line { position: relative; width: 100%; height: 18px; margin: 12px 0 8px; display: grid; place-items: center; }
.line::before { content: ''; position: absolute; left: 0; right: 0; top: 8px; height: 2px; background: rgba(255, 255, 255, .24); }
.line.first::before { left: 50%; } .line.last::before { right: 50%; }
.seen .line::before { background: var(--accent); }
.dot { position: relative; width: 12px; height: 12px; border-radius: 50%; background: var(--bg); border: 2.5px solid rgba(255, 255, 255, .38); }
.seen .dot { background: var(--accent); border-color: var(--accent); }
.next .dot { width: 16px; height: 16px; border-color: var(--accent); }
.stop > b { color: var(--dim); }
.stop.next > b { color: var(--accent); }
.code { color: var(--mute); font-size: 12px; max-width: 120px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.code.part { color: var(--accent); font-weight: 700; }
.sub { color: var(--mute); font-size: 11px; max-width: 120px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.chapter { display: flex; align-items: center; gap: 12px; margin: 6px var(--pad) 10px 0; }
.chapter b { color: var(--accent); letter-spacing: 2.5px; font-size: 13px; white-space: nowrap; }
.cbar { flex: 1; height: 3px; background: rgba(255, 255, 255, .1); border-radius: 2px; overflow: hidden; }
.cbar i { display: block; height: 100%; background: var(--accent, var(--orange)); }
.cbar.big { height: 6px; margin: 12px 0; }
.part { width: 128px; }
.part .p { aspect-ratio: 2 / 3; transition: transform .2s; }
.part:hover .p { transform: scale(1.05); }
.label { position: absolute; inset: auto 0 0; padding: 30px 8px 8px; background: linear-gradient(transparent, rgba(0, 0, 0, .9)); display: grid; }
.label b { font-size: 12px; line-height: 1.15; }
.label span { color: var(--accent); font-size: 11px; font-weight: 800; }
.hero { width: 124px; display: grid; justify-items: center; text-align: center; gap: 2px; padding-top: 6px; }
.face { width: 112px; height: 112px; border-radius: 50%; border: 2px solid var(--accent, var(--orange)); padding: 3px; background-clip: content-box; transition: transform .2s; }
.face :deep(img) { border-radius: 50%; }
.hero:hover .face { transform: scale(1.04); }
.hero b { font-size: 13.5px; margin-top: 8px; max-width: 120px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.hero .n { color: var(--accent, var(--orange)); font-size: 11.5px; font-weight: 800; }
.facts { display: grid; grid-template-columns: repeat(auto-fill, minmax(380px, 1fr)); gap: 12px; }
.fact { display: flex; gap: 12px; background: var(--surface); border-left: 3px solid var(--accent); border-radius: 10px; padding: 16px; font-size: 14.5px; line-height: 1.45; }
.fact b { color: var(--accent); font-size: 18px; font-weight: 900; }
.trivia { list-style: none; padding: 0; margin: 0; display: grid; gap: 12px; max-width: 900px; }
.trivia li { display: flex; gap: 12px; font-size: 15px; line-height: 1.4; }

/* the standard page */
.coll { padding-bottom: 80px; }
.chero { position: relative; height: clamp(360px, 62vh, 640px); }
.chero img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; object-position: top center; }
.chero .fade { position: absolute; inset: 0; background: linear-gradient(transparent, rgba(14, 14, 14, .4) 55%, var(--bg)), linear-gradient(90deg, rgba(0, 0, 0, .9), transparent 70%); }
.chero .text { gap: 8px; bottom: 10px; }
.chero .eyebrow { color: var(--orange); letter-spacing: 3px; font-size: 13px; }
.chero h1 { font-size: 56px; font-weight: 900; letter-spacing: -1.2px; }
.chero .tag { font-style: italic; font-size: 19px; }
.cbody { padding: 16px var(--pad) 0; display: grid; gap: 18px; }
.cbody h2 { font-size: 21px; margin-top: 14px; }
.overview { max-width: 820px; font-size: 15.5px; line-height: 1.5; }
.cbody .chip { cursor: default; }
.pbox { background: var(--surface); border: 1px solid var(--line); border-radius: 10px; padding: 18px; max-width: 900px; }
.pline { display: flex; align-items: baseline; }
.pline b { font-size: 34px; font-weight: 300; }
.pline .right { margin-left: auto; color: var(--dim); font-weight: 700; }
.pline .right.done { color: var(--orange); }
.up { color: var(--orange); font-weight: 800; letter-spacing: 1px; }
.tiles { display: flex; flex-wrap: wrap; gap: 12px; }
.tiles div { width: 190px; background: var(--surface); border-radius: 10px; padding: 14px 16px; display: grid; }
.tiles b { font-size: 26px; font-weight: 800; }
.tiles span { color: var(--dim); font-size: 13px; }
.faces { padding-left: 0; }
</style>
