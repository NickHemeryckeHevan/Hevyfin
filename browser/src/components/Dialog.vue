<script setup>
// Shows what ask() (dialog.js) asked: a question with OK/Cancel, or a name to type.
import { nextTick, ref, watch } from 'vue'
import { dialog } from '../dialog.js'

const input = ref(null)
watch(dialog, async (d) => {
  if (d?.value === null) return
  await nextTick()
  input.value?.select()
})
function done(ok) {
  const d = dialog.value
  dialog.value = null
  if (d.value === null) d.resolve(ok)
  else d.resolve(ok && d.value.trim() ? d.value.trim() : null)
}
</script>

<template>
  <div v-if="dialog" class="scrim" @click.self="done(false)" @keydown.esc="done(false)">
    <form class="dialog" @submit.prevent="done(true)">
      <h3>{{ dialog.title }}</h3>
      <p v-if="dialog.text" class="dim">{{ dialog.text }}</p>
      <input v-if="dialog.value !== null" ref="input" v-model="dialog.value" autofocus />
      <div class="actions">
        <button type="button" class="btn ghost" @click="done(false)">Cancel</button>
        <button class="btn" :class="{ danger: dialog.danger }" autofocus>{{ dialog.ok }}</button>
      </div>
    </form>
  </div>
</template>
