<script setup>
// Line icons (24px grid, drawn in the text colour); "fill" ones are solid shapes.
defineProps({ name: String, size: { type: Number, default: 20 } })
const PATHS = {
  home: 'M3 11l9-7 9 7v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z',
  search: 'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14z M20 20l-4-4',
  sparkle: 'M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z M19 16l.8 2.2L22 19l-2.2.8L19 22l-.8-2.2L16 19l2.2-.8z',
  back: 'M19 12H5 M11 6l-6 6 6 6',
  close: 'M6 6l12 12 M18 6L6 18',
  check: 'M5 12.5l4.5 4.5L19 7',
  plus: 'M12 5v14 M5 12h14',
  left: 'M15 5l-7 7 7 7',
  right: 'M9 5l7 7-7 7',
  down: 'M6 9l6 6 6-6',
  more: 'M12 6.5a.5.5 0 1 0 0-.01 M12 12a.5.5 0 1 0 0-.01 M12 17.5a.5.5 0 1 0 0-.01',
  info: 'M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18z M12 11v5 M12 7.5v.01',
  settings: 'M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6z M19.4 13.5a7.6 7.6 0 0 0 0-3l2-1.5-2-3.5-2.4 1a7.4 7.4 0 0 0-2.6-1.5L14 2.5h-4l-.4 2.5A7.4 7.4 0 0 0 7 6.5l-2.4-1-2 3.5 2 1.5a7.6 7.6 0 0 0 0 3l-2 1.5 2 3.5 2.4-1a7.4 7.4 0 0 0 2.6 1.5l.4 2.5h4l.4-2.5a7.4 7.4 0 0 0 2.6-1.5l2.4 1 2-3.5z',
  profiles: 'M9 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M3 20c.6-3.3 3-5 6-5s5.4 1.7 6 5 M16.5 10.5a2.5 2.5 0 1 0 0-5 M18 14.5c1.7.6 2.8 2.4 3 5.5',
  inbox: 'M4 13l2.5-8h11L20 13v6H4z M4 13h5l1 2h4l1-2h5',
  logout: 'M15 4h3a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1h-3 M10 8l-4 4 4 4 M6 12h10',
  bookmark: 'M7 4h10v16l-5-4-5 4z',
  lock: 'M6 11h12v9H6z M9 11V8a3 3 0 0 1 6 0v3',
  star: 'M12 4l2.4 5 5.6.6-4.2 3.8 1.2 5.6L12 16.2 7 19l1.2-5.6L4 9.6 9.6 9z',
  film: 'M4 5h16v14H4z M8 5v14 M16 5v14 M4 9h4 M4 15h4 M16 9h4 M16 15h4',
  tv: 'M3 6h18v12H3z M8 21h8 M12 18v3',
  trailer: 'M4 5h16v14H4z M10 9l5 3-5 3z',
  // the player
  play: 'M7 4.5v15l12.5-7.5z',
  pause: 'M7 4.5h3.5v15H7z M13.5 4.5H17v15h-3.5z',
  back10: 'M4 12a8 8 0 1 0 2.4-5.7 M4 4v4h4 M9.5 10v5 M12.5 10h2.5v5h-2.5z',
  fwd10: 'M20 12a8 8 0 1 1-2.4-5.7 M20 4v4h-4 M9.5 10v5 M12.5 10h2.5v5h-2.5z',
  volume: 'M4 9.5h3.5L12 6v12l-4.5-3.5H4z M15.5 9a4 4 0 0 1 0 6 M18 6.5a7.5 7.5 0 0 1 0 11',
  mute: 'M4 9.5h3.5L12 6v12l-4.5-3.5H4z M16 10l4 4 M20 10l-4 4',
  full: 'M4 9V4h5 M15 4h5v5 M20 15v5h-5 M9 20H4v-5',
  unfull: 'M9 4v5H4 M20 9h-5V4 M15 20v-5h5 M4 15h5v5',
  subs: 'M3 5h18v14H3z M7 13h4 M13 13h4 M7 16h10',
  episodes: 'M4 6h16 M4 12h16 M4 18h10',
  next: 'M5 5l10 7-10 7z M18 5v14',
  pip: 'M3 5h18v14H3z M12 12h7v5h-7z',
  camera: 'M4 8h4l2-3h4l2 3h4v11H4z M12 10a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7z',
  link: 'M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1 M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1',
  moon: 'M20 14.5A8.5 8.5 0 1 1 9.5 4a7 7 0 0 0 10.5 10.5z',
}
const FILLED = new Set(['play', 'pause', 'next'])
</script>

<template>
  <svg :width="size" :height="size" viewBox="0 0 24 24" :fill="FILLED.has(name) ? 'currentColor' : 'none'" stroke="currentColor" stroke-width="1.8"
       stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" class="icon"><path :d="PATHS[name]" /></svg>
</template>
