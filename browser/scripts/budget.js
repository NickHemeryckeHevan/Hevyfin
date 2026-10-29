// Fails the build when the first page or the player grows past its budget (gzip sizes):
// the browser version has to stay quick to open on a slow connection.
import { readFileSync, readdirSync } from 'node:fs'
import { gzipSync } from 'node:zlib'

const dir = new URL('../dist/assets/', import.meta.url)
const html = readFileSync(new URL('../dist/index.html', import.meta.url), 'utf8')
const gz = (f) => gzipSync(readFileSync(new URL(f, dir))).length
const files = readdirSync(dir)
// What index.html loads straight away: its entry script and the ones it preloads.
const first = [...html.matchAll(/assets\/([^"']+\.js)/g)].map((m) => m[1])
const firstKb = first.reduce((s, f) => s + gz(f), 0) / 1024
const player = files.filter((f) => f.startsWith('Player-') && f.endsWith('.js'))
const hls = files.filter((f) => f.startsWith('hls') && f.endsWith('.js'))
const playerKb = [...player, ...hls].reduce((s, f) => s + gz(f), 0) / 1024
const total = files.filter((f) => f.endsWith('.js')).reduce((s, f) => s + gz(f), 0) / 1024
console.log(`first page ${firstKb.toFixed(1)} KB, player ${playerKb.toFixed(1)} KB, all scripts ${total.toFixed(1)} KB (gzip)`)
let bad = false
if (firstKb > 120) (bad = true), console.error(`The first page is over its 120 KB budget`)
if (playerKb > 200) (bad = true), console.error(`The player is over its 200 KB budget`)
process.exit(bad ? 1 : 0)
