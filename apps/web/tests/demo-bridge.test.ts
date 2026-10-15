import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { filterReviews, normalizedName } from '@shared/domain'
import type { Row, Snapshot, Suggestion, Term } from '@shared/types'
import { DEMO_SUMMARY_MESSAGE, DemoBridge, PREVIEW_COUNT } from '../src/demo-bridge'
import { demoData, FALL } from '../src/demo-data'

function setup() {
  const bridge = new DemoBridge(demoData, 0)
  let state!: Snapshot
  bridge.subscribe(s => { state = s })
  return { bridge, get: () => state }
}
async function search(query: string) {
  const s = setup()
  await s.bridge.command({ kind: 'search', query, term: FALL }); await s.bridge.idle()
  return s
}
const find = (state: Snapshot, name: string) => state.professors.find(p => p.name === name)!

test('terms and course suggestions come from the sample schedule', async () => {
  const { bridge } = setup()
  const terms = await bridge.command({ kind: 'terms' }) as Term[]
  assert.deepEqual(terms.map(t => t.termName), ['Fall 2026'])
  const results = await bridge.command({ kind: 'suggest', term: FALL.termCode, query: 'calc' }) as Suggestion[]
  assert.equal(results[0].course.display, 'MATH 5A')
  assert.equal((await bridge.command({ kind: 'suggest', term: FALL.termCode, query: 'eth14' }) as Suggestion[])[0].course.key, 'ETH014')
})

test('search groups sections by professor and previews each profile', async () => {
  const { get } = await search('eth 14')
  const state = get()
  assert.equal(state.course?.display, 'ETH 014'); assert.equal(state.loading, false); assert.equal(state.previewPending, 0)
  assert.equal(state.professors.length, 5)
  const marisol = find(state, 'Marisol Quintero-Hale')
  assert.equal(marisol.state, 'ready'); assert.equal(marisol.sections.length, 2)
  assert.equal(marisol.profile?.reviews.length, PREVIEW_COUNT)
  assert.equal(marisol.profile?.coverage.all?.hasNextPage, true)
  const tba = find(state, 'Instructor to be announced')
  assert.equal(tba.state, 'unavailable'); assert.match(tba.issue!, /not named an instructor/)
})

test('an ambiguous name asks for a profile and remembers the choice', async () => {
  const s = await search('ETH 014')
  const daniel = find(s.get(), 'Daniel Reyes')
  assert.equal(daniel.state, 'choose'); assert.equal(daniel.candidates.length, 2); assert.equal(daniel.profile, undefined)
  await s.bridge.command({ kind: 'discover', professorId: daniel.id }); await s.bridge.idle()
  assert.equal(find(s.get(), 'Daniel Reyes').choosing, true)
  await s.bridge.command({ kind: 'select', professorId: daniel.id, profileId: '9999' }); await s.bridge.idle()
  assert.match(s.get().issue!, /current list/)
  await s.bridge.command({ kind: 'select', professorId: daniel.id, profileId: '7103' }); await s.bridge.idle()
  const chosen = find(s.get(), 'Daniel Reyes')
  assert.equal(chosen.state, 'ready'); assert.equal(chosen.profile?.department, 'Ethnic Studies'); assert.equal(chosen.choosing, false)
  await s.bridge.command({ kind: 'search', query: 'ETH 014', term: FALL }); await s.bridge.idle()
  assert.equal(find(s.get(), 'Daniel Reyes').profile?.id, '7103')
})

test('a professor without a profile is marked unavailable with a reason', async () => {
  const { get } = await search('MATH 5A')
  const calvin = find(get(), 'Calvin Ostrowski')
  assert.equal(calvin.state, 'unavailable'); assert.match(calvin.issue!, /No matching PCC profile/)
})

test('details load every review and course filters use the shared domain logic', async () => {
  const s = await search('MATH 5A')
  const lena = find(s.get(), 'Lena Whitcombe')
  await s.bridge.command({ kind: 'details', professorId: lena.id }); await s.bridge.idle()
  const profile = find(s.get(), 'Lena Whitcombe').profile!
  const source = demoData.profiles.find(p => p.id === profile.id)!
  assert.equal(profile.reviews.length, source.reviews.length); assert.equal(profile.coverage.all?.hasNextPage, false)
  const thisCourse = filterReviews(profile, s.get().course!, 'this')
  assert.ok(thisCourse.length > 0 && thisCourse.every(r => r.course === 'MATH5A'))
  assert.equal(filterReviews(profile, s.get().course!, 'all').length, profile.reviews.length)
})

test('summary reports that AI is not part of the demo', async () => {
  const s = await search('ENGL 1A')
  const yuki = find(s.get(), 'Yuki Hartwell')
  await s.bridge.command({ kind: 'summary', professorId: yuki.id })
  assert.equal(find(s.get(), 'Yuki Hartwell').summaryIssue, DEMO_SUMMARY_MESSAGE)
})

test('stop ends a running search and a new search still works', async () => {
  const bridge = new DemoBridge(demoData, 1)
  let state!: Snapshot; bridge.subscribe(s => { state = s })
  await bridge.command({ kind: 'search', query: 'ENGL 1A', term: FALL })
  await new Promise(r => setTimeout(r, 450))
  assert.ok(state.professors.some(p => p.state === 'loading'))
  await bridge.command({ kind: 'stop' }); await bridge.idle()
  assert.equal(state.loading, false)
  assert.ok(state.professors.every(p => p.state === 'ready' || p.state === 'unavailable'))
  assert.ok(state.professors.some(p => p.issue?.startsWith('Stopped')))
  await bridge.command({ kind: 'search', query: 'ETH 014', term: FALL }); await bridge.idle()
  assert.equal(state.course?.key, 'ETH014'); assert.equal(state.loading, false)
  assert.ok(state.professors.filter(p => p.state === 'ready').length >= 3)
})

test('unknown courses and links out report a readable issue', async () => {
  const { get } = await search('CHEM 1A')
  assert.equal(get().professors.length, 0); assert.match(get().issue!, /No matching sections/)
  await assert.rejects(new DemoBridge(demoData, 0).command({ kind: 'source', target: 'rmp' }), /turned off in the demo/)
})

test('sample data never reuses instructor names from the saved PCC schedule', async () => {
  const saved = JSON.parse(await readFile(new URL('../../../Tests/ClasswiseCoreTests/Fixtures/pcc-summer-2026-eth014.json', import.meta.url), 'utf8')) as Row[]
  const real = new Set(saved.map(r => normalizedName(String(r.pfaName ?? ''))).filter(Boolean))
  const demo = [...Object.values(demoData.schedules).flat().map(r => String(r.pfaName ?? '')), ...demoData.profiles.map(p => `${p.firstName} ${p.lastName}`)]
  for (const name of demo.map(normalizedName).filter(Boolean)) assert.equal(real.has(name), false, `${name} appears in the real schedule`)
})
