<script setup>
// Shown when Seerr isn't signed in: one password field (the same account as Hevyfin).
import { ref } from 'vue'
import Icon from './Icon.vue'
import * as seerr from '../api/seerr.js'
import { session } from '../state/session.js'

const pw = ref('')
const busy = ref(false)
const error = ref('')

async function go() {
  busy.value = true
  error.value = ''
  try {
    await seerr.login(session.value.userName, pw.value)
  } catch (e) {
    error.value = e.message
  }
  busy.value = false
}
</script>

<template>
  <form class="connect" @submit.prevent="go">
    <Icon name="inbox" :size="52" class="mark" />
    <h2>Connect Seerr</h2>
    <p class="dim">Requests go through Seerr. Enter your password for {{ session.userName }} to link it.</p>
    <input v-model="pw" type="password" placeholder="Password" autocomplete="current-password" autofocus />
    <p v-if="error" class="danger">{{ error }}</p>
    <button class="btn orange" :disabled="busy">{{ busy ? 'Connecting…' : 'Connect' }}</button>
  </form>
</template>

<style scoped>
.connect { width: min(420px, 100%); margin: 0 auto; padding: calc(var(--bar) + 60px) 0 60px; display: grid; gap: 14px; text-align: center; }
.mark { justify-self: center; color: var(--orange); }
h2 { font-size: 24px; font-weight: 900; }
</style>
