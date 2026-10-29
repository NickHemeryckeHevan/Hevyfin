<script setup>
// A titled row that loads itself once it's near the screen (rows far down cost nothing until
// scrolled to), shows its last contents at once when it has them, and hides when it's empty.
import { onBeforeUnmount, onMounted, ref } from 'vue'
import Icon from './Icon.vue'
import { cached, keep } from '../state/rows.js'

const props = defineProps({
  title: String,
  subtitle: String,
  load: Function,
  cacheKey: String, // remembered between visits under this name
  more: String, // "Explore all" link
  minItems: { type: Number, default: 1 },
  shape: { type: String, default: 'poster' }, // poster | wide | top10, for the placeholder
})
const items = ref(props.cacheKey ? cached(props.cacheKey) : null)
const failed = ref(false)
const root = ref(null)
const strip = ref(null)
let seen

async function fill() {
  try {
    const got = await props.load()
    if (props.cacheKey) keep(props.cacheKey, got)
    items.value = got
  } catch {
    failed.value = true
  }
}

onMounted(() => {
  if (!root.value) return fill()
  seen = new IntersectionObserver((e) => {
    if (!e[0].isIntersecting) return
    seen.disconnect()
    fill()
  }, { rootMargin: '600px 0px' })
  seen.observe(root.value)
})
onBeforeUnmount(() => seen?.disconnect())

/** Arrows page the row by most of its width. */
const page = (dir) => strip.value.scrollBy({ left: dir * strip.value.clientWidth * 0.85, behavior: 'smooth' })
</script>

<template>
  <section ref="root" class="row" v-if="!failed && (items === null || items.length >= minItems)">
    <div class="row-head">
      <h2><span v-if="subtitle" class="sub">{{ subtitle }} </span>{{ title }}</h2>
      <router-link v-if="more && items" :to="more">Explore all ›</router-link>
    </div>
    <div class="row-wrap">
      <button v-if="items" class="arrow l" aria-label="Back" @click="page(-1)"><Icon name="left" :size="30" /></button>
      <div ref="strip" class="strip">
        <template v-if="items">
          <template v-for="(item, index) in items" :key="item.Id || item.id || index"><slot :item="item" :index="index" /></template>
        </template>
        <div v-else v-for="n in 7" :key="n" class="skeleton" :class="shape" />
      </div>
      <button v-if="items" class="arrow r" aria-label="More" @click="page(1)"><Icon name="right" :size="30" /></button>
    </div>
  </section>
</template>

<style scoped>
.sub { color: var(--dim); font-weight: 500; }
.skeleton.poster { width: 170px; aspect-ratio: 2 / 3; }
.skeleton.wide { width: 300px; aspect-ratio: 16 / 9; }
.skeleton.top10 { width: 230px; height: 210px; }
</style>
