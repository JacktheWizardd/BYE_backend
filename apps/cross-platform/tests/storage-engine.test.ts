import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtemp, rm } from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import { setTimeout as delay } from 'node:timers/promises'
import { Engine, Queue } from '../src/main/engine'
import { Store } from '../src/main/storage'
import { IdentityError, PCC, RMP } from '../src/main/network'
import { course } from '../src/shared/domain'
import { buildSummary } from '../src/main/summary-evidence'
import { AI_SUMMARIES_DISABLED_MESSAGE } from '../src/shared/features'
import type { Profile, Review, Term } from '../src/shared/types'
import { fixtureServices } from '../scripts/offline-fixtures'
const term: Term = { termCode: '202650', termName: 'Summer 2026', termDisplayControl: 'Y' }
const base = (id = '1'): Profile => ({ id, firstName: 'John', lastName: 'Harris', schoolID: 2649, school: 'Pasadena City College', department: 'History', reviews: [], coverage: {}, courseCounts: [] })
const review = (id = 'r1'): Review => ({ id, text: 'Clear explanations', course: 'ETH14', date: '2026-01-01' })
async function temporary(t: any) { const directory = await mkdtemp(path.join(os.tmpdir(), 'bye-test-')); t.after(() => rm(directory, { recursive: true, force: true })); return directory }
function harness(directory: string, candidates: Profile[] = [base()], summariesEnabled?: () => boolean) {
  const pcc = { terms: async () => [term], schedule: async () => [{ subjCode: 'ETH', courseNumbDisplay: '014', crn: '1', pfaName: 'John Harris' }] } as unknown as PCC
  const fake = { candidates: async () => structuredClone(candidates), page: async (id: string, _count: number, _signal: AbortSignal, cursor?: string) => ({ profile: { ...base(id), reviews: [review(cursor ? 'r2' : 'r1')] }, ids: [cursor ? 'r2' : 'r1'], hasNextPage: !cursor, nextCursor: cursor ? undefined : 'next' }) }
  const ai = { cacheIdentity: 'test', summarize: async (reviews: Review[], c: ReturnType<typeof course>) => buildSummary({ positives: [], concerns: [] }, reviews, c, 'test') }
  const store = new Store(directory), snapshots: any[] = []
  const engine = new Engine(pcc, fake as unknown as RMP, store, ai, state => snapshots.push(state), summariesEnabled)
  return { engine, fake, store, snapshots, ai }
}

test('concurrent mixed MATH profiles and background retries never request dialogs', async t => {
  const h = harness(await temporary(t)), services = fixtureServices([])
  Object.assign(h.engine.pcc, services.pcc); Object.assign(h.fake, services.rmp)
  services.controls.ambiguous = true
  await h.engine.search('math 5a', term)
  assert.equal(h.engine.state.professors.find(p => p.name === 'Alex Example')?.state, 'choose')
  assert.equal(h.engine.state.professors.find(p => p.name === 'Blair Sample')?.state, 'choose')
  assert.equal(h.engine.state.professors.find(p => p.name === 'Casey Missing')?.state, 'unavailable')
  assert.equal(h.engine.state.professors.find(p => p.name === 'Dana Identity')?.state, 'choose')
  assert.ok(h.snapshots.every(s => s.professors.every((p: any) => !p.choosing)))
  await Promise.all(h.engine.state.professors.map(p => h.engine.retry(p.id)))
  assert.ok(h.snapshots.every(s => s.professors.every((p: any) => !p.choosing)))
  services.controls.ambiguous = false
  await h.engine.search('MATH 005A', term)
  assert.equal(h.engine.state.professors.find(p => p.name === 'Alex Example')?.state, 'ready')
  assert.ok(h.engine.state.professors.every(p => !p.choosing))
})

