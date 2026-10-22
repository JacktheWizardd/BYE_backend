import { test } from 'node:test'
import assert from 'node:assert/strict'
import { setTimeout as delay } from 'node:timers/promises'
import { SourceService, SCHEDULE_TTL, type Cache, type CacheEntry, type SourceConfig } from '../src/service'
import { IdentityError } from '../src/network'
import type { Profile } from '@bye/contracts/types'
import { demoData, FALL } from './source-data'
import { normalizedName } from '@bye/source-domain'

import { setup } from './fixtures'
const params = (extra: Record<string, string> = {}) => new URLSearchParams({ term: FALL.termCode, course: 'MATH5A', instructor: 'Lena Whitcombe', id: '7101', ...extra })

test('disabled API and unauthorized RMP never retrieve professor data', async () => {
  const off = setup({ enabled: false }); await assert.rejects(off.service.operation('sections', params(), 'one'), /not available/); assert.equal(off.counts().schedules, 0)
  const unapproved = setup({ rmpAuthorized: false }); await assert.rejects(unapproved.service.operation('profile', params(), 'one'), /authorized/); assert.equal(unapproved.counts().profiles, 0)
  const noReference = setup({ rmpPermissionRef: '' }); await assert.rejects(noReference.service.operation('profile', params(), 'one'), /authorized/)
})
test('concurrent visitors share semester retrieval and cached results', async () => {
  const s = setup()
  const results = await Promise.all(Array.from({ length: 10 }, (_, i) => s.service.operation('sections', params(), String(i))))
  assert.equal(s.counts().schedules, 1); assert.equal(results[0].data.course.display, 'MATH 5A')
  await s.service.operation('sections', params(), 'another'); assert.equal(s.counts().schedules, 1)
})
test('expired PCC data refreshes; failed refresh retains sections and hides enrollment counts', async () => {
  const s = setup(); await s.service.operation('sections', params(), 'one'); s.advance(SCHEDULE_TTL + 1); s.fail()
  const result = await s.service.operation('sections', params(), 'one')
  assert.equal(result.meta.stale, true); assert.ok(result.warning)
  for (const p of result.data.professors) for (const section of p.sections) { assert.equal(section.source?.stale, true); assert.equal(section.details?.seatsOpen, undefined); assert.equal(section.details?.waitlistCount, undefined) }
  s.advance(86_400_000); await assert.rejects(s.service.operation('sections', params(), 'one'))
})
test('published terms and instructor membership are checked server-side', async () => {
  const s = setup()
  await assert.rejects(s.service.operation('sections', params({ term: '../bad' }), 'one'))
  await assert.rejects(s.service.operation('sections', params({ term: '999999' }), 'one'))
  await assert.rejects(s.service.operation('candidates', params({ instructor: 'Someone Else' }), 'one'))
  await assert.rejects(s.service.operation('reviews', params({ filter: '../secret' }), 'one'))
  await assert.rejects(s.service.operation('reviews', params({ remaining: '0' }), 'one'))
  assert.equal(s.counts().profiles, 0)
})
test('profiles are verified against PCC identity, even when ID exists at RMP', async () => {
  const s = setup(), wrong = demoData.profiles.find(p => p.firstName !== 'Lena')!
  await assert.rejects(s.service.operation('profile', params({ id: wrong.id }), 'one'), /identity/)
  const right = demoData.profiles.find(p => p.firstName === 'Lena')!
  const result = await s.service.operation('profile', params({ id: right.id }), 'one'); assert.equal(result.data.profile.id, right.id); assert.equal(result.data.profile.source?.source, 'rmp')
})
test('RMP page cache suppresses duplicate requests without retaining choices', async () => {
  const s = setup(), id = demoData.profiles.find(p => p.firstName === 'Lena')!.id
  await Promise.all(Array.from({ length: 10 }, (_, i) => s.service.operation('profile', params({ id }), String(i))))
  assert.equal(s.counts().profiles, 1); assert.ok(![...s.cache.entries.keys()].some(k => k.includes('choice')))
})
test('zero RMP retention stores no profile or candidate evidence', async () => {
  const s = setup({ rmpCacheSeconds: 0 }), id = demoData.profiles.find(p => p.firstName === 'Lena')!.id
  await s.service.operation('profile', params({ id }), 'one'); await s.service.operation('profile', params({ id }), 'two')
  assert.equal(s.counts().profiles, 2); assert.ok([...s.cache.entries.keys()].every(k => k === 'terms' || k.startsWith('schedule:')))
})
test('shared service enforces a per-client traffic limit and allows another visitor', async () => {
  const s = setup()
  for (let i = 0; i < 120; i++) await s.service.operation('terms', new URLSearchParams(), 'one')
  await assert.rejects(s.service.operation('terms', new URLSearchParams(), 'one'), /Too many/)
  assert.ok((await s.service.operation('terms', new URLSearchParams(), 'two')).data.length)
  s.advance(60_001); await s.service.operation('terms', new URLSearchParams(), 'one')
})
