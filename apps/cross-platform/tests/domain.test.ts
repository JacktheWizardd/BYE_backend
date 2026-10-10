import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { catalog, course, delivery, eligible, filterReviews, identity, professors, resolve, sameCourse, suggestions } from '../src/shared/domain'
import { buildSummary, corroborated, selectEvidence } from '../src/main/summary-evidence'
import type { Profile, Review, Row } from '../src/shared/types'
export const profile = (id = '1', overrides: Partial<Profile> = {}): Profile => ({ id, firstName: 'John', lastName: 'Harris', schoolID: 2649, school: 'Pasadena City College', department: 'History', reviews: [], courseCounts: [], coverage: {}, ...overrides })
const review = (id: string, text: string, label = 'ETH014'): Review => ({ id, text, course: label, date: '2026-05-01' })
test('course shorthand preserves subject, prefix, suffix and original label', () => {
  for (const input of ['math 5a', 'MATH05A', 'MATH 005A']) assert.equal(course(input).matchingKey, 'MATH5A')
  assert.equal(course('POLS C1000').matchingKey, 'POLSC1000')
  assert.equal(course('ETH000').matchingKey, 'ETH0')
  assert.equal(course('ETH 014').display, 'ETH 014')
  for (const input of ['14', 'SOC14', 'ETH14B']) assert.equal(sameCourse(course('ETH014'), input), false)
  assert.throws(() => course('5A'))
})
test('official resolution, exact precedence and ambiguous aliases', () => {
  const rows: Row[] = ['005A', '5A'].map((number, i) => ({ subjCode: 'MATH', courseNumbDisplay: number, crn: String(i + 1), courseTitle: 'Calculus' }))
  assert.equal(resolve('math5a', rows).key, 'MATH5A')
  assert.throws(() => resolve('math05a', rows), /More than one/)
  assert.equal(resolve('math05a', rows.slice(0, 1)).key, 'MATH005A')
  assert.equal(suggestions('math5a', rows)[0].course.key, 'MATH5A')
  assert.equal(catalog([{ ...rows[0], fwSectOpenInd: 'R' }]).length, 0)
})
test('PCC fixture retains closed sections, deduplicates CRNs and groups meetings', async () => {
  const rows = JSON.parse(await readFile(new URL('../../../Tests/ClasswiseCoreTests/Fixtures/pcc-summer-2026-eth014.json', import.meta.url), 'utf8'))
  const result = professors(rows, course('ETH14'))
  assert.equal(result.length, 10)
  assert.equal(result.reduce((n, p) => n + p.sections.length, 0), 14)
  const hybrid = result.find(p => p.name === 'Ryan Howard')!.sections[0]
  assert.equal(hybrid.crn, '54591'); assert.equal(hybrid.meetings.length, 2)
  assert.equal(delivery(hybrid), 'Hybrid · campus meetings required')
  assert.equal(delivery(result.find(p => p.name === 'Ariana Flores')!.sections[0]), 'Online · no scheduled meetings')
})
test('identity requires PCC school and conservative full name; departments never break ties', () => {
  const a = profile(), b = profile('2', { department: 'Ethnic Studies' })
  assert.equal(eligible('John Harris', [a, b, a]).length, 2)
  assert.equal(identity('John Harris', profile('1', { schoolID: 1 })), false)
  assert.equal(identity('John Harris', profile('1', { school: 'Other College' })), false)
  assert.equal(identity('John Harris', profile('1', { firstName: 'Jane' })), false)
  assert.equal(identity('Dr José De La Cruz', profile('1', { firstName: 'Jose', lastName: 'De La Cruz' })), true)
  assert.equal(identity('Jose De La Cruz', profile('1', { firstName: 'Jose', lastName: 'Cruz' })), false)
})
test('review filters preserve source labels, separate all-course coverage and cap 50', () => {
  const p = profile('1', { reviews: [review('1', 'Text', 'MATH5A'), review('2', 'Other', 'SOC14'), review('3', 'Unspecified', '5A')], coverage: { all: { reviewIDs: ['1', '2'], hasNextPage: false, updatedAt: Date.now() } } })
  assert.deepEqual(filterReviews(p, course('MATH005A'), 'this').map(r => r.id), ['1'])
  assert.equal(filterReviews(p, course('MATH005A'), 'all').length, 2)
  assert.equal(filterReviews(p, course('MATH005A'), 'SOC14')[0].course, 'SOC14')
})
test('summary evidence prefers two course-specific reviews and retains complete text', () => {
  const reviews = [review('1', 'A'.repeat(3000)), review('2', 'Other', 'SOC14'), review('3', 'Clear explanations')]
  const selected = selectEvidence(reviews, course('ETH14'))
  assert.equal(selected.length, 2); assert.equal(selected[0].text.length, 3000)
})
test('grounding rejects fabricated IDs, isolated qualifiers, negation and false sentiment', () => {
  const reviews = [review('1', 'Clear explanations. Helpful lectures.'), review('2', 'Clear explanations and caring teaching.')]
  assert.equal(corroborated({ text: 'Clear explanations', reviewIDs: ['1', '2'] }, reviews, false), true)
  assert.equal(corroborated({ text: 'Clear explanations and caring teaching', reviewIDs: ['1', '2'] }, reviews, false), false)
  assert.equal(corroborated({ text: 'Clear explanations', reviewIDs: ['1', 'fake'] }, reviews, false), false)
  assert.equal(corroborated({ text: 'Excessive homework', reviewIDs: ['1', '2'] }, [review('1', 'Homework was not excessive'), review('2', 'Never excessive homework')], true), false)
  assert.equal(corroborated({ text: 'Difficult exams', reviewIDs: ['1', '2'] }, [review('1', 'Difficult exams'), review('2', 'Difficult exams')], false), false)
  const result = buildSummary({ overview: 'Invented policy', positives: [{ text: 'Clear explanations', reviewIDs: ['1', '2'] }], concerns: [{ text: 'Expensive textbooks', reviewIDs: ['1', '2'] }] }, reviews, course('ETH14'), 'test')
  assert.equal(result.positives.length, 1); assert.equal(result.concerns.length, 0); assert.doesNotMatch(result.overview, /Invented/)
})
test('supported unfavorable observations cannot appear as positives even if model assigns wrong category', () => {
  const reviews = [review('1', 'Difficult exams were stressful'), review('2', 'Exams were difficult and stressful')]
  const result = buildSummary({ positives: [{ text: 'Difficult exams', reviewIDs: ['1', '2'] }], concerns: [] }, reviews, course('ETH14'), 'test')
  assert.equal(result.positives.length, 0); assert.equal(result.concerns[0].text, 'Difficult exams')
})
