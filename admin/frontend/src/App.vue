<script setup>
import { onMounted, ref, watch } from 'vue'
import { api, signedOut, toast } from './api.js'
import People from './components/People.vue'
import Requests from './components/Requests.vue'
import Watching from './components/Watching.vue'
import Server from './components/Server.vue'

const TABS = [
  { id: 'people', label: 'People', comp: People },
  { id: 'requests', label: 'Requests', comp: Requests },
  { id: 'watching', label: 'Now watching', comp: Watching },
  { id: 'server', label: 'Server health', comp: Server },
]
const me = ref(null)
const ready = ref(false)
const tab = ref(TABS.find((t) => '#' + t.id === location.hash)?.id || 'people')
watch(tab, (t) => history.replaceState(null, '', '#' + t))
const form = ref({ username: '', password: '' })
const err = ref('')
const busy = ref(false)

onMounted(async () => {
  try { me.value = await api('me') } catch {}
  ready.value = true
})
watch(signedOut, (v) => v && (me.value = null))

async function login() {
  busy.value = true
  err.value = ''
  try {
    me.value = await api('login', { method: 'POST', body: form.value })
    signedOut.value = false
    form.value.password = ''
  } catch (e) {
    err.value = e.message
  }
  busy.value = false
}
async function logout() {
  await api('logout', { method: 'POST' }).catch(() => {})
  me.value = null
}
</script>

<template>
  <div v-if="!ready" class="center dim">Loading…</div>
  <form v-else-if="!me" class="login" @submit.prevent="login">
    <div class="brand"><span class="mark">H</span> Hevyfin <b>Admin</b></div>
    <p class="dim">Sign in with a Hevyfin admin account.</p>
    <input v-model="form.username" autocomplete="username" placeholder="Username" autofocus />
    <input v-model="form.password" type="password" autocomplete="current-password" placeholder="Password" />
    <p v-if="err" class="error">{{ err }}</p>
    <button class="btn" :disabled="busy">{{ busy ? 'Signing in…' : 'Sign in' }}</button>
  </form>
  <template v-else>
    <header class="top">
      <div class="brand"><span class="mark">H</span> Hevyfin <b>Admin</b></div>
      <nav class="tabs" role="tablist">
        <button v-for="t in TABS" :key="t.id" role="tab" :aria-selected="tab === t.id" :class="{ on: tab === t.id }" @click="tab = t.id">{{ t.label }}</button>
      </nav>
      <div class="who"><span class="dim">{{ me.name }}</span> <button class="link" @click="logout">Sign out</button></div>
    </header>
    <main><component :is="TABS.find((t) => t.id === tab).comp" :me="me" /></main>
  </template>
  <div class="toast" :class="{ show: toast }" role="status">{{ toast }}</div>
</template>
