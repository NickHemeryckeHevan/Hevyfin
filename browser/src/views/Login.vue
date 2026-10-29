<script setup>
// Sign in with the Jellyfin account (Seerr is signed in with it too, for requests).
import { ref } from 'vue'
import Wordmark from '../components/Wordmark.vue'
import { adding, login, profiles } from '../state/session.js'

const user = ref('')
const pass = ref('')
const busy = ref(false)
const error = ref('')

async function submit() {
  if (!user.value.trim()) return
  busy.value = true
  error.value = ''
  try {
    await login(user.value, pass.value)
  } catch (e) {
    error.value = e.message
  }
  busy.value = false
}
</script>

<template>
  <div class="login-page">
    <Wordmark :size="34" class="mark" />
    <form class="box" @submit.prevent="submit">
      <h1>Sign in</h1>
      <input v-model="user" autocomplete="username" placeholder="Username" autofocus />
      <input v-model="pass" type="password" autocomplete="current-password" placeholder="Password" />
      <p v-if="error" class="danger">{{ error }}</p>
      <button class="btn orange" :disabled="busy">{{ busy ? 'Signing in…' : 'Sign in' }}</button>
      <button v-if="profiles.length" type="button" class="btn flat" @click="adding = false">Back to profiles</button>
      <p class="small mute">Use your Jellyfin account, the same one as in the apps.</p>
    </form>
  </div>
</template>

<style scoped>
.login-page { min-height: 100vh; display: grid; place-items: center; padding: 24px;
  background: radial-gradient(ellipse at 50% -20%, #3a1a06, var(--bg) 65%); }
.mark { position: fixed; top: 26px; left: var(--pad); }
.box { width: min(400px, 100%); display: grid; gap: 14px; background: rgba(0, 0, 0, .7); padding: 48px 56px; border-radius: 6px; }
.box h1 { font-size: 30px; font-weight: 800; margin-bottom: 8px; }
</style>
