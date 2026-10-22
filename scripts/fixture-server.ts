/** Loopback-only fictional API. No environment files, source services, email or database access. */
import { createServer } from 'node:http'
import { Worker, isMainThread, parentPort } from 'node:worker_threads'
import { resolve } from 'node:path'
import { handleReviewRequest } from '../services/web-api/src/reviews'
import { errorResponse } from '../services/web-api/src/service'
import { setup } from '../services/web-api/tests/fixtures'
import { reviewFixture } from '../services/web-api/tests/review-fixtures'
let source = setup(), auth = reviewFixture()
let options = { enabled: true, rmpEnabled: true, combined: false, byeFails: false }, reportWrites = 0
const reviews = Array.from({ length: 25 }, (_, i) => ({ id: `11111111-1111-4111-8111-${String(i).padStart(12, '0')}`, quality: 4, difficulty: 2, body: i === 0 ? '<img src=x onerror=alert(1)>' : 'Fictional BYE comment ' + i, created_at: '2026-10-16T00:00:00Z', course_id: 2, courses: { code: 'MATH 005A', title: 'CALCULUS' } }))
const outbound: typeof fetch = async (input, init) => {
  if (!options.combined) return auth.outbound(input, init)
  const request = typeof input === 'string' || input instanceof URL ? undefined : input
  const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url)
  const method = init?.method ?? request?.method ?? 'GET', path = url.pathname.split('/').at(-1)
  if (options.byeFails && ['reviews', 'professors'].includes(path ?? '')) return Response.json({ code: 'XX000' }, { status: 503 })
  if (path === 'professors') { const row = { id: 1, first_name: 'Lena', last_name: 'Whitcombe' }; return Response.json(url.searchParams.has('id') ? row : [row]) }
  if (path === 'courses') { const row = { id: 2, code: 'MATH 005A', title: 'CALCULUS' }; return Response.json(url.searchParams.has('id') ? row : [row]) }
  if (path === 'reviews') {
    if (url.searchParams.get('select') === 'id') return Response.json({ id: reviews[0].id })
    const offset = Number(url.searchParams.get('offset') ?? 0), limit = Number(url.searchParams.get('limit') ?? 1000)
    return Response.json(reviews.slice(offset, offset + limit))
  }
  if (path === 'reports' && method === 'POST') { reportWrites++; return new Response(null, { status: 201 }) }
  return auth.outbound(input, init)
}
const server = createServer(async (req, res) => {
  try {
    // Reject LAN/DNS rebinding and cross-origin access to the test control surface.
    const host = req.headers.host ?? ''
    if (host !== '127.0.0.1:' + (server.address() as { port: number }).port) { res.writeHead(403); res.end(); return }
    const url = new URL(req.url ?? '/', 'http://' + host)
    const chunks: Buffer[] = []; let size = 0
    for await (const part of req) { size += part.length; if (size > 20_000) { res.writeHead(413); res.end(); return }; chunks.push(Buffer.from(part)) }
    if (url.pathname.startsWith('/__fixture/')) {
      if (req.headers.origin || req.headers['x-bye-fixture-control'] !== 'local-test') { res.writeHead(403); res.end(); return }
      if (req.method === 'POST') {
        const data = JSON.parse(Buffer.concat(chunks).toString() || '{}')
        if (url.pathname === '/__fixture/reset') { source = setup(); auth = reviewFixture(); options = { enabled: true, rmpEnabled: true, combined: false, byeFails: false }; reportWrites = 0 }
        for (const key of Object.keys(options) as (keyof typeof options)[]) if (typeof data[key] === 'boolean') options[key] = data[key]
        for (const key of ['authExpired', 'unconfirmed', 'nonPcc', 'emailRateLimited', 'saveFails', 'duplicate', 'catalogFails'] as const) if (typeof data[key] === 'boolean') auth.state[key] = data[key]
        if (['students', 'tester'].includes(data.reviewAccess)) auth.env.REVIEW_ACCESS = data.reviewAccess
        if (typeof data.reviewsEnabled === 'boolean') auth.env.REVIEWS_ENABLED = String(data.reviewsEnabled)
      }
      // Fictional state only; omit bearer tokens and Authorization headers even here.
      const state = { ...auth.state, calls: auth.state.calls.map(({ method, url }) => ({ method, url })), reportWrites, sourceCounts: source.counts() }
      res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify(state)); return
    }
    // This header exists only on this loopback fixture server, never in the deployed Worker.
    const original = new URL(String(req.headers['x-bye-fixture-url'] ?? url))
    if (!((['127.0.0.1', 'localhost'].includes(original.hostname) && original.protocol === 'http:') || original.origin === 'https://fixture.local')) { res.writeHead(403); res.end(); return }
    const headers = new Headers()
    for (const [name, value] of Object.entries(req.headers)) if (typeof value === 'string' && name !== 'x-bye-fixture-url') headers.set(name, value)
    const request = new Request(original, { method: req.method, headers, ...(!['GET', 'HEAD'].includes(req.method ?? 'GET') ? { body: Buffer.concat(chunks) } : {}) })
    let response: Response
    if (url.pathname.startsWith('/api/reviews/')) response = await handleReviewRequest(request, auth.env, outbound)
    else if (url.pathname.startsWith('/api/v1/')) {
      const kind = url.pathname.split('/').at(-1)!
      if (kind === 'status') response = Response.json({ enabled: options.enabled, rmpConfigured: options.enabled && options.rmpEnabled })
      else if (!options.enabled) response = Response.json({ error: { code: 'LIVE_DISABLED', message: 'The live beta is not available yet. You can use the sample demo.', retryable: true } }, { status: 503 })
      else { try { response = Response.json(await source.service.operation(kind as any, url.searchParams, headers.get('CF-Connecting-IP') ?? 'fixture-browser')) } catch (error) { response = errorResponse(error) } }
    } else response = new Response('Not found', { status: 404 })
    res.writeHead(response.status, Object.fromEntries(response.headers)); res.end(await response.arrayBuffer().then(b => Buffer.from(b)))
  } catch { res.writeHead(500, { 'Cache-Control': 'no-store' }); res.end('Fixture request failed') }
})
if (!isMainThread) {
  server.listen(0, '127.0.0.1', () => parentPort!.postMessage((server.address() as { port: number }).port))
} else {
  // A fresh test isolate per reset preserves production limiter logic without exposing a reset API there.
  let worker: Worker
  const spawn = () => new Promise<number>((resolvePort, reject) => {
    worker = new Worker("require('tsx/cjs'); require(require('node:worker_threads').workerData)", { eval: true, workerData: resolve('scripts/fixture-server.ts') })
    worker.once('message', resolvePort); worker.once('error', reject)
  })
  let ready = spawn()
  const gateway = createServer(async (req, res) => {
    try {
      if (req.headers.host !== '127.0.0.1:8788') { res.writeHead(403); res.end(); return }
      if (req.url === '/__fixture/reset' && req.method === 'POST') {
        if (req.headers.origin || req.headers['x-bye-fixture-control'] !== 'local-test') { res.writeHead(403); res.end(); return }
        await ready; await worker.terminate(); ready = spawn()
      }
      const port = await ready, parts: Buffer[] = []; let bytes = 0
      for await (const part of req) { bytes += part.length; if (bytes > 20_000) { res.writeHead(413); res.end(); return }; parts.push(Buffer.from(part)) }
      const headers = new Headers(); for (const [name, value] of Object.entries(req.headers)) if (typeof value === 'string') headers.set(name, value)
      const response = await fetch('http://127.0.0.1:' + port + req.url, { method: req.method, headers, ...(!['GET','HEAD'].includes(req.method ?? 'GET') ? { body: Buffer.concat(parts) } : {}), redirect: 'manual' })
      res.writeHead(response.status, Object.fromEntries(response.headers)); res.end(Buffer.from(await response.arrayBuffer()))
    } catch { res.writeHead(503); res.end('Fixture isolate unavailable') }
  })
  gateway.listen(8788, '127.0.0.1', () => console.log('Fictional backend API at http://127.0.0.1:8788; fresh test isolates, no real outbound access.'))
  for (const signal of ['SIGINT','SIGTERM'] as const) process.on(signal, () => { void worker.terminate(); gateway.close(() => process.exit(0)) })
}
