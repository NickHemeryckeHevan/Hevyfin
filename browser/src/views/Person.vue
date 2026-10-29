<script setup>
// An actor (or director): photo, biography, life dates, what's on Hevyfin and the whole
// filmography (from Seerr/TMDb when it's connected, else what Jellyfin knows).
import { computed, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import PosterCard from '../components/PosterCard.vue'
import SeerrCard from '../components/SeerrCard.vue'
import Row from '../components/Row.vue'
import * as jf from '../api/jellyfin.js'
import * as seerr from '../api/seerr.js'
import { providerIds, tmdbId } from '../lib/item.js'

const props = defineProps({ id: String, tmdb: String })
const route = useRoute()
const d = ref(null)
const error = ref('')
const more = ref(false)

onMounted(async () => {
  try {
    let person = null, library = [], tmdb = props.tmdb ? Number(props.tmdb) : null
    if (props.id) {
      ;[person, library] = await Promise.all([jf.item(props.id), jf.items({ personIds: props.id, sortBy: 'PremiereDate', sortOrder: 'Descending' })])
      tmdb ||= tmdbId(person)
    }
    let sp = null, credits = []
    if (seerr.seerrReady.value && tmdb) {
      try {
        ;[sp, credits] = await Promise.all([seerr.person(tmdb), seerr.personCredits(tmdb)])
      } catch {}
    }
    const photo = sp?.profilePath ? seerr.image(sp.profilePath, 'h632') : person?.ImageTags?.Primary ? jf.img(person.Id, 'Primary', { tag: person.ImageTags.Primary, width: 600 }) : null
    d.value = {
      name: sp?.name || person?.Name || route.query.name || '',
      photo,
      bio: sp?.biography || person?.Overview || '',
      born: sp?.birthday || person?.PremiereDate || null,
      died: sp?.deathday || person?.EndDate || null,
      place: sp?.placeOfBirth || person?.ProductionLocations?.[0] || null,
      knownFor: sp?.knownForDepartment || null,
      imdb: sp?.imdbId || (person && providerIds(person).imdb) || null,
      aka: sp?.alsoKnownAs || [],
      library,
      credits,
    }
    document.title = `${d.value.name} · Hevyfin`
  } catch (e) {
    error.value = e.message
  }
})

const fmt = (s) => (s ? new Date(s).toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' }) : '')
const age = computed(() => {
  if (!d.value?.born) return null
  const end = d.value.died ? new Date(d.value.died) : new Date(), b = new Date(d.value.born)
  return end.getFullYear() - b.getFullYear() - (end < new Date(end.getFullYear(), b.getMonth(), b.getDate()) ? 1 : 0)
})
const inLibrary = computed(() => new Set((d.value?.library || []).map(tmdbId)))
const known = computed(() => [...(d.value?.credits || [])].filter((c) => c.media.posterPath).sort((a, b) => (b.media.voteCount || 0) - (a.media.voteCount || 0)).slice(0, 16))
const dated = computed(() => [...(d.value?.credits || [])].sort((a, b) => (seerr.year(b.media) || 9999) - (seerr.year(a.media) || 9999)))
</script>

<template>
  <div v-if="error" class="center"><p class="danger">{{ error }}</p></div>
  <div v-else-if="!d" class="center"><span class="spinner" /></div>
  <main v-else class="person">
    <div class="glow" :style="d.photo ? { backgroundImage: `url(${d.photo})` } : null" />
    <header>
      <img v-if="d.photo" :src="d.photo" alt="" class="photo" />
      <div class="info">
        <small v-if="d.knownFor" class="eyebrow">{{ d.knownFor === 'Acting' ? 'ACTOR' : d.knownFor.toUpperCase() }}</small>
        <h1>{{ d.name }}</h1>
        <p class="dim">
          <template v-if="d.born">Born {{ fmt(d.born) }}<template v-if="d.place"> in {{ d.place }}</template></template>
          <template v-if="d.died"> · Died {{ fmt(d.died) }}</template>
          <template v-if="age !== null"> · {{ d.died ? `aged ${age}` : `${age} years old` }}</template>
        </p>
        <div class="stats">
          <span v-if="d.credits.length"><b>{{ d.credits.length }}</b> credits</span>
          <span v-if="d.library.length"><b>{{ d.library.length }}</b> on Hevyfin</span>
          <a v-if="d.imdb" :href="`https://www.imdb.com/name/${d.imdb}`" target="_blank" rel="noopener" class="imdb">IMDb</a>
        </div>
        <p v-if="d.bio" class="bio" :class="{ more }" @click="more = !more">{{ d.bio }}</p>
        <p v-if="d.aka.length" class="mute small">Also known as {{ d.aka.slice(0, 3).join(', ') }}</p>
      </div>
    </header>

    <Row v-if="d.library.length" title="On Hevyfin" :load="async () => d.library" v-slot="{ item }"><PosterCard :item="item" /></Row>
    <Row v-if="known.length" title="Known For" :load="async () => known.map((c) => c.media)" v-slot="{ item }"><SeerrCard :media="item" /></Row>

    <section v-if="dated.length" class="films">
      <h2>Filmography</h2>
      <template v-for="(c, n) in dated" :key="c.media.mediaType + c.media.id">
        <div v-if="n === 0 || seerr.year(dated[n - 1].media) !== seerr.year(c.media)" class="year">{{ seerr.year(c.media) || 'Coming' }}</div>
        <router-link :to="`/request/${seerr.mediaType(c.media)}/${c.media.id}`" class="credit">
          <b>{{ seerr.title(c.media) }}</b>
          <span class="dim small">{{ c.role }}<template v-if="c.episodes"> · {{ c.episodes }} episode{{ c.episodes === 1 ? '' : 's' }}</template></span>
          <span v-if="inLibrary.has(c.media.id)" class="here">ON HEVYFIN</span>
        </router-link>
      </template>
    </section>
  </main>
</template>

<style scoped>
.person { position: relative; padding: calc(var(--bar) + 30px) 0 60px; }
.glow { position: absolute; inset: 0 0 auto; height: 520px; background: center / cover; filter: blur(60px) brightness(.35); opacity: .7; z-index: -1;
  mask-image: linear-gradient(#000, transparent); }
header { display: flex; gap: 40px; padding: 0 var(--pad) 40px; align-items: flex-start; }
.photo { width: 260px; aspect-ratio: 2 / 3; object-fit: cover; border-radius: 10px; box-shadow: 0 12px 40px rgba(0, 0, 0, .6); flex: none; }
.info { display: grid; gap: 10px; max-width: 820px; }
.eyebrow { color: var(--orange); font-weight: 800; letter-spacing: 2.5px; font-size: 13px; }
h1 { font-size: 48px; font-weight: 900; }
.stats { display: flex; gap: 22px; align-items: center; color: var(--dim); }
.stats b { color: #fff; font-size: 18px; }
.imdb { background: #f5c518; color: #000; font-weight: 900; border-radius: 4px; padding: 2px 8px; }
.bio { line-height: 1.6; display: -webkit-box; -webkit-line-clamp: 6; line-clamp: 6; -webkit-box-orient: vertical; overflow: hidden; cursor: pointer; white-space: pre-line; }
.bio.more { display: block; }
.films { padding: 0 var(--pad); max-width: 1000px; }
.films h2 { font-size: 20px; margin-bottom: 10px; }
.year { color: var(--orange); font-weight: 800; margin: 18px 0 6px; }
.credit { display: flex; gap: 12px; align-items: baseline; padding: 8px 10px; border-radius: 6px; }
.credit:hover { background: var(--surface); }
.credit .dim { flex: 1; }
.here { color: var(--good); font-size: 11px; font-weight: 800; letter-spacing: 1px; }
</style>
