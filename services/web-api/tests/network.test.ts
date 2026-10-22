import { test } from 'node:test'
import assert from 'node:assert/strict'
import { setTimeout as delay } from 'node:timers/promises'
import { PCC, RMP, Transport, numericID, profileFrom, retryAfter, jsonResponse } from '../src/network'
const signal = () => new AbortController().signal
const response = (data: unknown, status = 200, headers = {}) => new Response(JSON.stringify(data), { status, headers })
const teacher = { id: Buffer.from('Teacher-1').toString('base64'), legacyId: 1, firstName: 'John', lastName: 'Harris', school: { legacyId: 2649, name: 'Pasadena City College' }, avgRating: 4, ratings: { edges: [], pageInfo: { hasNextPage: false } } }
test('IDs validate global/legacy agreement; missing scores remain missing', () => {
  assert.equal(numericID(teacher.id, 1, 'Teacher'), '1')
  assert.throws(() => numericID(teacher.id, 2, 'Teacher'))
  assert.throws(() => numericID(Buffer.from('School-1').toString('base64'), 1, 'Teacher'))
  assert.throws(() => numericID(null, -1, 'Teacher'))
  assert.equal(profileFrom({ ...teacher, avgRating: 8 }).rating, undefined)
})
test('transport has shared concurrency two, no redirects/cookies, and progressive cancellation', async () => {
  let active = 0, peak = 0, started = 0
  const transport = new Transport(async (_url, init) => {
    assert.equal(init?.redirect, 'manual'); assert.equal(init?.credentials, 'omit'); assert.equal(init?.cache, 'no-store')
    active++; started++; peak = Math.max(peak, active); await delay(15, undefined, { signal: init?.signal ?? undefined }); active--
    return response({ data: { ok: true } })
  }, 0, 0)
  await Promise.all(Array.from({ length: 6 }, () => transport.send('query', {}, signal())))
  assert.equal(peak, 2); assert.equal(started, 6)
  const abort = new AbortController(); abort.abort(); await assert.rejects(transport.send('query', {}, abort.signal))
})
test('bounded retries, Retry-After seconds/date, long cooldowns and GraphQL errors', async () => {
  let count = 0
  const t = new Transport(async () => { count++; return count < 3 ? response({}, 503, { 'retry-after': '0' }) : response({ data: {} }) }, 0, 0)
  await t.send('', {}, signal()); assert.equal(count, 3)
  const long = new Transport(async () => response({}, 429, { 'retry-after': '31' }), 0, 0)
  await assert.rejects(long.send('', {}, signal()), /longer cooldown/)
  assert.equal(retryAfter('2'), 2000); assert.equal(retryAfter(new Date(5000).toUTCString(), 1000), 4000)
  const graph = new Transport(async () => response({ data: {}, errors: [{}] }), 0, 0)
  await assert.rejects(graph.send('', {}, signal()), /unsupported response/)
})
test('source response size is checked while streaming', async () => {
  await assert.rejects(jsonResponse(response({ text: 'x'.repeat(100) }), 50, signal()), /unsupported/)
})
test('PCC suggestions/search share flights and cache; refresh bypasses; invalid terms never fetch', async () => {
  let calls = 0, now = 1000
  const pcc = new PCC(async () => { calls++; await delay(10); return response([{ subjCode: 'ETH', courseNumbDisplay: '014', crn: '1' }]) }, () => now)
  await Promise.all([pcc.schedule('202650'), pcc.schedule('202650')]); assert.equal(calls, 1)
  await pcc.schedule('202650'); assert.equal(calls, 1)
  await pcc.schedule('202650', true); assert.equal(calls, 2)
  now += 300001; await pcc.schedule('202650'); assert.equal(calls, 3)
  await assert.rejects(pcc.schedule('../secret')); assert.equal(calls, 3)
})
test('profile pages reject stalled cursors, wrong IDs, missing connection, oversized pages and duplicates', async () => {
  const make = (node: any) => new RMP(new Transport(async () => response({ data: { node } }), 0, 0))
  await assert.rejects(make({ ...teacher, ratings: undefined }).page('1', 3, signal()))
  await assert.rejects(make(teacher).page('2', 3, signal()))
  await assert.rejects(make({ ...teacher, ratings: { edges: [], pageInfo: { hasNextPage: true, endCursor: 'same' } } }).page('1', 3, signal(), 'same'))
  const edges = [{ node: { id: 'r1', comment: 'Review' } }, { node: { id: 'r1', comment: 'Duplicate' } }]
  await assert.rejects(make({ ...teacher, ratings: { edges, pageInfo: { hasNextPage: false } } }).page('1', 3, signal()))
  await assert.rejects(make({ ...teacher, ratings: { edges, pageInfo: { hasNextPage: false } } }).page('1', 1, signal()))
})
test('blank reviews count toward coverage and absent dates are never invented', async () => {
  const node = { ...teacher, ratings: { edges: [{ node: { id: 'blank', comment: '' } }, { node: { id: 'text', comment: 'Actual text', class: 'ETH14' } }], pageInfo: { hasNextPage: false } } }
  const page = await new RMP(new Transport(async () => response({ data: { node } }), 0, 0)).page('1', 3, signal())
  assert.deepEqual(page.ids, ['blank', 'text']); assert.equal(page.profile.reviews.length, 1); assert.equal(page.profile.reviews[0].date, '')
})
test('candidate discovery retains eligible profiles after later-page failure', async () => {
  let calls = 0
  const rmp = new RMP(new Transport(async () => { calls++; return calls === 1 ? response({ data: { search: { teachers: { edges: [{ node: teacher }], pageInfo: { hasNextPage: true, endCursor: 'next' } } } } }) : response({}, 400) }, 0, 0))
  assert.equal((await rmp.candidates('John Harris', signal(), true)).length, 1); assert.equal(calls, 2)
})
test('one shared RMP transport caps starts across visitors and preserves a long cooldown', async () => {
  let starts = 0
  const budget = new Transport(async () => { starts++; return response({ data: {} }) }, 0, 0)
  for (let i = 0; i < 60; i++) await budget.send('', {}, signal())
  await assert.rejects(budget.send('', {}, signal()), /budget reached/); assert.equal(starts, 60)
  let calls = 0; const cooldown = new Transport(async () => { calls++; return response({}, 429, { 'retry-after': '60' }) }, 0, 0)
  await assert.rejects(cooldown.send('', {}, signal()), /longer cooldown/)
  await assert.rejects(cooldown.send('', {}, signal()), /longer cooldown/); assert.equal(calls, 1)
})
test('manual redirect handling rejects source redirects instead of following another host', async () => {
  const pcc = new PCC(async (_url, init) => { assert.equal(init?.redirect, 'manual'); return new Response('', { status: 302, headers: { Location: 'https://unexpected.example' } }) })
  await assert.rejects(pcc.terms(), /HTTP 302/)
  const rmp = new Transport(async (_url, init) => { assert.equal(init?.redirect, 'manual'); return new Response('', { status: 302, headers: { Location: 'https://unexpected.example' } }) }, 0, 0)
  await assert.rejects(rmp.send('', {}, signal()), /HTTP 302/)
})
