<script setup>
import { computed, onMounted, ref } from 'vue'
import { ago, api, say } from '../api.js'

const props = defineProps({ me: Object })
const data = ref(null)
const open = ref(null)
const devices = ref([])
const error = ref('')

const pw = ref({ password: '', current: '', signOut: true })
const access = ref({})
const req = ref({})
const adding = ref(false)
const add = ref({ name: '', password: '' })

const CAPS = [
  { v: 0, label: 'No limit' }, { v: 4, label: '4 Mbps (720p)' }, { v: 8, label: '8 Mbps (1080p)' }, { v: 15, label: '15 Mbps' }, { v: 2, label: '2 Mbps (data saver)' },
]
const DAYS = [
  { v: 'Everyday', label: 'Every day' }, { v: 'Weekday', label: 'Weekdays' }, { v: 'Weekend', label: 'Weekends' },
]

async function load() {
  try {
    data.value = await api('people')
  } catch (e) {
    error.value = e.message
  }
}
onMounted(load)

const person = computed(() => data.value?.people.find((p) => p.id === open.value))
const self = computed(() => open.value === props.me.id)
const libName = (id) => data.value.libraries.find((l) => l.id === id)?.name || '?'
const ratingName = (v) => (v == null ? 'Everything' : data.value.ratings.find((r) => r.value === v)?.name || `≤ ${v}`)

async function select(p) {
  if (open.value === p.id) return (open.value = null)
  open.value = p.id
  pw.value = { password: '', current: '', signOut: true }
  access.value = {
    maxParentalRating: p.maxParentalRating, allLibraries: p.allLibraries, libraries: [...p.libraries],
    remoteBitrateMbps: Math.round(p.remoteBitrate / 1e6), hours: p.schedules[0] ? { ...p.schedules[0] } : null,
  }
  req.value = p.seerr
    ? { canRequest: p.seerr.canRequest, autoApprove: p.seerr.autoApprove, movieQuota: { ...p.seerr.movieQuota }, tvQuota: { ...p.seerr.tvQuota } }
    : null
  devices.value = await api(`people/${p.id}/devices`).catch(() => [])
}

async function run(fn, done) {
  try {
    const r = await fn()
    if (done) say(typeof done === 'function' ? done(r) : done)
    await load()
    if (open.value) devices.value = await api(`people/${open.value}/devices`).catch(() => [])
  } catch (e) {
    say(e.message)
  }
}

const setPassword = () =>
  run(async () => {
    const r = await api(`people/${open.value}/password`, { method: 'POST', body: pw.value })
    pw.value = { password: '', current: '', signOut: pw.value.signOut }
    return r
  }, (r) => `Password changed${r.signedOut ? `; signed out on ${r.signedOut} device${r.signedOut > 1 ? 's' : ''}` : ''}`)
const toggleDisabled = () => run(() => api(`people/${open.value}/policy`, { method: 'PUT', body: { disabled: !person.value.disabled } }), person.value.disabled ? 'Switched on' : 'Switched off')
const saveAccess = () =>
  run(() => {
    const a = access.value
    return api(`people/${open.value}/policy`, {
      method: 'PUT',
      body: {
        maxParentalRating: a.maxParentalRating, allLibraries: a.allLibraries, libraries: a.libraries, remoteBitrateMbps: a.remoteBitrateMbps,
        schedules: a.hours ? [{ DayOfWeek: a.hours.DayOfWeek, StartHour: a.hours.StartHour, EndHour: a.hours.EndHour }] : [],
      },
    })
  }, 'Saved')
const saveRequests = () => run(() => api(`people/${open.value}/requests`, { method: 'PUT', body: req.value }), 'Saved')
const signOutDevice = (d) => run(() => api(`people/${open.value}/devices/${d.id}`, { method: 'DELETE' }), `Signed out on ${d.name}`)
const signOutAll = () => confirm(`Sign ${person.value.name} out on every device?`) && run(() => api(`people/${open.value}/signout`, { method: 'POST' }), (r) => `Signed out on ${r.signedOut} devices`)
const addPerson = () =>
  run(async () => {
    const r = await api('people', { method: 'POST', body: add.value })
    adding.value = false
    add.value = { name: '', password: '' }
    return r
  }, (r) => `${r.name} added: they can sign in to Hevyfin now`)
</script>