test('explicit discovery has one owner, deduplicates clicks and stays dismissed after delayed results', async t => {
  const h = harness(await temporary(t)), services = fixtureServices([])
  Object.assign(h.engine.pcc, services.pcc); Object.assign(h.fake, services.rmp)
  await h.engine.search('MATH5A', term)
  services.controls.candidateDelay = 60
  const calls = services.calls.candidates
  const first = h.engine.discover('alex example')
  const repeated = h.engine.discover('alex example')
  assert.equal(first, repeated)
  assert.equal(h.engine.state.professors[0].discoveryLoading, true)
  const second = h.engine.discover('blair sample')
  assert.deepEqual(h.engine.state.professors.filter(p => p.choosing).map(p => p.id), ['blair sample'])
  h.engine.dismiss('blair sample')
  await Promise.all([first, second])
  assert.equal(services.calls.candidates - calls, 2)
  assert.ok(h.engine.state.professors.every(p => !p.choosing && !p.discoveryLoading))
  await h.engine.discover('casey missing')
  assert.equal(h.engine.state.professors.find(p => p.id === 'casey missing')?.candidates.length, 0)
  h.fake.candidates = async () => { throw new Error('Fixture discovery failure') }
  await h.engine.discover('alex example')
  assert.equal(h.engine.state.professors[0].issue, 'Fixture discovery failure')
  assert.equal(h.engine.state.professors[0].discoveryLoading, false)
  assert.throws(() => h.engine.select('alex example', '9999'), /current candidate list/)
})

test('identity failures during selection and review loading never reopen a dialog', async t => {
  const h = harness(await temporary(t))
  await h.engine.search('ETH14', term)
  const p = h.engine.state.professors[0]
  h.fake.page = async () => { throw new IdentityError() }
  await h.engine.expand(p.id)
  assert.equal(p.state, 'choose'); assert.ok(!p.choosing)
  await h.engine.discover(p.id)
  await h.engine.select(p.id, '1')
  assert.equal(p.state, 'choose'); assert.ok(!p.choosing)
  await h.engine.discover(p.id)
  h.engine.stop()
  assert.ok(!p.choosing && !p.discoveryLoading)
})

