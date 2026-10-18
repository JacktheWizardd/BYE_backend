import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { WEEKDAYS, catalog, course, dateLabel, delivery, displayTitle, eligible, excerpt, filterFinished, filterReviews, filterSections, fits, formatLabel, identity, orderReviews, place, preferredFilter, professors, requestLabel, resolve, reviewURL, sameCourse, scheduleNotAnnounced, suggestions, visibleText } from '../src/shared/domain'
import { buildSummary, corroborated, selectEvidence } from '../src/main/summary-evidence'
import type { Profile, Review, Row } from '../src/shared/types'
export const profile = (id = '1', overrides: Partial<Profile> = {}): Profile => ({ id, firstName: 'John', lastName: 'Harris', schoolID: 2649, school: 'Pasadena City College', department: 'History', reviews: [], courseCounts: [], coverage: {}, ...overrides })
const review = (id: string, text: string, label = 'ETH014'): Review => ({ id, text, course: label, date: '2026-05-01' })

test('MATH suffix suggestions and searches preserve the official course and sections', async () => {
  const rows: Row[] = JSON.parse(await readFile(new URL('./fixtures/math-courses.json', import.meta.url), 'utf8'))
  for (const input of ['MATH 005A', 'math 005a', 'math 5a', 'MATH5A']) {
    assert.equal(suggestions(input, rows)[0].course.display, 'MATH 005A')
    const resolved = resolve(input, rows)
    assert.equal(resolved.key, 'MATH005A')
    assert.equal(professors(rows, resolved).flatMap(p => p.sections).length, 4)
    assert.equal(sameCourse(resolved, 'MATH005B'), false)
  }
  assert.deepEqual(suggestions('MATH 005', rows).map(s => s.course.number), ['005A', '005B'])
})
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
test('0.4.0 section details, meeting places, day filter and format labels match the Mac app', async () => {
  const rows = JSON.parse(await readFile(new URL('../../../Tests/ClasswiseCoreTests/Fixtures/pcc-summer-2026-eth014.json', import.meta.url), 'utf8'))
  const result = professors(rows, course('ETH14'))
  const hybrid = result.find(p => p.name === 'Ryan Howard')!.sections[0], online = result.find(p => p.name === 'Ariana Flores')!.sections[0]
  assert.equal(formatLabel(hybrid), 'Hybrid'); assert.equal(formatLabel(online), 'Online · async')
  assert.equal(fits(online, ['Sat']), true)
  assert.ok(hybrid.days!.length > 0); assert.equal(fits(hybrid, hybrid.days!), true)
  assert.equal(fits(hybrid, WEEKDAYS.map(d => d.key).filter(d => !hybrid.days!.includes(d)).slice(0, 1)), false)
  const unscheduled = { ...hybrid, formats: ['LE'], days: [] }
  assert.equal(fits(unscheduled, ['Mon']), false); assert.equal(scheduleNotAnnounced(unscheduled), true)
  assert.equal(formatLabel({ ...hybrid, formats: ['OL'] }), 'Online · live'); assert.equal(formatLabel({ ...hybrid, formats: ['LE'] }), 'In person')
  const row: Row = { subjCode: 'ETH', courseNumbDisplay: '014', crn: '1', pfaName: 'Ada Lovelace', schdCode: 'LE', monDay: 'M', wedDay: 'W', beginTime: '0800', endTime: '0925', bldgDesc: 'C', roomCode: '323',
    seatsAvail: '-2', maxEnrl: '40', waitCount: '6', waitCapacity: '10', ptrmDesc: 'Full term', campDesc: 'Main campus', creditHrLow: '3', subjDesc: 'Ethnic Studies' }
  const [ada] = professors([row, { ...row, pfaName: 'Grace Hopper', monDay: '', wedDay: '', friDay: 'F' }], course('ETH14'))
  assert.equal(ada.subjectDescription, 'Ethnic Studies')
  // Co-instructors keep every meeting of the shared CRN.
  assert.deepEqual(ada.sections[0].days, ['Mon', 'Wed', 'Fri'])
  assert.ok(ada.sections[0].meetings.includes('Mon, Wed 8:00 AM – 9:25 AM · C 323'))
  assert.deepEqual(ada.sections[0].details, { seatsOpen: 0, capacity: 40, waitlistCount: 6, waitlistCapacity: 10, termPart: 'Full term', campus: 'Main campus', units: '3' })
  assert.equal(place('Online ASYNCH,R', 'Needs Assignment'), 'R · room TBA')
  assert.equal(place('Online Zoom', ''), 'Online (Zoom)')
  assert.equal(dateLabel({ ...hybrid, start: '2026-06-22T00:00:00', end: 'bad' }), 'Jun 22, 2026 – Date unavailable')
  assert.equal(displayTitle('INTRO TO ETHNIC STUDIES II'), 'Intro to Ethnic Studies II')
  const both = filterSections([ada], ['Fri'], false); assert.equal(both.length, 1)
  assert.equal(filterSections([ada], [], true).length, 0)
})
test('review sorts, preferred filter, entities and review link follow the Mac app', () => {
  const rated = (id: string, rating: number | undefined, date: string, difficulty?: number): Review => ({ id, text: id, course: 'ETH014', date, rating, difficulty })
  const list = [rated('a', 3, '2026-05-01 00:00:00 +0000 UTC', 2), rated('b', undefined, '2026-06-01 00:00:00 +0000 UTC', 5), rated('c', 5, '', 1), rated('d', 3, '2026-07-01T00:00:00Z')]
  assert.deepEqual(orderReviews(list, 'recent').map(r => r.id), ['d', 'b', 'a', 'c'])
  assert.deepEqual(orderReviews(list, 'oldest').map(r => r.id), ['a', 'b', 'd', 'c'])
  assert.deepEqual(orderReviews(list, 'highest').map(r => r.id), ['c', 'd', 'a', 'b'])
  assert.deepEqual(orderReviews(list, 'lowest').map(r => r.id), ['d', 'a', 'c', 'b'])
  assert.deepEqual(orderReviews(list, 'highestDifficulty').map(r => r.id), ['b', 'a', 'c', 'd'])
  assert.deepEqual(orderReviews(list, 'difficulty').map(r => r.id), ['c', 'a', 'b', 'd'])
  assert.equal(preferredFilter(undefined, course('ETH14')), 'this')
  assert.equal(preferredFilter(profile('1', { reviews: [review('1', 'x', 'SOC14')] }), course('ETH14')), 'all')
  assert.equal(preferredFilter(profile('1', { reviews: [review('1', 'x', 'ETH14')] }), course('ETH14')), 'this')
  assert.equal(visibleText('A &amp; B &#8212; C&#x27;s &bogus; &'), 'A & B — C\'s &bogus; &')
  assert.equal(excerpt(review('1', 'x'.repeat(600))).length, 501)
  assert.equal(reviewURL('Ada Lovelace+', course('ETH 014')), 'https://bye-before-you-enroll.pages.dev/reviews/?professor=Ada+Lovelace%2B&course=ETH+014')
  assert.equal(reviewURL('  ', course('ETH 014')), undefined)
  const covered = profile('1', { coverage: { 'course|ETH014': { reviewIDs: [], hasNextPage: false, updatedAt: 0 } } })
  assert.equal(filterFinished(covered, course('ETH 014'), 'this'), true); assert.equal(filterFinished(covered, course('ETH 014'), 'all'), false)
  assert.equal(requestLabel(course('ETH 014'), 'all'), undefined)
})
