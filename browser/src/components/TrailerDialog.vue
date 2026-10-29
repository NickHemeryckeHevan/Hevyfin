<script setup>
// A YouTube trailer over the page (privacy-enhanced embed); Esc or a click outside closes it.
import { onBeforeUnmount, onMounted } from 'vue'
const props = defineProps({ url: String })
const emit = defineEmits(['close'])
const id = (props.url.match(/(?:v=|youtu\.be\/|embed\/)([\w-]{11})/) || [])[1]
const key = (e) => e.key === 'Escape' && emit('close')
onMounted(() => addEventListener('keydown', key))
onBeforeUnmount(() => removeEventListener('keydown', key))
</script>

<template>
  <div class="scrim" @click.self="emit('close')">
    <div class="frame">
      <iframe v-if="id" :src="`https://www.youtube-nocookie.com/embed/${id}?autoplay=1&rel=0`" title="Trailer" allow="autoplay; encrypted-media; picture-in-picture; fullscreen"
              allowfullscreen />
    </div>
  </div>
</template>

<style scoped>
.frame { width: min(1100px, 92vw); aspect-ratio: 16 / 9; background: #000; border-radius: 8px; overflow: hidden; box-shadow: 0 20px 80px #000; }
iframe { width: 100%; height: 100%; border: 0; }
</style>
