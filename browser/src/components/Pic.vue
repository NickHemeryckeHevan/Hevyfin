<script setup>
// A picture that fades in over its BlurHash (or a plain tile with the title when there's none).
import { computed, ref, watch } from 'vue'
import { blurUrl } from '../lib/images.js'

const props = defineProps({ src: String, srcset: String, hash: String, alt: { type: String, default: '' }, fallback: String, eager: Boolean })
const ready = ref(false)
const failed = ref(false)
watch(() => props.src, () => ((ready.value = false), (failed.value = false)))
const blur = computed(() => (props.hash ? `url(${blurUrl(props.hash)})` : null))
</script>

<template>
  <div class="pic" :style="blur && !ready ? { backgroundImage: blur } : null">
    <img v-if="src && !failed" :src="src" :srcset="srcset" :alt="alt" :class="{ ready }" :loading="eager ? 'eager' : 'lazy'" decoding="async"
         @load="ready = true" @error="failed = true" />
    <div v-if="(!src || failed) && fallback" class="fallback">{{ fallback }}</div>
    <slot />
  </div>
</template>
