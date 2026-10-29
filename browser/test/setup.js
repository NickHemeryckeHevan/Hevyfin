// The app reads the page's address and storage; tests get small stand-ins.
globalThis.location = { origin: 'http://hevyfin.test' }
const store = new Map()
globalThis.localStorage = {
  getItem: (k) => (store.has(k) ? store.get(k) : null),
  setItem: (k, v) => store.set(k, String(v)),
  removeItem: (k) => store.delete(k),
  clear: () => store.clear(),
}
