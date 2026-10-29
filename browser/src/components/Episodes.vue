<script setup>
// A show's seasons as pills and the chosen season's episodes; a mini series is just its own.
import { onMounted, ref } from 'vue'
import Pic from './Pic.vue'
import Icon from './Icon.vue'
import * as jf from '../api/jellyfin.js'
import { duration, played, progress } from '../lib/item.js'
import { bump } from '../state/session.js'

const props = defineProps({ series: Object })
const seasons = ref(null)
const season = ref(null)
const episodes = ref(null)
const done = ref({}) // ticked or unticked here

onMounted(async () => {
  const mini = props.series.PathStop?.mini ? props.series.PathStop : null
  if (mini) {
    seasons.value = []
    episodes.value = mini.parts
    return
  }
  const all = await jf.seasons(props.series.Id)
  if (!all.length) return (seasons.value = [])
  // The season asked for (a universe's season or cut), else the one with the next thing to watch.
  const open = all.find((s) => s.Id === props.series.OpenSeasonId)
  const next = open ? null : (await jf.nextUp({ seriesId: props.series.Id, limit: 1 }))[0]
  seasons.value = all
  pick(open || all.find((s) => s.Id === next?.SeasonId) || all.find((s) => (s.IndexNumber ?? 0) > 0) || all[0])
})

async function pick(s) {
  season.value = s
  const got = await jf.episodes(props.series.Id, s.Id)
  // (season.value is Vue's wrapper of s, so compare ids.)
  if (season.value?.Id === s.Id) episodes.value = got
}

async function tick(e) {
  const on = !(done.value[e.Id] ?? played(e))
  done.value[e.Id] = on
  await jf.setPlayed(e.Id, on)
  jf.forget()
}
</script>

<template>
  <div class="episodes">
    <div v-if="seasons?.length > 1" class="chips seasons">
      <button v-for="s in seasons" :key="s.Id" class="chip" :class="{ on: s.Id === season?.Id }" @click="pick(s)">{{ s.Name }}</button>
    </div>
    <div v-if="!episodes" class="skeleton" style="height: 300px" />
    <router-link v-for="e in episodes" :key="e.Id" :to="`/play/${e.Id}${series.PathStop?.box ? `?in=${series.PathStop.box}` : ''}`" class="ep">
      <span class="n">{{ e.IndexNumber ?? '' }}</span>
      <Pic :src="jf.thumb(e, 300)" :hash="jf.blurHash(e)" :fallback="e.Name" class="still">
        <span class="go"><Icon name="play" :size="22" /></span>
        <div v-if="progress(e) && !(done[e.Id] ?? played(e))" class="bar"><i :style="{ width: progress(e) * 100 + '%' }" /></div>
      </Pic>
      <div class="text">
        <div class="top">
          <b>{{ e.Name }}</b>
          <span class="dim">{{ duration(e.RunTimeTicks / 1e7) }}</span>
          <button class="icon-btn tick" :class="{ on: done[e.Id] ?? played(e) }" :title="(done[e.Id] ?? played(e)) ? 'Mark unwatched' : 'Mark watched'"
                  @click.prevent.stop="tick(e)"><Icon name="check" :size="18" /></button>
        </div>
        <p class="dim">{{ e.Overview }}</p>
      </div>
    </router-link>
  </div>
</template>

<style scoped>
.seasons { margin-bottom: 14px; }
.ep { display: grid; grid-template-columns: 40px 200px 1fr; gap: 16px; padding: 16px 12px; border-bottom: 1px solid var(--line); border-radius: 6px; align-items: start; }
.ep:hover { background: var(--surface); }
.n { font-size: 22px; color: var(--dim); padding-top: 34px; text-align: center; }
.still { aspect-ratio: 16 / 9; border-radius: 4px; }
.go { position: absolute; inset: 0; display: grid; place-items: center; opacity: 0; transition: opacity .2s; background: rgba(0, 0, 0, .35); }
.ep:hover .go { opacity: 1; }
.top { display: flex; align-items: center; gap: 12px; }
.top b { flex: 1; font-size: 15.5px; }
.tick { color: var(--mute); border: 1.5px solid currentColor; padding: 3px; }
.tick.on { color: #000; background: var(--orange); border-color: var(--orange); }
.text p { margin-top: 6px; font-size: 13.5px; line-height: 1.45; display: -webkit-box; -webkit-line-clamp: 3; line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; }
</style>
