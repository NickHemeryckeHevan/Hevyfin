<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { ago, api, say } from '../api.js'

const list = ref(null)
const error = ref('')
const msg = ref('')
let timer
async function load() {
  try {
    list.value = await api('sessions')
    error.value = ''
  } catch (e) {
    error.value = e.message
  }
}
onMounted(() => { load(); timer = setInterval(load, 10000) })
onUnmounted(() => clearInterval(timer))
const playing = computed(() => (list.value || []).filter((s) => s.playing))
const idle = computed(() => (list.value || []).filter((s) => !s.playing))

async function stop(s) {
  if (!confirm(`Stop ${s.user}'s ${s.playing.series || s.playing.title} on ${s.device}?`)) return
  try { await api(`sessions/${s.id}/stop`, { method: 'POST' }); say('Stopped'); load() } catch (e) { say(e.message) }
}
async function send() {
  try {
    const r = await api('sessions/message', { method: 'POST', body: { text: msg.value } })
    say(r.sent ? `Shown on ${r.sent} screen${r.sent > 1 ? 's' : ''}` : 'No screen that shows messages is open')
    msg.value = ''
  } catch (e) { say(e.message) }
}
</script>

<template>
  <section>
    <div class="row-head"><h1>Now watching</h1><span class="dim">refreshes every 10 s</span></div>
    <p v-if="error" class="error">{{ error }}</p>
    <p v-else-if="!list" class="dim">Loading…</p>
    <template v-else>
      <p v-if="!playing.length" class="empty">Nobody is watching right now.</p>
      <div class="grid">
        <article v-for="s in playing" :key="s.id" class="card">
          <h3>{{ s.playing.series || s.playing.title }}</h3>
          <p class="dim">{{ s.playing.series ? s.playing.episode + ' · ' + s.playing.title : s.playing.type }}</p>
          <p><b>{{ s.user }}</b> on {{ s.device }} <span class="dim">({{ s.client }}) · {{ s.address }}</span></p>
          <div class="bar" :aria-label="`${s.playing.progress}% watched`"><i :style="{ width: (s.playing.progress || 0) + '%' }"></i></div>
          <p class="dim">
            {{ s.playing.paused ? 'Paused' : 'Playing' }} ·
            <template v-if="s.playing.transcode">
              <span class="warn">converting</span> to {{ s.playing.transcode.video }}/{{ s.playing.transcode.audio }}, {{ s.playing.transcode.mbps }} Mbps{{ s.playing.transcode.hardware ? ' on the GPU' : ' on the CPU' }}
              <span v-if="s.playing.transcode.reasons.length"> ({{ s.playing.transcode.reasons.join(', ') }})</span>
            </template>
            <template v-else>{{ s.playing.method === 'DirectPlay' ? 'played as it is' : s.playing.method }}</template>
          </p>
          <div class="actions"><button class="btn ghost danger" @click="stop(s)">Stop</button></div>
        </article>
      </div>
      <template v-if="idle.length">
        <h2>Open, not playing</h2>
        <ul class="plain card">
          <li v-for="s in idle" :key="s.id"><span><b>{{ s.user || '—' }}</b> on {{ s.device }} <span class="dim">({{ s.client }}) · {{ ago(s.lastActivity) }}</span></span></li>
        </ul>
      </template>
      <h2>Message to every screen</h2>
      <form class="card fields" @submit.prevent="send">
        <label>Message<input v-model="msg" maxlength="300" placeholder="The server restarts in 5 minutes" required /></label>
        <button class="btn">Send</button>
      </form>
    </template>
  </section>
</template>
