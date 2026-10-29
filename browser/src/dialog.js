// The app's own small dialogs instead of the browser's prompt() and confirm():
//   if (await ask({ title: 'Delete?', ok: 'Delete', danger: true })) …
//   const name = await ask({ title: 'Rename', value: 'Old name' })   // null when cancelled
import { ref } from 'vue'

export const dialog = ref(null)

export function ask({ title, text = '', value = null, ok = 'OK', danger = false }) {
  return new Promise((resolve) => {
    dialog.value = { title, text, value, ok, danger, resolve }
  })
}
