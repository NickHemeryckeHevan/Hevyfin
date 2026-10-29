<script setup>
// Match, year, age rating, length or seasons, quality, and when it would end if started now.
import { computed } from 'vue'
import { duration, isCollection, isSeries, played, quality, resumeAt, runtime } from '../lib/item.js'

const props = defineProps({ item: Object })
const match = computed(() => (props.item.CommunityRating > 0 ? `${Math.min(99, Math.max(1, Math.round(props.item.CommunityRating * 10)))}% match` : null))
const length = computed(() => {
  const i = props.item, mini = i.PathStop?.mini ? i.PathStop : null
  if (mini) {
    const total = mini.parts.reduce((s, p) => s + (runtime(p) || 0), 0)
    return `${mini.parts.length} Episode${mini.parts.length === 1 ? '' : 's'} · ${duration(total)}`
  }
  if (isSeries(i)) return i.ChildCount ? `${i.ChildCount} Season${i.ChildCount === 1 ? '' : 's'}` : ''
  return duration(runtime(i))
})
const ends = computed(() => {
  const i = props.item, r = runtime(i)
  if (!r || isSeries(i) || isCollection(i) || played(i)) return null
  const at = resumeAt(i)
  const t = new Date(Date.now() + (at > 0 && at < r ? r - at : r) * 1000)
  return `Ends at ${String(t.getHours()).padStart(2, '0')}:${String(t.getMinutes()).padStart(2, '0')}`
})
</script>

<template>
  <div class="meta">
    <span v-if="match" class="match">{{ match }}</span>
    <span v-if="item.ProductionYear">{{ item.ProductionYear }}</span>
    <span v-if="item.OfficialRating" class="tag">{{ item.OfficialRating }}</span>
    <span v-if="length">{{ length }}</span>
    <span v-if="quality(item)" class="tag">{{ quality(item) }}</span>
    <span v-if="ends">{{ ends }}</span>
  </div>
</template>

<style scoped>
.meta { display: flex; flex-wrap: wrap; gap: 6px 12px; align-items: center; color: var(--dim); font-weight: 600; }
.match { color: var(--orange); font-weight: 800; }
.tag { border: 1px solid rgba(255, 255, 255, .45); border-radius: 3px; padding: 0 6px; font-size: 12px; line-height: 20px; }
</style>
