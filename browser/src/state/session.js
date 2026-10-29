// Who's signed in, the profiles on this browser, and this browser's settings (port of
// lib/state/app_state.dart). Kept in localStorage under "hevyfin.*"; the first start takes
// over the Flutter web version's sign-ins ("flutter.*" on the same address).
import { reactive, ref, watch } from 'vue'
import * as jf from '../api/jellyfin.js'
import * as seerr from '../api/seerr.js'
import { sha256 } from '../lib/sha256.js'

const KEY = 'hevyfin.'
const read = (k, fallback) => {
  try {
    const v = localStorage.getItem(KEY + k)
    return v === null ? fallback : JSON.parse(v)
  } catch {
    return fallback
  }
}
const write = (k, v) => (v === undefined || v === null ? localStorage.removeItem(KEY + k) : localStorage.setItem(KEY + k, JSON.stringify(v)))

/** Settings on this browser. */
export const prefs = reactive({
  audioLang: 'eng', // ISO 639-2
  subtitleLang: '', // '' = off
  maxMbps: 0, // 0 = original quality
  autoSkip: false,
  trailerPreviews: true,
  subSize: 1,
  subColor: 'white',
  subBox: false,
  storyOrder: [], // collection ids watched in story order
  volume: 1,
})

/** The signed-in account, or null. */
export const session = ref(null)
/** Everyone signed in on this browser: {id, name, token, pin?}. */
export const profiles = ref([])
/** "Who's watching?" is up / someone else is being signed in. */
export const choosing = ref(false)
export const adding = ref(false)
/** Ids in My List (Jellyfin favourites). */
export const myList = reactive(new Set())
/** Bumped when lists should reload (watched, My List, requests). */
export const revision = ref(0)
export const bump = () => {
  jf.forget()
  revision.value++
}

function newDeviceId() {
  const r = crypto.getRandomValues(new Uint8Array(8))
  return 'hevyfin-' + [...r].map((b) => b.toString(16).padStart(2, '0')).join('')
}

/** The Flutter web version kept its settings as "flutter.<key>", JSON-encoded. */
function importFlutter() {
  if (read('imported', false)) return
  const f = (k) => {
    try {
      const v = localStorage.getItem('flutter.' + k)
      return v === null ? undefined : JSON.parse(v)
    } catch {
      return undefined
    }
  }
  for (const k of ['audioLang', 'subtitleLang', 'maxMbps', 'autoSkip', 'trailerPreviews', 'subSize', 'subColor', 'subBox', 'storyOrder']) {
    if (f(k) !== undefined && read('prefs', null) === null) prefs[k] = f(k)
  }
  if (f('deviceId') && !read('deviceId', null)) write('deviceId', f('deviceId'))
  if (!read('profiles', null)) {
    let list = []
    try {
      list = JSON.parse(f('profiles') || '[]').map((p) => ({ id: p.id, name: p.name, token: p.token, ...(p.pin ? { pin: p.pin } : {}) }))
    } catch {}
    const uid = f('userId'), name = f('userName'), token = f('token')
    if (uid && name && token && !list.some((p) => p.id === uid)) list.push({ id: uid, name, token })
    if (list.length) write('profiles', list)
    if (uid && name && token) write('session', { userId: uid, userName: name, token })
  }
  write('imported', true)
}

function use(s) {
  session.value = s
  Object.assign(jf.auth, { userId: s?.userId || '', userName: s?.userName || '', token: s?.token || '' })
  write('session', s)
}

/** Load what this browser remembers and pick up where it was. */
export async function start() {
  importFlutter()
  Object.assign(prefs, read('prefs', {}))
  watch(prefs, () => write('prefs', { ...prefs }), { deep: true })
  let deviceId = read('deviceId', null)
  if (!deviceId) write('deviceId', (deviceId = newDeviceId()))
  jf.auth.deviceId = deviceId
  profiles.value = read('profiles', [])
  jf.onSignedOut.fn = () => signOutHere()
  const s = read('session', null)
  choosing.value = profiles.value.length > 1
  if (s) {
    use(s)
    refreshMyList()
    seerr.check()
  }
}

const saveProfiles = () => write('profiles', profiles.value)

export async function login(username, password) {
  const s = await jf.login(username.trim(), password)
  // A browser keeps one Seerr sign-in: the new account links its own.
  await seerr.logout()
  const i = profiles.value.findIndex((p) => p.id === s.userId)
  if (i >= 0) profiles.value[i] = { ...profiles.value[i], token: s.token }
  else profiles.value.push({ id: s.userId, name: s.userName, token: s.token })
  saveProfiles()
  use(s)
  adding.value = choosing.value = false
  myList.clear()
  refreshMyList()
  try {
    await seerr.login(s.userName, password)
  } catch {}
  bump()
}

export const currentProfile = () => profiles.value.find((p) => p.id === session.value?.userId) || null

export const hashPin = (userId, pin) => sha256(`hevyfin:${userId}:${pin}`)
export const pinMatches = (p, pin) => !p.pin || p.pin === hashPin(p.id, pin)

export function setPin(p, pin) {
  const i = profiles.value.findIndex((x) => x.id === p.id)
  if (i < 0) return
  const { pin: _, ...rest } = profiles.value[i]
  profiles.value[i] = pin ? { ...rest, pin: hashPin(p.id, pin) } : rest
  saveProfiles()
}

/** Become [p]: their Continue watching, My List, requests and settings on the server. */
export async function switchTo(p) {
  await seerr.logout()
  use({ userId: p.id, userName: p.name, token: p.token })
  choosing.value = false
  myList.clear()
  refreshMyList()
  bump()
}

/** Forget a profile on this browser (signs it out if it's the current one). */
export function removeProfile(p) {
  if (p.id === session.value?.userId) return logout()
  profiles.value = profiles.value.filter((x) => x.id !== p.id)
  saveProfiles()
}

/** The server no longer takes this sign-in: forget it here and ask again. */
function signOutHere() {
  const uid = session.value?.userId
  profiles.value = profiles.value.filter((p) => p.id !== uid)
  saveProfiles()
  use(null)
  choosing.value = profiles.value.length > 0
  myList.clear()
}

export async function logout() {
  await jf.logout()
  await seerr.logout()
  signOutHere()
}

export async function refreshMyList() {
  try {
    const items = await jf.items({ filters: 'IsFavorite', fields: 'Tags' })
    myList.clear()
    items.forEach((i) => myList.add(i.Id))
  } catch {}
}

export async function toggleMyList(id) {
  const add = !myList.has(id)
  add ? myList.add(id) : myList.delete(id)
  try {
    await jf.setFavorite(id, add)
    bump()
  } catch (e) {
    add ? myList.delete(id) : myList.add(id)
    throw e
  }
}

/** A short message at the bottom of the screen. */
export const toast = ref('')
let toastTimer
export function say(text) {
  toast.value = text
  clearTimeout(toastTimer)
  toastTimer = setTimeout(() => (toast.value = ''), 4000)
}
