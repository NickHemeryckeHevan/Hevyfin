<script setup>
// Account, languages, subtitles, playback, Seerr, and signing a TV in (port of settings.dart).
// Settings are this browser's own, like each app keeps its own.
import { ref } from 'vue'
import Icon from '../components/Icon.vue'
import { VERSION, quickConnectApprove } from '../api/jellyfin.js'
import * as seerr from '../api/seerr.js'
import { capabilities } from '../lib/playback.js'
import { ask } from '../dialog.js'
import { choosing, logout, prefs, profiles, say, session } from '../state/session.js'

const LANGS = { eng: 'English', dut: 'Dutch', fre: 'French', ger: 'German', spa: 'Spanish', jpn: 'Japanese' }
const QUALITY = { 0: 'Original (no conversion)', 40: '40 Mbps', 20: '20 Mbps – 1080p', 10: '10 Mbps', 6: '6 Mbps – 720p', 3: '3 Mbps – mobile data' }
const SIZES = { 0.8: 'Small', 1: 'Normal', 1.25: 'Large', 1.5: 'Extra large' }
const caps = capabilities()
const plays = ['h264', 'hevc', 'av1', 'vp9'].filter((c) => caps[c]).map((c) => c.toUpperCase().replace('H264', 'H.264').replace('HEVC', 'HEVC (H.265)'))
const seerrPass = ref('')
document.title = 'Settings · Hevyfin'

async function tvCode() {
  const code = await ask({ title: 'Sign in a TV', text: 'Type the code shown on the TV.', value: '', ok: 'Approve' })
  if (!code) return
  try {
    await quickConnectApprove(code)
    say('The TV is signed in')
  } catch (e) {
    say(e.message)
  }
}

async function seerrLogin() {
  try {
    await seerr.login(session.value.userName, seerrPass.value)
    seerrPass.value = ''
    say('Signed in to Seerr')
  } catch (e) {
    say(e.message)
  }
}
</script>

<template>
  <main class="page settings">
    <h1 class="page-title">Settings</h1>

    <section>
      <h2>Account</h2>
      <div class="line"><span><b>{{ session.userName }}</b><span class="dim small">Signed in on this browser</span></span>
        <button class="btn ghost" @click="logout">Sign out</button></div>
      <div class="line"><span><b>Switch profile</b><span class="dim small">{{ profiles.length }} on this browser · add, lock with a PIN or remove under Manage profiles</span></span>
        <button class="btn ghost" @click="choosing = true"><Icon name="profiles" /> Profiles</button></div>
      <div class="line"><span><b>Sign in a TV</b><span class="dim small">Enter the code Hevyfin shows on your TV</span></span>
        <button class="btn ghost" @click="tvCode"><Icon name="tv" /> Enter code</button></div>
    </section>

    <section>
      <h2>Languages & subtitles</h2>
      <label class="line"><b>Audio language</b><select v-model="prefs.audioLang"><option v-for="(l, k) in LANGS" :key="k" :value="k">{{ l }}</option></select></label>
      <label class="line"><b>Subtitles by default</b><select v-model="prefs.subtitleLang"><option value="">Off</option><option v-for="(l, k) in LANGS" :key="k" :value="k">{{ l }}</option></select></label>
      <label class="line"><b>Subtitle size</b><select v-model.number="prefs.subSize"><option v-for="(l, k) in SIZES" :key="k" :value="Number(k)">{{ l }}</option></select></label>
      <label class="line"><b>Subtitle colour</b><select v-model="prefs.subColor"><option value="white">White</option><option value="yellow">Yellow</option></select></label>
      <label class="line check"><span><b>Dark box behind subtitles</b></span><input v-model="prefs.subBox" type="checkbox" /></label>
      <div class="sample"><span :class="{ box: prefs.subBox }" :style="{ fontSize: 26 * prefs.subSize + 'px', color: prefs.subColor === 'yellow' ? '#ffe14d' : '#fff' }">This is how subtitles look.</span></div>
    </section>

    <section>
      <h2>Playback</h2>
      <label class="line check"><span><b>Skip intros and recaps</b><span class="dim small">Jump straight past them instead of showing a Skip button.</span></span>
        <input v-model="prefs.autoSkip" type="checkbox" /></label>
      <label class="line"><span><b>Streaming quality</b><span class="dim small">Original plays the file as it is when this browser can. A cap makes the server convert it: handy on a slow connection.</span></span>
        <select v-model.number="prefs.maxMbps"><option v-for="(l, k) in QUALITY" :key="k" :value="Number(k)">{{ l }}</option></select></label>
      <p class="dim small">This browser plays {{ plays.join(', ') || 'no video formats it says it knows' }} itself{{ caps.hdr ? ', and HDR on this screen' : '' }}; the server converts the rest.</p>
    </section>

    <section>
      <h2>Requests (Seerr)</h2>
      <div v-if="seerr.seerrReady.value" class="line"><span><b>Signed in to Seerr</b><span class="dim small">Requests go in as {{ session.userName }}</span></span><Icon name="check" class="ok" /></div>
      <form v-else class="line" @submit.prevent="seerrLogin">
        <span><b>Not signed in to Seerr</b><span class="dim small">Your Hevyfin password, to request films and shows</span></span>
        <span class="inline"><input v-model="seerrPass" type="password" placeholder="Password" autocomplete="current-password" /><button class="btn orange">Sign in</button></span>
      </form>
    </section>

    <p class="mute small">Hevyfin for the browser {{ VERSION }} · a free Jellyfin + Seerr client (GPL-3.0) · <a href="https://github.com/NickHemeryckeHevan/hevyfin" target="_blank" rel="noopener">source</a></p>
  </main>
</template>

<style scoped>
.settings { max-width: 860px; }
section { margin-bottom: 34px; }
h2 { font-size: 15px; color: var(--dim); text-transform: uppercase; letter-spacing: 1.5px; margin-bottom: 8px; }
.line { display: flex; justify-content: space-between; align-items: center; gap: 24px; padding: 14px 0; border-bottom: 1px solid var(--line); }
.line > span:first-child { display: grid; gap: 2px; }
.line select { width: 240px; }
.check input { width: 20px; height: 20px; }
.inline { display: flex; gap: 8px; }
.inline input { width: 200px; }
.sample { margin-top: 14px; height: 120px; border-radius: 8px; display: grid; place-items: end center; padding-bottom: 18px;
  background: linear-gradient(135deg, #3a4a5a, #1a2228); }
.sample span { font-weight: 600; text-shadow: 0 0 8px #000, 1px 1px 2px #000; }
.sample span.box { background: rgba(0, 0, 0, .7); padding: 2px 10px; text-shadow: none; }
.ok { color: var(--good); }
</style>
