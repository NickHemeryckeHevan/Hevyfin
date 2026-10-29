<script setup>
// HEVYFIN: heavy, italic, orange.
defineProps({ size: { type: Number, default: 26 } })
</script>

<template>
  <span class="wordmark" :style="{ fontSize: size + 'px' }">HEVYFIN</span>
</template>

<style scoped>
.wordmark { font-weight: 900; font-style: italic; letter-spacing: -.02em; line-height: 1; background: var(--grad); -webkit-background-clip: text;
  background-clip: text; color: transparent; user-select: none; }
</style>
