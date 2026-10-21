import type { Course, Profile, Professor, Review, Row, Section, SectionDetails, Suggestion, Weekday } from './types'
export const fold = (s: string) => s.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase()
export function course(input: string): Course {
  const match = input.trim().toUpperCase().match(/^([A-Z]{2,8})\s*([A-Z]?\d{1,4}[A-Z]?)$/)
  if (!match) throw new Error('Enter a subject and course number, such as ETH 014 or POLS C1000.')
  const [, subject, number] = match
  return { subject, number, key: subject + number, display: `${subject} ${number}`, matchingKey: subject + number.replace(/\d+/, n => String(Number(n))) }
}
export function sameCourse(a: Course, label: string) { try { return a.matchingKey === course(label).matchingKey } catch { return false } }
const value = (r: Row, k: string) => typeof r[k] === 'string' || typeof r[k] === 'number' ? String(r[k]) : ''
export function catalog(rows: Row[]): Suggestion[] {
  const result = new Map<string, Suggestion>()
  for (const row of rows) {
    if (['R', 'X'].includes(value(row, 'fwSectOpenInd')) || !value(row, 'crn')) continue
    try {
      const c = course(value(row, 'subjCode') + value(row, 'courseNumbDisplay')), title = value(row, 'courseTitle').trim()
      const old = result.get(c.key)
      if (!old || !old.title || (title && title.localeCompare(old.title) < 0)) result.set(c.key, { course: c, title })
    } catch { /* Ignore unrelated malformed schedule rows. */ }
  }
  return [...result.values()].sort((a, b) => a.course.display.localeCompare(b.course.display, 'en', { numeric: true }))
}
export function resolve(query: string, rows: Row[]): Course {
  const c = course(query), matches = catalog(rows).filter(x => x.course.matchingKey === c.matchingKey)
  const exact = matches.find(x => x.course.key === c.key)
  if (exact) return exact.course
  if (matches.length > 1) throw new Error('More than one PCC course matches. Choose an official course from the suggestions.')
  return matches[0]?.course ?? c
}
export function suggestions(query: string, rows: Row[]): Suggestion[] {
  const needle = fold(query).trim(), compact = needle.replace(/\s/g, '').toUpperCase()
  if (!needle) return []
  let parsed: Course | undefined; try { parsed = course(query) } catch { /* Partial input. */ }
  return catalog(rows).map(item => ({ item, rank: item.course.key === compact ? 0 : item.course.matchingKey === parsed?.matchingKey ? 1 : item.course.key.startsWith(compact) ? 2 : fold(item.title).startsWith(needle) ? 3 : item.course.key.includes(compact) || fold(item.title).includes(needle) ? 4 : 99 }))
    .filter(x => x.rank < 99).sort((a, b) => a.rank - b.rank || a.item.course.display.localeCompare(b.item.course.display)).slice(0, 5).map(x => x.item)
}
export const nameTokens = (s: string) => fold(s).split(/[^\p{L}]+/u).filter(x => x && !['dr', 'prof', 'professor'].includes(x))
export const normalizedName = (s: string) => nameTokens(s).join(' ')
export function identity(name: string, p: Profile): boolean {
  const tokens = nameTokens(name), first = nameTokens(p.firstName), last = nameTokens(p.lastName)
  return p.schoolID === 2649 && normalizedName(p.school) === 'pasadena city college' && tokens.length >= 2 && first[0] === tokens[0] && last.includes(tokens.at(-1)!) && tokens.slice(1).every(x => [...first, ...last].includes(x))
}
export function eligible(name: string, profiles: Profile[]) {
  return [...new Map(profiles.filter(p => identity(name, p)).map(p => [p.id, p])).values()].sort((a, b) => `${a.firstName}|${a.lastName}|${a.department}|${a.id}`.localeCompare(`${b.firstName}|${b.lastName}|${b.department}|${b.id}`))
}
function clock(s: string) {
  if (!/^\d{4}$/.test(s) || Number(s.slice(0, 2)) > 23 || Number(s.slice(2)) > 59) return s
  const h = Number(s.slice(0, 2)); return `${h % 12 || 12}:${s.slice(2)} ${h < 12 ? 'AM' : 'PM'}`
}
export const WEEKDAYS: { key: Weekday; short: string; label: string }[] = [
  { key: 'Mon', short: 'M', label: 'Monday' }, { key: 'Tue', short: 'T', label: 'Tuesday' }, { key: 'Wed', short: 'W', label: 'Wednesday' },
  { key: 'Thu', short: 'Th', label: 'Thursday' }, { key: 'Fri', short: 'F', label: 'Friday' }, { key: 'Sat', short: 'Sa', label: 'Saturday' },
  { key: 'Sun', short: 'Su', label: 'Sunday' }
]
const rowDays = (r: Row) => WEEKDAYS.filter(d => value(r, d.key.toLowerCase() + 'Day').trim()).map(d => d.key)
// Mirrors SectionDetails(row:) in Sources/ClasswiseCore/Models.swift.
export function sectionDetails(row: Row): SectionDetails {
  const count = (key: string) => { const raw = value(row, key).trim(); return /^[-+]?\d+$/.test(raw) ? Number(raw) : undefined }
  const seats = count('seatsAvail')
  return { seatsOpen: seats === undefined ? undefined : Math.max(0, seats), capacity: count('maxEnrl'), waitlistCount: count('waitCount'), waitlistCapacity: count('waitCapacity'), termPart: value(row, 'ptrmDesc').trim(), campus: value(row, 'campDesc').trim(), units: value(row, 'creditHrLow').trim() }
}
/** Readable place for one meeting. PCC's building field lists every building of the section ("Online ASYNCH,R"), and an unassigned room reads "Needs Assignment". */
export function place(building: string, room: string) {
  const parts = building.split(',').map(x => x.trim()).filter(Boolean), campus = parts.filter(x => !x.startsWith('Online'))
  const code = room.trim(), assigned = !code || code === 'Needs Assignment' ? '' : code
  if (!campus.length) return parts.some(x => /zoom/i.test(x)) ? 'Online (Zoom)' : parts.length ? 'Online' : assigned ? 'Room ' + assigned : ''
  const buildings = campus.join(' / ')
  return assigned ? `${buildings} ${assigned}` : `${buildings} · room TBA`
}
function meeting(r: Row) {
  if (value(r, 'schdCode') === 'OD') return ''
  const days = rowDays(r).join(', '), times = [value(r, 'beginTime'), value(r, 'endTime')].filter(Boolean).map(clock).join(' – ')
  const when = [days, times].filter(Boolean).join(' '), where = place(value(r, 'bldgDesc'), value(r, 'roomCode'))
  if (!when) {
    // A no-time row with no room is the online part of a hybrid class; with a room, the time is unannounced.
    const roomAssigned = !['', 'Needs Assignment'].includes(value(r, 'roomCode').trim())
    if (!roomAssigned && value(r, 'bldgDesc').includes('Online')) return 'Online, no set meeting time'
    return where ? 'Time TBA · ' + where : ''
  }
  return [when, where].filter(Boolean).join(' · ')
}
export function professors(rows: Row[], c: Course): Professor[] {
  const groups = new Map<string, Map<string, Row[]>>(), byCRN = new Map<string, Row[]>()
  for (const row of rows) {
    if (!sameCourse(c, value(row, 'subjCode') + value(row, 'courseNumbDisplay')) || ['R', 'X'].includes(value(row, 'fwSectOpenInd')) || !value(row, 'crn')) continue
    const name = value(row, 'pfaName').trim() || 'Instructor to be announced', crn = value(row, 'crn')
    const group = groups.get(name) ?? new Map<string, Row[]>(); group.set(crn, [...(group.get(crn) ?? []), row]); groups.set(name, group)
    byCRN.set(crn, [...(byCRN.get(crn) ?? []), row])
  }
  return [...groups].map(([name, records]): Professor => {
    const subjects = new Set([...records.values()].flat().map(r => value(r, 'subjDesc').trim()).filter(Boolean))
    return {
      id: fold(name), name, subject: c.subject, subjectDescription: subjects.size === 1 ? [...subjects][0] : '', state: 'pending', candidates: [],
      // Co-instructors keep every required meeting of their CRN.
      sections: [...records.keys()].map((crn): Section => {
        const meetings = byCRN.get(crn)!, first = meetings[0], formats = [...new Set(meetings.map(r => value(r, 'schdCode')).filter(Boolean))].sort()
        const scheduled = meetings.filter(r => value(r, 'schdCode') !== 'OD').map(rowDays)
        const days = WEEKDAYS.map(d => d.key).filter(d => scheduled.some(x => x.includes(d)))
        return { crn, title: value(first, 'courseTitle'), start: value(first, 'ptrmStartDate'), end: value(first, 'ptrmEndDate'), status: value(first, 'fwSectOpenInd'), formats,
          meetings: [...new Set(meetings.map(meeting).filter(Boolean))].sort(), days, unannouncedMeetings: scheduled.some(x => !x.length), details: sectionDetails(first) }
      }).sort((a, b) => a.crn.localeCompare(b.crn))
    }
  }).sort((a, b) => a.name.localeCompare(b.name))
}
export function delivery(section: Section) {
  const f = section.formats
  return f.length && f.every(x => x === 'OD') ? 'Online · no scheduled meetings' : f.includes('HY') ? 'Hybrid · campus meetings required' : f.length && f.every(x => ['OD', 'OL', 'OS', 'ON'].includes(x)) ? 'Online · scheduled meetings' : 'In person'
}
export const fullyOnline = (s: Section) => s.formats.length > 0 && s.formats.every(f => f === 'OD')
/** Short format label for tags: In person, Hybrid, Online · live or Online · async, or "Format not announced" without format codes. */
export function formatLabel(s: Section) {
  if (!s.formats.length) return 'Format not announced'
  if (fullyOnline(s)) return 'Online · async'
  if (s.formats.includes('HY')) return 'Hybrid'
  if (s.formats.length && s.formats.every(f => ['OD', 'OL', 'OS', 'ON'].includes(f))) return 'Online · live'
  return 'In person'
}
export const scheduleNotAnnounced = (s: Section) => !fullyOnline(s) && (!s.days?.length || !!s.unannouncedMeetings)
/** True when the section meets on every picked day (it may meet on other days too). Fully online sections always match; sections with no announced days never do. */
export function fits(s: Section, picked: readonly Weekday[]) {
  if (!picked.length || fullyOnline(s)) return true
  return !!s.days?.length && picked.every(d => s.days!.includes(d))
}
/** Professors with at least one section left by the filters, keeping only those sections. */
export function filterSections(list: Professor[], picked: readonly Weekday[], onlineOnly: boolean) {
  return list.map(p => ({ ...p, sections: p.sections.filter(s => (!onlineOnly || fullyOnline(s)) && fits(s, picked)) })).filter(p => p.sections.length)
}
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
export function dateLabel(s: Section) {
  const label = (raw: string) => { const m = raw.slice(0, 10).match(/^(\d{4})-(\d{2})-(\d{2})$/); return m && Number(m[2]) >= 1 && Number(m[2]) <= 12 ? `${MONTHS[Number(m[2]) - 1]} ${Number(m[3])}, ${m[1]}` : 'Date unavailable' }
  return `${label(s.start)} – ${label(s.end)}`
}
/** PCC prints titles in capitals; show them in title case but keep Roman numerals. */
export function displayTitle(raw: string) {
  return raw.split(' ').filter(Boolean).map((word, i) => {
    const upper = word.toUpperCase()
    if (['I', 'II', 'III', 'IV', 'V', 'VI'].includes(upper)) return upper
    if (i > 0 && ['AND', 'OF', 'TO', 'THE', 'FOR', 'IN'].includes(upper)) return upper.toLowerCase()
    return word[0].toUpperCase() + word.slice(1).toLowerCase()
  }).join(' ')
}
const NAMED: Record<string, string> = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ', mdash: '—', ndash: '–', hellip: '…', rsquo: '’', lsquo: '‘', rdquo: '”', ldquo: '“' }
/** RMP comments can contain HTML character references such as `&#8212;` or `&amp;`; show the characters. */
export function visibleText(source: string) {
  return source.replace(/&(#[xX][0-9a-fA-F]+|#\d+|[a-zA-Z]+);/g, (whole, name: string) => {
    if (name[0] !== '#') return NAMED[name.toLowerCase()] ?? whole
    const code = name[1] === 'x' || name[1] === 'X' ? parseInt(name.slice(2), 16) : Number(name.slice(1))
    return Number.isInteger(code) && code >= 0 && code <= 0x10ffff && (code < 0xd800 || code > 0xdfff) ? String.fromCodePoint(code) : whole
  })
}
export function excerpt(review: Review) { const text = visibleText(review.text); return [...text].length > 500 ? [...text].slice(0, 500).join('') + '…' : text }
/** Review dates arrive as ISO strings or RMP's "2026-05-01 00:00:00 +0000 UTC". */
export function reviewTime(raw: string) {
  const direct = Date.parse(raw); if (Number.isFinite(direct)) return direct
  const m = raw.match(/^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}) ([+-]\d{2})(\d{2})(?: UTC)?$/)
  const parsed = m ? Date.parse(`${m[1]}T${m[2]}${m[3]}:${m[4]}`) : NaN
  return Number.isFinite(parsed) ? parsed : undefined
}
export const REVIEW_SORTS = [['recent', 'Latest first'], ['oldest', 'Oldest first'], ['highest', 'Highest rating'], ['lowest', 'Lowest rating'], ['highestDifficulty', 'Highest difficulty'], ['difficulty', 'Lowest difficulty']] as const
// Mirrors Ordering.reviews(_:by:): missing scores and dates sort last, then newest (or oldest), then ID.
export function orderReviews(reviews: Review[], by = 'recent') {
  const compare = (x: number | undefined, y: number | undefined, ascending: boolean) => x === undefined || !Number.isFinite(x) ? (y === undefined || !Number.isFinite(y) ? 0 : 1) : y === undefined || !Number.isFinite(y) ? -1 : x === y ? 0 : (ascending ? x - y : y - x)
  return reviews.map(review => ({ review, time: reviewTime(review.date) })).sort((a, b) => {
    const score = by === 'highest' || by === 'lowest' ? compare(a.review.rating, b.review.rating, by === 'lowest') : by === 'highestDifficulty' || by === 'difficulty' ? compare(a.review.difficulty, b.review.difficulty, by === 'difficulty') : 0
    return score || compare(a.time, b.time, by === 'oldest') || (a.review.id < b.review.id ? -1 : a.review.id > b.review.id ? 1 : 0)
  }).map(x => x.review)
}
export function filterReviews(profile: Profile, c: Course, filter: string) {
  const all = profile.coverage.all?.reviewIDs
  return orderReviews(profile.reviews.filter(r => filter === 'this' ? sameCourse(c, r.course) : filter === 'all' ? !all || all.includes(r.id) : r.course === filter)).slice(0, 50)
}
/** The filter a report opens on: this course when any downloaded review is about it, otherwise all courses. A profile without reviews keeps this course. */
export function preferredFilter(profile: Profile | undefined, c: Course) {
  if (!profile?.reviews.length) return 'this'
  return profile.reviews.some(r => sameCourse(c, r.course)) ? 'this' : 'all'
}
/** The source label "Find more" requests for a filter; all courses requests none. */
export const requestLabel = (c: Course, filter: string) => filter === 'all' ? undefined : filter === 'this' ? c.key : filter
export function filterFinished(profile: Profile, c: Course, filter: string) {
  const label = requestLabel(c, filter), coverage = profile.coverage[label === undefined ? 'all' : 'course|' + label]
  return !!coverage && (!coverage.hasNextPage || coverage.reviewIDs.length >= 50)
}
export const REVIEW_SITE = 'https://bye-before-you-enroll.pages.dev'
/** Opens the BYE website's review form, prefilled by name. The website resolves names to database IDs and only fills them in on an unambiguous match. */
export function reviewURL(professor: string, c: Course, site = REVIEW_SITE) {
  const name = professor.trim()
  if (!name) return undefined
  const url = new URL(site.replace(/\/+$/, '') + '/reviews/')
  url.searchParams.set('professor', name); url.searchParams.set('course', c.display)
  return url.toString()
}
export function orderProfessors(list: Professor[], by: string, c: Course) {
  const score = (p: Professor) => by === 'difficulty' ? -(p.profile?.difficulty ?? 100) : by === 'reviews' ? p.profile?.reviews.filter(r => sameCourse(c, r.course)).length ?? 0 : p.profile?.rating ?? -1
  return [...list].sort((a, b) => Number(a.state === 'unavailable') - Number(b.state === 'unavailable') || score(b) - score(a) || (b.profile?.ratingCount ?? 0) - (a.profile?.ratingCount ?? 0) || a.name.localeCompare(b.name))
}