test('new searches cancel an explicitly opened discovery without publishing its results', async t => {
  const h = harness(await temporary(t))
  await h.engine.search('ETH14', term)
  let release!: () => void
  h.fake.candidates = async () => { await new Promise<void>(resolve => { release = resolve }); return [base('2')] }
  const discovery = h.engine.discover(h.engine.state.professors[0].id)
  await h.engine.search('MATH5A', term)
  release(); await discovery
  assert.equal(h.engine.state.course?.key, 'MATH5A')
  assert.equal(h.engine.state.professors.length, 0)
  assert.ok(!h.snapshots.at(-1).professors.some((p: any) => p.choosing))
})
test('cache lifetime, clock rollback, subject isolation and evidence/provider invalidation', async t => {
  const directory = await temporary(t); let now = 10000; const s = new Store(directory, () => now), c = course('ETH14')
  await s.setChoice('Dr John Harris', 'ETH', '1'); assert.equal(await new Store(directory).choice('John Harris', 'ETH'), '1'); assert.equal(await s.choice('John Harris', 'MATH'), undefined)
  await s.setProfile(base()); assert.equal((await s.profile('1'))?.id, '1')
  now = 9999; assert.equal(await s.profile('1'), undefined)
  now = 10000 + 86400000; assert.equal(await s.profile('1'), undefined)
  now = 10000
  const summary = { ...buildSummary({ positives: [], concerns: [] }, [review()], c, 'test'), generatedAt: now }
  await s.setSummary('1', c, summary, [review()]); assert.ok(await s.summary('1', c, 'test', [review()]))
  assert.equal(await s.summary('1', c, 'other', [review()]), undefined)
  assert.equal(await s.summary('1', c, 'test', [{ ...review(), text: 'Changed text, same ID' }]), undefined)
  assert.equal(await s.summary('2', c, 'test', [review()]), undefined)
  await s.setProfile(base('3'), () => false); assert.equal(await s.profile('3'), undefined)
})
test('ambiguity requires choice, dismissal stays unresolved, confirmed choices survive restart', async t => {
  const h = harness(await temporary(t), [base('1'), { ...base('2'), department: 'Ethnic Studies' }])
  await h.engine.search('ETH14', term)
  let p = h.engine.state.professors[0]; assert.equal(p.state, 'choose'); assert.equal(p.profile, undefined)
  h.engine.dismiss(p.id); assert.equal(p.state, 'choose'); assert.equal(p.choosing, false)
  await h.engine.select(p.id, '2'); assert.equal(h.engine.state.professors[0].profile?.id, '2'); assert.equal(await h.store.choice(p.name, p.subject), '2')
  const next = harness(h.store.directory, [base('1'), base('2')]); await next.engine.search('ETH14', term)
  assert.equal(next.engine.state.professors[0].profile?.id, '2')
})
test('saved choices are retained on transient failure and invalidated on identity mismatch', async t => {
  const h = harness(await temporary(t), [base('1'), base('2')])
  await h.store.setChoice('John Harris', 'ETH', '1')
  h.fake.page = async () => { throw new Error('Temporary outage') }
  await h.engine.search('ETH14', term, true)
  assert.equal(h.engine.state.professors[0].state, 'unavailable'); assert.equal(await h.store.choice('John Harris', 'ETH'), '1')
  h.fake.page = async () => { throw new IdentityError() }
  await h.engine.retry(h.engine.state.professors[0].id)
  assert.equal(h.engine.state.professors[0].state, 'choose'); assert.equal(await h.store.choice('John Harris', 'ETH'), undefined); assert.equal(await h.store.index('John Harris', 'ETH'), undefined)
})
test('profile discovery preserves report until replacement confirmation, then clears immediately', async t => {
  const h = harness(await temporary(t))
  await h.engine.search('ETH14', term); const p = h.engine.state.professors[0]
  h.fake.candidates = async () => [base('1'), base('2')]
  await h.engine.discover(p.id); assert.equal(p.profile?.id, '1')
  const page = h.fake.page; h.fake.page = async (...args) => { await delay(30); return page(...args) }
  const selecting = h.engine.select(p.id, '2'); assert.equal(p.profile, undefined); assert.equal(p.summary, undefined)
  await selecting; assert.equal(h.engine.state.professors[0].profile?.id, '2')
})
test('partial detail failures persist cursor and resume after retry', async t => {
  const h = harness(await temporary(t)); await h.engine.search('ETH14', term)
  const p = h.engine.state.professors[0], page = h.fake.page; let fail = true
  h.fake.page = async (...args) => { if (args[3] && fail) throw new Error('Temporary outage'); return page(...args) }
  await h.engine.expand(p.id); assert.match(p.reviewIssue!, /Temporary/); assert.equal(p.profile?.coverage.all.nextCursor, 'next')
  assert.equal((await new Store(h.store.directory).profile('1'))?.coverage.all.nextCursor, 'next')
  fail = false; await h.engine.expand(p.id); assert.equal(p.profile?.reviews.length, 2); assert.equal(p.profile?.coverage.all.hasNextPage, false)
})
test('changed search rejects delayed preview publication and cache writes', async t => {
  const h = harness(await temporary(t)); let release!: () => void
  const page = h.fake.page; h.fake.page = async (...args) => { await new Promise<void>(resolve => { release = resolve }); return page(...args) }
  const old = h.engine.search('ETH14', term)
  while (!release) await delay(5)
  const newOperation = h.engine.search('MATH5A', term); release(); await Promise.all([old, newOperation])
  assert.equal(h.engine.state.course?.key, 'MATH5A'); assert.equal(h.engine.state.professors.length, 0); assert.equal(await h.store.profile('1'), undefined)
})
test('cancelled summaries cannot publish or cache and ratings remain usable', async t => {
  const h = harness(await temporary(t), [base()], () => true); await h.engine.search('ETH14', term)
  const p = h.engine.state.professors[0]; let started = false
  h.ai.summarize = async (reviews, c) => { started = true; await delay(40); return buildSummary({ positives: [], concerns: [] }, reviews, c, 'test') }
  const job = h.engine.summarize(p.id); while (!started) await delay(5); h.engine.stop(); await job
  assert.equal(p.summary, undefined); assert.equal(p.profile?.id, '1'); assert.equal(await h.store.summary('1', course('ETH014'), 'test', p.profile!.reviews), undefined)
})

