/** Exercise the actual bundled Pages + SQLite Durable Object code locally, with fictional outbound sources. */
import { Miniflare } from 'miniflare'
import { execFileSync } from 'node:child_process'
import { mkdir } from 'node:fs/promises'
import { resolve } from 'node:path'
import assert from 'node:assert/strict'
import { demoData, demoSeats, FALL } from '../services/web-api/tests/source-data'
const out = resolve('.wrangler/test-build'); await mkdir(out, { recursive: true })
const env = { ...process.env, WRANGLER_SEND_METRICS: 'false', WRANGLER_LOG_PATH: '/private/tmp/bye-runtime-wrangler.log' }
execFileSync(process.execPath, ['node_modules/wrangler/bin/wrangler.js', 'deploy', '--config', 'services/source-worker/wrangler.jsonc', '--env', 'preview', '--dry-run', '--outdir', out + '/sources'], { env, stdio: 'pipe' })
execFileSync(process.execPath, ['node_modules/wrangler/bin/wrangler.js', 'deploy', '--config', 'services/web-api/wrangler.jsonc', '--dry-run', '--outdir', out + '/pages'], { env, stdio: 'pipe' })
let schedules = 0, rmpRequests = 0
const rows = demoData.schedules[FALL.termCode].map(row => { const seats = demoSeats[String(row.crn)]; return { ...row, ...(seats ? { seatsAvail: seats.open, maxEnrl: seats.capacity, waitCount: seats.waitlist, waitCapacity: seats.waitCapacity } : {}) } })
const mf = new Miniflare({
  workers: [
    { name: 'sources', modules: true, scriptPath: out + '/sources/index.js', compatibilityDate: '2025-10-11', durableObjects: { SOURCES: { className: 'Sources', useSQLite: true } }, bindings: { LIVE_APP_ENABLED: 'true', RMP_AUTHORIZED: 'true', RMP_PERMISSION_REF: 'fictional-local-runtime-only', RMP_CACHE_SECONDS: '60' },
      outboundService: async request => {
        const url = new URL(request.url)
        if (url.hostname === 'prod-apiweb.pasadena.edu') {
          if (url.pathname.endsWith('getClassScheduleTerms')) return Response.json(demoData.terms)
          schedules++; return Response.json(rows)
        }
        if (url.hostname !== 'www.ratemyprofessors.com') throw new Error('Unexpected outbound source')
        rmpRequests++
        const body = await request.json() as { query: string; variables: { id?: string; count: number; cursor?: string; courseFilter?: string; query?: { text: string } } }
        const node = (p: typeof demoData.profiles[number]) => ({ id: btoa('Teacher-' + p.id), legacyId: Number(p.id), firstName: p.firstName, lastName: p.lastName, school: { legacyId: 2649, name: 'Pasadena City College' }, department: p.department, avgRating: p.rating, avgDifficulty: p.difficulty, numRatings: p.ratingCount, wouldTakeAgainPercent: p.wouldTakeAgain, courseCodes: p.courseCounts.map(c => ({ courseName: c.label, courseCount: c.count })) })
        if (body.variables.query) return Response.json({ data: { search: { teachers: { edges: demoData.profiles.filter(p => (p.firstName + ' ' + p.lastName) === body.variables.query!.text).map(p => ({ node: node(p) })), pageInfo: { hasNextPage: false } } } } })
        const id = atob(body.variables.id!).slice('Teacher-'.length), p = demoData.profiles.find(p => p.id === id)!
        const list = p.reviews.filter(r => !body.variables.courseFilter || r.course === body.variables.courseFilter), offset = Number(body.variables.cursor ?? 0), records = list.slice(offset, offset + body.variables.count)
        return Response.json({ data: { node: { ...node(p), ratings: { edges: records.map(r => ({ node: { id: r.id, comment: r.text, class: r.course, date: r.date, helpfulRating: r.rating, difficultyRating: r.difficulty, isForOnlineClass: r.online } })), pageInfo: { hasNextPage: offset + records.length < list.length, endCursor: String(offset + records.length) } } } } })
      }
    },
    { name: 'sources-pcc', modules: true, scriptPath: out + '/sources/index.js', compatibilityDate: '2025-10-11', durableObjects: { SOURCES: { className: 'Sources', useSQLite: true } }, bindings: { LIVE_APP_ENABLED: 'true', RMP_AUTHORIZED: 'false', RMP_CACHE_SECONDS: '0' }, outboundService: request => {
      const url=new URL(request.url)
      if(url.hostname!=='prod-apiweb.pasadena.edu')throw new Error('PCC-only worker must not contact RMP')
      return Response.json(url.pathname.endsWith('getClassScheduleTerms')?demoData.terms:rows)
    } },
    { name: 'pages-pcc', modules: true, scriptPath: out + '/pages/index.js', compatibilityDate: '2025-10-11', durableObjects: { SOURCES: { className: 'Sources', scriptName: 'sources-pcc', useSQLite: true } }, bindings: { LIVE_APP_ENABLED: 'true' } },
    { name: 'disabled', modules: true, scriptPath: out + '/pages/index.js', compatibilityDate: '2025-10-11', durableObjects: { SOURCES: { className: 'Sources', scriptName: 'sources', useSQLite: true } }, bindings: { LIVE_APP_ENABLED: 'false' } },
    { name: 'pages', modules: true, scriptPath: out + '/pages/index.js', compatibilityDate: '2025-10-11', durableObjects: { SOURCES: { className: 'Sources', scriptName: 'sources', useSQLite: true } }, bindings: { LIVE_APP_ENABLED: 'true' } }
  ]
})
try {
  const pages = await mf.getWorker('pages')
  const disabled = await mf.getWorker('disabled')
  assert.equal((await disabled.fetch('https://fixture.local/api/v1/terms')).status, 503)
  assert.equal((await (await disabled.fetch('https://fixture.local/api/v1/status')).json() as any).enabled, false)
  assert.equal(schedules, 0); assert.equal(rmpRequests, 0)
  const request = (path: string, init?: RequestInit) => pages.fetch('https://fixture.local/api/v1/' + path, init)
  const status = await (await request('status')).json() as { enabled: boolean; rmpConfigured: boolean }; assert.equal(status.enabled, true); assert.equal(status.rmpConfigured, true)
  const params = new URLSearchParams({ term: FALL.termCode, query: 'MATH5A' })
  const results = await Promise.all(Array.from({ length: 10 }, () => request('sections?' + params)))
  assert.ok(results.every(r => r.status === 200)); assert.equal(schedules, 1)
  const result = await results[0].json() as any
  assert.equal(result.data.course.display, 'MATH 5A'); assert.ok(result.data.professors.some((p: any) => p.sections.some((s: any) => s.details.seatsOpen !== undefined)))
  const identity = new URLSearchParams({ term: FALL.termCode, course: 'MATH5A', instructor: 'Lena Whitcombe' })
  const candidates = await (await request('candidates?' + identity)).json() as any
  assert.equal(candidates.data.length, 1)
  identity.set('id', candidates.data[0].id)
  const profile = await (await request('profile?' + identity)).json() as any
  assert.equal(profile.data.profile.firstName, 'Lena'); assert.ok(profile.data.profile.reviews.length)
  const before = rmpRequests
  await request('profile?' + identity); assert.equal(rmpRequests, before, 'Profile served from SQLite evidence cache')
  identity.set('id', demoData.profiles.find(p => p.firstName !== 'Lena')!.id)
  assert.equal((await request('profile?' + identity)).status, 409)
  assert.equal((await request('terms', { method: 'POST' })).status, 405)
  assert.equal((await request('arbitrary-proxy')).status, 404)
  const pccOnly=await mf.getWorker('pages-pcc')
  assert.equal((await(await pccOnly.fetch('https://fixture.local/api/v1/status')).json() as any).rmpConfigured,false)
  assert.equal((await pccOnly.fetch('https://fixture.local/api/v1/sections?'+params)).status,200)
  const beforeDisabled=rmpRequests
  assert.equal((await pccOnly.fetch('https://fixture.local/api/v1/candidates?'+identity)).status,503)
  assert.equal(rmpRequests,beforeDisabled)
  console.log('Local workerd: Pages routing, SQLite cache, ten shared searches, fixed-source retrieval, identity checks and method limits passed. No real source requests.')
} finally { await mf.dispose() }
