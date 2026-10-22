// Read-only public-source probe. Prints metadata and aggregate counts, not instructor data.
import { performance } from 'node:perf_hooks'
async function probe(path) {
  const started = performance.now()
  const response = await fetch('https://prod-apiweb.pasadena.edu/api/' + path, { signal: AbortSignal.timeout(35_000), redirect: 'error' })
  if (!response.ok) throw new Error(`PCC HTTP ${response.status}`)
  const body = await response.text(), parsing = performance.now(), data = JSON.parse(body), parsed = performance.now()
  if (!Array.isArray(data)) throw new Error('Unexpected PCC response')
  return { data, result: { path, bytes: Buffer.byteLength(body), rows: data.length, totalMs: Math.round(parsed - started), parseMs: +(parsed - parsing).toFixed(2) } }
}
const terms = await probe('getClassScheduleTerms')
const term = process.argv[2] ?? terms.data.find(t => t.termDisplayControl === 'Y')?.termCode
if (!/^\d{6}$/.test(term)) throw new Error('No valid published semester')
const schedule = await probe('classSchedule/' + term)
const fields = ['seatsAvail', 'maxEnrl', 'waitCount', 'waitCapacity', 'ptrmDesc', 'campDesc', 'creditHrLow']
console.log(JSON.stringify({ observedAt: new Date().toISOString(), runtime: 'local-node-not-cloudflare', terms: terms.result, schedule: schedule.result, enrollmentFields: Object.fromEntries(fields.map(key => [key, schedule.data.filter(row => row[key] !== null && row[key] !== undefined).length])) }, null, 2))
