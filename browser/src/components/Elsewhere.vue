<script setup>
// A universe's titles that aren't in the library yet: released ones to request (those already
// asked for or downloading in their own "On its way" row), announced ones with their date.
// From the section's own list, else from the tags the universe job puts on the collection.
import { computed, ref } from 'vue'
import SeerrCard from './SeerrCard.vue'
import Pic from './Pic.vue'
import * as seerr from '../api/seerr.js'

const props = defineProps({ box: Object, accent: String, upcoming: Boolean, title: String, items: Array })
const list = ref(null)
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

const wanted = computed(() => {
  if (props.items) return props.items.filter((m) => Number(m.tmdb)).map((m) => ({ kind: m.kind || 'movie', id: Number(m.tmdb), date: m.date ? new Date(m.date) : null }))
  const out = []
  for (const t of props.box.Tags || []) {
    const p = t.split(':')
    if (!props.upcoming && p.length === 3 && p[0] === 'missing' && Number(p[2])) out.push({ kind: p[1], id: Number(p[2]), date: null })
    if (props.upcoming && p.length === 4 && p[0] === 'upcoming' && Number(p[2])) out.push({ kind: p[1], id: Number(p[2]), date: p[3] ? new Date(p[3]) : null })
  }
  // Dated ones first, soonest first.
  return out.sort((a, b) => (a.date?.getTime() ?? 9e15) - (b.date?.getTime() ?? 9e15))
})

if (seerr.seerrReady.value && wanted.value.length) {
  Promise.all(wanted.value.slice(0, 30).map((w) => seerr.details(w.kind, w.id).then((m) => ({ m, date: w.date })).catch(() => null))).then(
    (l) => (list.value = l.filter(Boolean)),
  )
}

/** Requested, downloading, or being fetched by Sonarr/Radarr (tagged coming:<kind>:<tmdb>). */
const onItsWay = (m) =>
  [2, 3].includes(seerr.status(m)) || seerr.downloadProgress(m.mediaInfo) !== null || (props.box.Tags || []).includes(`coming:${seerr.mediaType(m)}:${m.id}`)
const coming = computed(() => (props.upcoming ? [] : (list.value || []).filter((e) => onItsWay(e.m))))
const rest = computed(() => (list.value || []).filter((e) => !coming.value.includes(e)))
const heading = computed(() => props.title || (props.upcoming ? 'Coming soon' : 'Not in your library yet'))

function when(date) {
  if (!date) return 'Date to be announced'
  const days = Math.floor((date - Date.now()) / 864e5)
  return days <= 0 ? 'Out now' : days < 60 ? `In ${days} days` : `${MONTHS[date.getMonth()]} ${date.getFullYear()}`
}
const to = (m) => (seerr.status(m) === 5 && seerr.jellyfinId(m) ? `/item/${seerr.jellyfinId(m)}` : `/request/${seerr.mediaType(m)}/${m.id}`)
</script>

<template>
  <template v-if="seerr.seerrReady.value && wanted.length">
    <div v-if="!list" class="uhead"><i :style="{ background: accent }" /><h2>{{ heading }}</h2><span class="dim">{{ wanted.length }}</span></div>
    <template v-if="coming.length">
      <div class="uhead"><i :style="{ background: accent }" /><h2>On its way</h2><span class="dim">{{ coming.length }}</span></div>
      <div class="strip flush"><SeerrCard v-for="e in coming" :key="e.m.id" :media="e.m" :width="140" /></div>
    </template>
    <template v-if="rest.length">
      <div class="uhead"><i :style="{ background: accent }" /><h2>{{ heading }}</h2><span class="dim">{{ rest.length }}</span></div>
      <div class="strip flush">
        <template v-if="upcoming">
          <router-link v-for="e in rest" :key="e.m.id" :to="to(e.m)" class="soon">
            <Pic :src="seerr.image(e.m.posterPath)" :fallback="seerr.title(e.m)" class="p" />
            <b>{{ seerr.title(e.m) }}</b>
            <span :style="{ color: accent }">{{ when(e.date) }}</span>
          </router-link>
        </template>
        <SeerrCard v-else v-for="e in rest" :key="e.m.id" :media="e.m" :width="140" />
      </div>
    </template>
  </template>
</template>

<style scoped>
.soon { width: 140px; display: grid; gap: 4px; }
.soon .p { aspect-ratio: 2 / 3; transition: transform .2s; }
.soon:hover .p { transform: scale(1.04); }
.soon b { font-size: 13px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.soon span { font-size: 12px; font-weight: 700; }
</style>
