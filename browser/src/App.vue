<script setup>
// Signed out: the sign-in (or "Who's watching?"). Signed in: the top bar over the page; the
// player has the screen to itself.
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import TopBar from './components/TopBar.vue'
import Dialog from './components/Dialog.vue'
import Login from './views/Login.vue'
import Profiles from './views/Profiles.vue'
import { adding, choosing, profiles, revision, session, toast } from './state/session.js'

const route = useRoute()
const router = useRouter()

// "/" searches from anywhere (except while typing, or in the player).
addEventListener('keydown', (e) => {
  if (e.key !== '/' || e.ctrlKey || e.metaKey || e.altKey || route.meta.bare || e.target.closest?.('input, select, textarea')) return
  e.preventDefault()
  router.push('/search')
})

const gate = computed(() => {
  if (adding.value || (!session.value && !profiles.value.length)) return 'login'
  if (choosing.value || !session.value) return 'profiles'
  return null
})
</script>

<template>
  <Login v-if="gate === 'login'" />
  <Profiles v-else-if="gate === 'profiles'" />
  <template v-else>
    <TopBar v-if="!route.meta.bare" />
    <!-- A new profile or a change in what's watched: the pages load again. -->
    <router-view :key="`${revision}|${session.userId}|${route.fullPath.split('#')[0]}`" />
  </template>
  <Dialog />
  <div v-if="toast" class="toast" role="status">{{ toast }}</div>
</template>
