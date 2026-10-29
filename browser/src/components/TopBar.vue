<script setup>
// The bar over every page: home, the five places, search, "What tonight?" and the profile.
// Clear over a page's picture, frosted once the page scrolls under it.
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import Icon from './Icon.vue'
import Wordmark from './Wordmark.vue'
import { choosing, logout, session } from '../state/session.js'

const TABS = [
  ['Home', '/'],
  ['Shows', '/shows'],
  ['Movies', '/movies'],
  ['New & Popular', '/new'],
  ['My List', '/my-list'],
]
const route = useRoute()
const router = useRouter()
const solid = ref(false)
const menu = ref(false)
const onScroll = () => (solid.value = scrollY > 10)
const close = () => (menu.value = false)
onMounted(() => {
  addEventListener('scroll', onScroll, { passive: true })
  addEventListener('click', close)
  onScroll()
})
onBeforeUnmount(() => {
  removeEventListener('scroll', onScroll)
  removeEventListener('click', close)
})

function pick(what) {
  menu.value = false
  if (what === 'profiles') choosing.value = true
  if (what === 'requests') router.push('/new?tab=requests')
  if (what === 'settings') router.push('/settings')
  if (what === 'logout') logout()
}
</script>

<template>
  <header class="topbar" :class="{ solid }">
    <router-link to="/" class="home" aria-label="Home"><Wordmark :size="26" /></router-link>
    <nav class="tabs">
      <router-link v-for="([label, to], i) in TABS" :key="to" :to="to" :class="{ on: route.meta.tab === i }">{{ label }}</router-link>
    </nav>
    <div class="right">
      <router-link to="/search" class="icon-btn" title="Search (/)" aria-label="Search"><Icon name="search" :size="23" /></router-link>
      <router-link to="/tonight" class="icon-btn" title="What should I watch tonight?" aria-label="What tonight?"><Icon name="sparkle" :size="22" /></router-link>
      <div class="profile" @click.stop>
        <button class="avatar" :aria-expanded="menu" :title="session.userName" @click="menu = !menu">{{ (session.userName || '?')[0].toUpperCase() }}</button>
        <div v-if="menu" class="menu">
          <div class="head">{{ session.userName }}</div>
          <button @click="pick('profiles')"><Icon name="profiles" /> Switch profile</button>
          <button @click="pick('requests')"><Icon name="inbox" /> My requests</button>
          <button @click="pick('settings')"><Icon name="settings" /> Settings</button>
          <hr />
          <button @click="pick('logout')"><Icon name="logout" /> Sign out</button>
        </div>
      </div>
    </div>
  </header>
</template>

<style scoped>
.topbar { position: fixed; inset: 0 0 auto; height: var(--bar); z-index: 40; display: flex; align-items: center; gap: 36px; padding: 0 var(--pad);
  background: linear-gradient(rgba(0, 0, 0, .75), transparent); transition: background .3s; }
.topbar.solid { background: rgba(14, 14, 14, .82); backdrop-filter: blur(20px); }
.tabs { display: flex; gap: 4px; flex: 1; min-width: 0; overflow: hidden; }
.tabs a { position: relative; padding: 8px 12px; font-size: 14.5px; font-weight: 500; color: var(--dim); white-space: nowrap; transition: color .2s; }
.tabs a:hover { color: #ddd; }
.tabs a.on { color: #fff; font-weight: 800; }
.tabs a.on::after { content: ''; position: absolute; left: 50%; bottom: 0; width: 22px; height: 2.5px; margin-left: -11px; border-radius: 2px; background: var(--orange); }
.right { display: flex; align-items: center; gap: 4px; }
.profile { position: relative; margin-left: 6px; }
.avatar { width: 34px; height: 34px; border: 0; border-radius: 4px; background: var(--grad); color: #000; font-weight: 900; font-size: 17px; cursor: pointer; }
@media (max-width: 760px) { .tabs a:nth-child(n + 4) { display: none; } .topbar { gap: 16px; } }
</style>
