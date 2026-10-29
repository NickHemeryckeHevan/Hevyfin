<script setup>
// "Who's watching?": everyone signed in on this browser, plus adding someone. Each profile is
// its own Jellyfin account, so Continue watching, My List and requests follow it.
import { ref } from 'vue'
import Wordmark from '../components/Wordmark.vue'
import Icon from '../components/Icon.vue'
import { ask } from '../dialog.js'
import { adding, choosing, pinMatches, profiles, removeProfile, say, session, setPin, switchTo } from '../state/session.js'

const COLORS = [['#ff8a1f', '#ff4d2e'], ['#4fc3f7', '#3a6ff7'], ['#66e3a1', '#1fa67a'], ['#f06bd0', '#9b5cf6'], ['#ffd54f', '#ff9f1c']]
const manage = ref(false)
const busy = ref(null)

const askPin = (title) => ask({ title, value: '', ok: 'OK' })

async function open(p) {
  if (manage.value) return edit(p)
  if (p.pin) {
    const pin = await askPin(`Enter ${p.name}'s PIN`)
    if (pin === null) return
    if (!pinMatches(p, pin)) return say('Wrong PIN')
  }
  busy.value = p.id
  try {
    await switchTo(p)
  } catch (e) {
    say(`Couldn't switch: ${e.message}`)
  }
  busy.value = null
}

async function edit(p) {
  // Changing or removing a PIN needs the current one.
  if (p.pin) {
    const old = await askPin('Current PIN')
    if (old === null) return
    if (!pinMatches(p, old)) return say('Wrong PIN')
  }
  const pin = await ask({ title: `${p.name}: PIN`, text: '4 digits to switch to this profile. Leave empty for none.', value: '', ok: 'Save' })
  if (pin !== null) {
    if (pin && !/^\d{4}$/.test(pin)) return say('A PIN is 4 digits')
    setPin(p, pin)
    say(pin ? 'PIN set' : 'PIN removed')
  }
}

async function remove(p) {
  if (await ask({ title: `Remove ${p.name} from this browser?`, text: 'They can sign in again any time.', ok: 'Remove', danger: true })) removeProfile(p)
}
</script>

<template>
  <div class="who">
    <Wordmark :size="30" class="mark" />
    <h1>{{ manage ? 'Manage profiles' : "Who's watching?" }}</h1>
    <div class="list">
      <div v-for="(p, n) in profiles" :key="p.id" class="profile">
        <button class="tile" :style="{ background: `linear-gradient(135deg, ${COLORS[n % 5][0]}, ${COLORS[n % 5][1]})` }" :disabled="!!busy" @click="open(p)">
          <span>{{ p.name[0]?.toUpperCase() }}</span>
          <i v-if="manage" class="edit"><Icon name="lock" :size="34" /></i>
          <i v-else-if="busy === p.id" class="edit"><span class="spinner" /></i>
        </button>
        <div class="name">{{ p.name }} <Icon v-if="p.pin" name="lock" :size="14" /></div>
        <button v-if="manage" class="btn flat small" @click="remove(p)">Remove</button>
      </div>
      <div v-if="!manage" class="profile">
        <button class="tile add" @click="adding = true"><Icon name="plus" :size="54" /></button>
        <div class="name">Add someone</div>
      </div>
    </div>
    <div class="foot">
      <button class="btn ghost" @click="manage = !manage">{{ manage ? 'Done' : 'Manage profiles' }}</button>
      <button v-if="session && !manage" class="btn flat" @click="choosing = false">Back</button>
    </div>
  </div>
</template>

<style scoped>
.who { min-height: 100vh; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 40px; padding: 80px 24px;
  background: radial-gradient(ellipse at 50% -10%, #2a1405, var(--bg) 70%); }
.mark { position: fixed; top: 26px; left: var(--pad); }
h1 { font-size: 46px; font-weight: 800; letter-spacing: -.5px; }
.list { display: flex; flex-wrap: wrap; justify-content: center; gap: 28px; }
.profile { display: grid; justify-items: center; gap: 10px; width: 150px; }
.tile { position: relative; width: 150px; height: 150px; border-radius: 8px; border: 3px solid transparent; cursor: pointer; display: grid; place-items: center;
  color: #000; font-size: 64px; font-weight: 900; transition: border-color .15s, transform .15s; }
.tile:hover, .tile:focus-visible { border-color: #fff; transform: scale(1.03); outline: 0; }
.tile.add { background: transparent; border: 3px solid #444; color: var(--dim); }
.tile.add:hover { color: #fff; }
.edit { position: absolute; inset: 0; display: grid; place-items: center; background: rgba(0, 0, 0, .55); color: #fff; border-radius: 5px; }
.name { color: var(--dim); font-size: 17px; display: flex; gap: 6px; align-items: center; }
.profile:hover .name { color: #fff; }
.foot { display: flex; gap: 10px; }
</style>