<template>
  <p v-if="error" class="error">{{ error }}</p>
  <p v-else-if="!data" class="dim">Loading…</p>
  <section v-else>
    <div class="row-head">
      <h1>People</h1>
      <button class="btn ghost" @click="adding = !adding">{{ adding ? 'Cancel' : 'Add someone' }}</button>
    </div>
    <form v-if="adding" class="card form" @submit.prevent="addPerson">
      <h3>A new Hevyfin account</h3>
      <div class="fields">
        <label>Name<input v-model="add.name" required /></label>
        <label>Password<input v-model="add.password" type="password" minlength="4" required /></label>
      </div>
      <p class="dim">They also get a Seerr account, so they can request films and shows.</p>
      <button class="btn">Add</button>
    </form>

    <div class="list">
      <div v-for="p in data.people" :key="p.id" class="person" :class="{ open: open === p.id, off: p.disabled }">
        <button class="person-row" @click="select(p)" :aria-expanded="open === p.id">
          <span class="avatar">{{ p.name[0].toUpperCase() }}</span>
          <span class="pname">{{ p.name }}
            <span v-if="p.admin" class="tag">admin</span>
            <span v-if="p.disabled" class="tag bad">switched off</span>
            <span v-if="p.maxParentalRating != null" class="tag">≤ {{ ratingName(p.maxParentalRating) }}</span>
            <span v-if="p.schedules.length" class="tag">hours</span>
          </span>
          <span class="dim">active {{ ago(p.lastActivity) }} · {{ p.devices }} device{{ p.devices === 1 ? '' : 's' }}</span>
        </button>

        <div v-if="open === p.id" class="editor">
          <div class="card">
            <h3>Password</h3>
            <form class="fields" @submit.prevent="setPassword">
              <label v-if="self">Current password<input v-model="pw.current" type="password" autocomplete="current-password" required /></label>
              <label>New password<input v-model="pw.password" type="password" autocomplete="new-password" minlength="4" required /></label>
              <label class="check"><input v-model="pw.signOut" type="checkbox" /> Also sign {{ self ? 'me' : 'them' }} out on all devices</label>
              <button class="btn">Set password</button>
            </form>
            <p class="dim">Seerr uses the same password.</p>
          </div>

          <div class="card">
            <h3>Devices</h3>
            <ul class="plain">
              <li v-for="d in devices" :key="d.id">
                <span>{{ d.name }} <span class="dim">· {{ d.app }} · {{ ago(d.lastSeen) }}</span></span>
                <button v-if="!d.panel" class="link" @click="signOutDevice(d)">Sign out</button>
                <span v-else class="dim">this panel</span>
              </li>
              <li v-if="!devices.length" class="dim">Not signed in anywhere.</li>
            </ul>
            <div class="actions">
              <button v-if="devices.some((d) => !d.panel)" class="btn ghost" @click="signOutAll">Sign out everywhere</button>
              <button v-if="!self" class="btn ghost" :class="{ danger: !p.disabled }" @click="toggleDisabled">{{ p.disabled ? 'Switch account on' : 'Switch account off' }}</button>
            </div>
          </div>

          <div class="card">
            <h3>What they can watch</h3>
            <div class="fields">
              <label>Age limit
                <select v-model="access.maxParentalRating">
                  <option :value="null">Everything</option>
                  <option v-for="r in data.ratings" :key="r.value" :value="r.value">Up to {{ r.name }}</option>
                </select>
              </label>
              <label>Streaming away from home
                <select v-model="access.remoteBitrateMbps"><option v-for="c in CAPS" :key="c.v" :value="c.v">{{ c.label }}</option></select>
              </label>
            </div>
            <label class="check"><input v-model="access.allLibraries" type="checkbox" /> All libraries</label>
            <div v-if="!access.allLibraries" class="chips">
              <label v-for="l in data.libraries" :key="l.id" class="check"><input v-model="access.libraries" type="checkbox" :value="l.id" /> {{ l.name }}</label>
            </div>
            <label class="check"><input type="checkbox" :checked="!!access.hours" @change="access.hours = $event.target.checked ? { DayOfWeek: 'Everyday', StartHour: 7, EndHour: 21 } : null" /> Only at set hours</label>
            <div v-if="access.hours" class="fields">
              <label>Days<select v-model="access.hours.DayOfWeek"><option v-for="d in DAYS" :key="d.v" :value="d.v">{{ d.label }}</option></select></label>
              <label>From<input v-model.number="access.hours.StartHour" type="number" min="0" max="23" /></label>
              <label>Until<input v-model.number="access.hours.EndHour" type="number" min="1" max="24" /></label>
            </div>
            <button class="btn" @click="saveAccess">Save</button>
          </div>

          <div class="card">
            <h3>Requests</h3>
            <template v-if="req && !p.seerr.admin">
              <label class="check"><input v-model="req.canRequest" type="checkbox" /> Can request films and shows</label>
              <label class="check"><input v-model="req.autoApprove" type="checkbox" /> Approved automatically (no waiting for you)</label>
              <div class="fields">
                <label>Films per period<input v-model.number="req.movieQuota.limit" type="number" min="0" placeholder="no limit" /></label>
                <label>Days<input v-model.number="req.movieQuota.days" type="number" min="1" placeholder="7" /></label>
                <label>Seasons per period<input v-model.number="req.tvQuota.limit" type="number" min="0" placeholder="no limit" /></label>
                <label>Days<input v-model.number="req.tvQuota.days" type="number" min="1" placeholder="7" /></label>
              </div>
              <p class="dim">{{ p.seerr.requests }} requests so far.</p>
              <button class="btn" @click="saveRequests">Save</button>
            </template>
            <p v-else-if="p.seerr?.admin" class="dim">A Seerr admin: can do everything.</p>
            <template v-else>
              <p class="dim">No Seerr account yet, so they can't request.</p>
              <button class="btn" @click="run(() => api(`people/${open}/requests`, { method: 'PUT', body: { canRequest: true } }), 'They can request now')">Let them request</button>
            </template>
          </div>
        </div>
      </div>
    </div>
  </section>
</template>
