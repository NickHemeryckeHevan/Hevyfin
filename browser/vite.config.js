import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// Served at /next/ next to the Flutter build, or from / (HEVYFIN_BASE=/).
// `npm run dev` passes /jellyfin, /seerr and /niql on like server/web/nginx.conf does:
//   JELLYFIN_URL=http://jellyfin.local:8096 SEERR_URL=http://jellyfin.local:5055 npm run dev
// (Remote control and watch together need nginx's socket header and don't work in dev.)
const jellyfin = process.env.JELLYFIN_URL || 'http://localhost:8096'
const seerr = process.env.SEERR_URL || 'http://localhost:5055'
const niql = process.env.NIQL_URL || 'http://localhost:8050'
const strip = (prefix) => (p) => p.replace(new RegExp(`^${prefix}`), '')
export default defineConfig({
  base: process.env.HEVYFIN_BASE || '/next/',
  plugins: [vue()],
  build: { target: ['firefox128', 'chrome120'], cssCodeSplit: true },
  server: {
    port: 5199,
    proxy: {
      '/jellyfin': { target: jellyfin, changeOrigin: true, ws: true, rewrite: strip('/jellyfin') },
      '/seerr': { target: seerr, changeOrigin: true, rewrite: strip('/seerr') },
      '/niql': { target: niql, changeOrigin: true, rewrite: strip('/niql') },
    },
  },
  test: { environment: 'node', setupFiles: ['test/setup.js'] },
})
