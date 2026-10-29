import { createApp } from 'vue'
import '@fontsource/inter-tight/400.css'
import '@fontsource/inter-tight/600.css'
import '@fontsource/inter-tight/800.css'
import '@fontsource/inter-tight/900-italic.css'
import './style.css'
import App from './App.vue'
import { router } from './router.js'
import { start } from './state/session.js'

start()
createApp(App).use(router).mount('#app')
