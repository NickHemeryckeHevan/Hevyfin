<script setup>
import { onMounted, ref, watch } from 'vue'
import { ago, api, gb, say } from '../api.js'

const s = ref(null)
const error = ref('')
const kind = ref('movies')
const lib = ref(null)
const busy = ref('')

async function load() {
  try { s.value = await api('server'); error.value = '' } catch (e) { error.value = e.message }
}
async function loadLib() {
  lib.value = null
  try { lib.value = await api(`library/${kind.value}`) } catch (e) { say(e.message) }
}
onMounted(() => { load(); loadLib() })
watch(kind, loadLib)

async function action(path, done) {
  busy.value = path
  try { const r = await api(path, { method: 'POST' }); say(done(r)); setTimeout(load, 3000) } catch (e) { say(e.message) }
  busy.value = ''
}
async function remove(item) {
  if (!confirm(`Delete ${item.title} (${gb(item.size)}) with its files? This can't be undone.`)) return
  try {
    await api(`library/${kind.value}/${item.id}`, { method: 'DELETE' })
    say(`${item.title} deleted: ${gb(item.size)} freed`)
    lib.value = lib.value.filter((x) => x.id !== item.id)
    load()
  } catch (e) { say(e.message) }
}
const pct = (d) => Math.round(100 * (1 - d.free / d.total))
// A part whose service isn't set up comes back as { enabled: false }: its card is left out.
const on = (part) => part?.enabled !== false
</script>

<template>
  <section>
    <div class="row-head"><h1>Server health</h1><button class="btn ghost" @click="load">Refresh</button></div>
    <p v-if="error" class="error">{{ error }}</p>
    <p v-else-if="!s" class="dim">Loading…</p>
    <template v-else>
      <ul v-if="s.alerts.length" class="alerts">
        <li v-for="(a, i) in s.alerts" :key="i" :class="a.level">{{ a.text }}</li>
      </ul>
      <p v-else class="ok">Everything looks fine.</p>

      <div class="grid">
        <div v-if="on(s.space)" class="card">
          <h3>Space</h3>
          <template v-if="Array.isArray(s.space)">
            <div v-for="d in s.space" :key="d.path" class="space">
              <div class="row"><span>{{ d.label }}</span><span class="dim">{{ gb(d.free) }} free of {{ gb(d.total) }}</span></div>
              <div class="bar" :class="{ full: pct(d) > 95 }"><i :style="{ width: pct(d) + '%' }"></i></div>
            </div>
          </template>
          <p v-else class="error">{{ s.space.error }}</p>
        </div>

        <div v-if="on(s.downloads)" class="card">
          <h3>Downloads</h3>
          <template v-if="!s.downloads.error">
            <p>qBittorrent: <b :class="s.downloads.connection === 'connected' ? 'good' : 'warn'">{{ s.downloads.connection }}</b></p>
            <p class="dim">{{ s.downloads.downloading }} downloading · {{ s.downloads.stalled }} stalled · {{ s.downloads.torrents }} in all ·
              ↓ {{ (s.downloads.down / 1e6).toFixed(1) }} MB/s · ↑ {{ (s.downloads.up / 1e6).toFixed(1) }} MB/s</p>
            <p v-if="s.downloads.errored.length" class="warn">With errors: {{ s.downloads.errored.join(', ') }}</p>
          </template>
          <p v-else class="error">{{ s.downloads.error }}</p>
        </div>

        <div v-if="on(s.indexers)" class="card">
          <h3>Indexers</h3>
          <ul v-if="Array.isArray(s.indexers)" class="plain">
            <li v-for="i in s.indexers" :key="i.name"><span>{{ i.name }}</span><span :class="i.off ? 'warn' : 'good'">{{ i.off ? 'switched off' : 'on' }}</span></li>
          </ul>
          <p v-else class="error">{{ s.indexers.error }}</p>
          <button class="btn ghost" :disabled="busy" @click="action('server/indexers/retest', () => 'Indexers tested: working ones are back on')">Test and switch back on</button>
        </div>

        <div v-if="on(s.sonarr) || on(s.radarr)" class="card">
          <h3>Missing</h3>
          <p v-for="a in ['sonarr', 'radarr'].filter((x) => on(s[x]))" :key="a">
            <template v-if="!s[a].error">
              <b>{{ a === 'sonarr' ? 'Episodes' : 'Films' }}:</b> {{ s[a].missing }} missing, {{ s[a].queue }} in the queue
              <span v-if="s[a].problems.length" class="warn"> · {{ s[a].problems.length }} with problems</span>
            </template>
            <span v-else class="error">{{ s[a].error }}</span>
          </p>
          <details v-for="a in ['sonarr', 'radarr'].filter((x) => on(s[x]))" :key="a + 'p'" v-show="s[a].problems?.length">
            <summary>{{ a === 'sonarr' ? 'Episode' : 'Film' }} download problems</summary>
            <ul class="plain small"><li v-for="p in s[a].problems" :key="p.title"><span>{{ p.title }}</span><span class="dim">{{ p.message }}</span></li></ul>
          </details>
          <button class="btn ghost" :disabled="busy" @click="action('server/search-missing', () => 'Searching for everything missing')">Search for missing now</button>
        </div>
      </div>

      <template v-if="s.watch">
        <h2>On the lookout</h2>
        <p class="dim">Checked daily on the indexers{{ s.watch.checked ? ', last ' + ago(s.watch.checked) : '' }}. Nothing is downloaded by itself: check it first.</p>
        <div class="grid">
          <div v-for="w in s.watch.watches" :key="w.id" class="card">
            <h3>{{ w.name }}</h3>
            <p class="dim small">{{ w.hint }}</p>
            <p v-if="w.error" class="error">{{ w.error }}</p>
            <ul v-if="w.found.length" class="plain">
              <li v-for="f in w.found" :key="f.title">
                <span>{{ f.title }} <span class="dim">· {{ gb(f.size) }} · {{ f.seeders ?? '?' }} seeds · {{ f.indexer }} · found {{ ago(f.firstSeen) }}</span></span>
                <a v-if="f.url" class="link" :href="f.url" target="_blank" rel="noopener">Look</a>
              </li>
            </ul>
            <p v-else class="ok">Nothing new yet.</p>
          </div>
        </div>
      </template>

      <template v-if="on(s.sonarr) || on(s.radarr)">
      <h2>Free up space</h2>
      <div class="segmented">
        <button :class="{ on: kind === 'movies' }" @click="kind = 'movies'">Films</button>
        <button :class="{ on: kind === 'shows' }" @click="kind = 'shows'">Shows</button>
      </div>
      <p class="dim">Biggest first. Deleting removes the files too, so it can't be watched any more.</p>
      <p v-if="!lib" class="dim">Loading…</p>
      <table v-else class="lib">
        <thead><tr><th>Title</th><th>Size</th><th>Watched by</th><th></th></tr></thead>
        <tbody>
          <tr v-for="x in lib" :key="x.id">
            <td>{{ x.title }} <span class="dim">{{ x.year }}</span></td>
            <td>{{ gb(x.size) }}</td>
            <td :class="{ dim: !x.watchedBy.length }">{{ x.watchedBy.join(', ') || 'nobody yet' }}</td>
            <td><button class="link danger" @click="remove(x)">Delete</button></td>
          </tr>
        </tbody>
      </table>
      </template>
    </template>
  </section>
</template>
