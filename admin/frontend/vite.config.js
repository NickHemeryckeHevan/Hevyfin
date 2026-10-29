import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  // `npm run dev` passes the API on to a local backend (flask --app hevyfin_admin.wsgi run).
  server: { port: 5198, proxy: { '/api': 'http://127.0.0.1:5000' } },
})