test('disabled summaries skip both cache reuse and inference while reviews stay usable', async t => {
  const h = harness(await temporary(t)); await h.engine.search('ETH14', term)
  const p = h.engine.state.professors[0], c = course('ETH14'), reviews = p.profile!.reviews
  const cached = buildSummary({ positives: [], concerns: [] }, reviews, c, 'test')
  await h.store.setSummary(p.profile!.id, c, cached, reviews)
  p.summary = cached
  h.ai.summarize = async () => { assert.fail('Disabled summaries must not invoke inference') }
  const readSummary = h.store.summary.bind(h.store)
  h.store.summary = async () => { assert.fail('Disabled summaries must not read the summary cache') }
  await h.engine.summarize(p.id)
  assert.equal(p.summary, undefined); assert.equal(p.summaryLoading, false)
  assert.equal(p.summaryIssue, AI_SUMMARIES_DISABLED_MESSAGE)
  assert.equal(h.snapshots.at(-1).professors[0].summaryIssue, AI_SUMMARIES_DISABLED_MESSAGE)
  assert.ok(await readSummary(p.profile!.id, c, 'test', reviews), 'Existing local summaries are retained')
  await h.engine.expand(p.id)
  assert.equal(p.profile!.reviews.length, 2); assert.equal(p.profile!.id, '1')
})
test('detail pagination caps source ratings at 50 including blank comments', async t => {
  const h = harness(await temporary(t)); await h.engine.search('ETH14', term); const p = h.engine.state.professors[0]; let downloaded = 1
  h.fake.page = async (id, count) => { const ids = Array.from({ length: count }, (_, i) => String(downloaded + i)); downloaded += count; return { profile: base(id), ids, hasNextPage: true, nextCursor: 'cursor-' + downloaded } }
  await h.engine.expand(p.id); assert.equal(p.profile?.coverage.all.reviewIDs.length, 50); assert.equal(downloaded, 50)
})
test('queue prioritizes previews, bounds concurrency and cancels pending jobs', async () => {
  const preview = new Queue(2), details = new Queue(1, () => preview.pending > 0), controller = new AbortController(), order: string[] = []
  const jobs = [preview.run(controller.signal, async () => { await delay(20); order.push('preview') }), details.run(controller.signal, async () => { order.push('detail') })]
  await Promise.all(jobs); assert.deepEqual(order, ['preview', 'detail'])
  const blocked = new Queue(1, () => true), abort = new AbortController(), pending = blocked.run(abort.signal, async () => {})
  abort.abort(); await assert.rejects(pending); assert.equal(blocked.pending, 0)
})
test('fresh ambiguity invalidates automatic identity cache and remains unresolved on the next search', async t => {
  const h = harness(await temporary(t)); await h.engine.search('ETH14', term)
  assert.equal(await h.store.index('John Harris', 'ETH'), '1')
  h.fake.candidates = async () => [base('1'), base('2')]
  await h.engine.search('ETH14', term, true); assert.equal(h.engine.state.professors[0].state, 'choose')
  assert.equal(await h.store.index('John Harris', 'ETH'), undefined)
  await h.engine.search('ETH14', term); assert.equal(h.engine.state.professors[0].state, 'choose')
})
test('invalid saved identity stays unresolved even when subsequent discovery fails', async t => {
  const h = harness(await temporary(t)); await h.store.setChoice('John Harris', 'ETH', '1')
  h.fake.page = async () => { throw new IdentityError() }; h.fake.candidates = async () => { throw new Error('Outage') }
  await h.engine.search('ETH14', term, true)
  assert.equal(h.engine.state.professors[0].state, 'choose'); assert.equal(h.engine.state.professors[0].candidates.length, 0)
})
