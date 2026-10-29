<script setup>
import { onMounted, onUnmounted, ref, watch } from 'vue'
import { ago, api, say } from '../api.js'

const FILTERS = [
  { id: 'pending', label: 'Waiting' }, { id: 'processing', label: 'Downloading' }, { id: 'available', label: 'Ready' }, { id: 'all', label: 'All' },
]
const filter = ref('pending')
const data = ref(null)
const error = ref('')
const busy = ref(new Set())
let timer

async function load() {
  try {
    data.value = await api(`requests?filter=${filter.value}`)
    error.value = ''
  } catch (e) {
    error.value = e.message
  }
}
watch(filter, () => { data.value = null; load() })
onMounted(() => { load(); timer = setInterval(load, 30000) })
onUnmounted(() => clearInterval(timer))

async function decide(r, action) {
  busy.value.add(r.id)
  try {
    await api(`requests/${r.id}/${action}`, { method: 'POST' })
    say(`${r.title}: ${action === 'approve' ? 'approved, downloading' : 'declined'}`)
    await load()
  } catch (e) {
    say(e.message)
  }
  busy.value.delete(r.id)
}

// Ask on someone's behalf.
const q = ref('')
const results = ref([])
const people = ref([])
const forWho = ref('')
let searchTimer
watch(q, (v) => {
  clearTimeout(searchTimer)
  searchTimer = setTimeout(async () => (results.value = v.trim() ? await api(`search?q=${encodeURIComponent(v)}`).catch(() => []) : []), 350)
})
onMounted(async () => {
  const p = await api('people').catch(() => null)
  people.value = (p?.people || []).filter((x) => x.seerr).map((x) => ({ id: x.seerr.id, name: x.name }))
})
async function requestFor(m) {
  try {
    await api('requests', { method: 'POST', body: { type: m.type, id: m.id, userId: forWho.value || null } })
    say(`Requested ${m.title}${forWho.value ? ' for ' + people.value.find((p) => p.id === forWho.value)?.name : ''}`)
    q.value = ''
    load()
  } catch (e) {
    say(e.message)
  }
}
</script>

<template>
  <section>
    <div class="row-head">
      <h1>Requests</h1>
      <span v-if="data" class="dim">{{ data.counts.pending }} waiting · {{ data.counts.processing }} downloading · {{ data.counts.total }} in all</span>
    </div>
    <div class="segmented" role="tablist">
      <button v-for="f in FILTERS" :key="f.id" :class="{ on: filter === f.id }" :aria-selected="filter === f.id" @click="filter = f.id">
        {{ f.label }}<span v-if="f.id === 'pending' && data?.counts.pending" class="badge">{{ data.counts.pending }}</span>
      </button>
    </div>
    <p v-if="error" class="error">{{ error }}</p>
    <p v-else-if="!data" class="dim">Loading…</p>
    <p v-else-if="!data.requests.length" class="empty">{{ filter === 'pending' ? 'Nothing waiting for you.' : 'Nothing here.' }}</p>
    <div v-else class="grid">
      <article v-for="r in data.requests" :key="r.id" class="card req">
        <img v-if="r.poster" :src="r.poster" alt="" width="70" height="105" loading="lazy" />
        <div v-else class="poster-ph">{{ r.type === 'tv' ? 'TV' : 'Film' }}</div>
        <div class="req-body">
          <h3>{{ r.title }} <span class="dim">{{ r.year }}</span></h3>
          <p class="dim">{{ r.type === 'tv' ? 'Series' + (r.seasons.length ? ' · seasons ' + r.seasons.join(', ') : '') : 'Film' }}</p>
          <p>Asked by <b>{{ r.by }}</b> · {{ ago(r.at) }}</p>
          <p class="dim">{{ r.status }}{{ r.media && r.status !== 'pending' ? ' · ' + r.media : '' }}{{ r.decidedBy ? ' by ' + r.decidedBy : '' }}</p>
          <div v-if="r.status === 'pending'" class="actions">
            <button class="btn" :disabled="busy.has(r.id)" @click="decide(r, 'approve')">Approve</button>
            <button class="btn ghost" :disabled="busy.has(r.id)" @click="decide(r, 'decline')">Decline</button>
          </div>
        </div>
      </article>
    </div>

    <h2>Request for someone</h2>
    <div class="card">
      <div class="fields">
        <label>Film or show<input v-model="q" placeholder="Search…" /></label>
        <label>For
          <select v-model="forWho"><option value="">Me</option><option v-for="p in people" :key="p.id" :value="p.id">{{ p.name }}</option></select>
        </label>
      </div>
      <ul v-if="results.length" class="plain results">
        <li v-for="m in results" :key="m.type + m.id">
          <span>{{ m.title }} <span class="dim">{{ m.year }} · {{ m.type === 'tv' ? 'series' : 'film' }}{{ m.status ? ' · ' + m.status : '' }}</span></span>
          <button v-if="!m.status || m.status === 'unknown' || m.status === 'deleted'" class="link" @click="requestFor(m)">Request</button>
        </li>
      </ul>
    </div>
  </section>
</template>
