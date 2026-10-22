import type { Course, Profile, Professor, Review, Row, Section, SectionDetails, Suggestion, Weekday } from '@bye/contracts/types'
export const fold = (s: string) => s.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase()
export function course(input: string): Course {
  const match = input.trim().toUpperCase().match(/^([A-Z]{2,8})\s*([A-Z]?\d{1,4}[A-Z]*)$/)
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
export const WEEKDAYS: readonly { key: Weekday; short: string; label: string }[] = [
  { key: 'Mon', short: 'M', label: 'Monday' }, { key: 'Tue', short: 'T', label: 'Tuesday' }, { key: 'Wed', short: 'W', label: 'Wednesday' },
  { key: 'Thu', short: 'Th', label: 'Thursday' }, { key: 'Fri', short: 'F', label: 'Friday' }, { key: 'Sat', short: 'Sa', label: 'Saturday' },
  { key: 'Sun', short: 'Su', label: 'Sunday' }
]
export function sectionDetails(row: Row): SectionDetails {
  const count = (key: string) => { const raw = value(row, key).trim(); if (!/^[-+]?\d+$/.test(raw)) return undefined; const n = Number(raw); return Number.isSafeInteger(n) ? Math.max(0, n) : undefined }
  return { seatsOpen: count('seatsAvail'), capacity: count('maxEnrl'), waitlistCount: count('waitCount'), waitlistCapacity: count('waitCapacity'), termPart: value(row, 'ptrmDesc').trim(), campus: value(row, 'campDesc').trim(), units: value(row, 'creditHrLow').trim() }
}
export function professors(rows: Row[], c: Course): Professor[] {
  const groups = new Map<string, Map<string, Row[]>>()
  for (const row of rows) {
    if (!sameCourse(c, value(row, 'subjCode') + value(row, 'courseNumbDisplay')) || ['R', 'X'].includes(value(row, 'fwSectOpenInd')) || !value(row, 'crn')) continue
    const name = value(row, 'pfaName').trim() || 'Instructor to be announced', crn = value(row, 'crn')
    const group = groups.get(name) ?? new Map<string, Row[]>(); group.set(crn, [...(group.get(crn) ?? []), row]); groups.set(name, group)
  }
  return [...groups].map(([name, records]): Professor => ({
    id: fold(name), name, subject: c.subject, state: 'pending', candidates: [],
    sections: [...records].map(([crn, meetings]): Section => {
      const first = meetings[0], formats = [...new Set(meetings.map(r => value(r, 'schdCode')).filter(Boolean))].sort()
      const descriptions = meetings.filter(r => value(r, 'schdCode') !== 'OD').map(r => {
        const days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'].filter(d => value(r, d + 'Day')).map(d => d[0].toUpperCase() + d.slice(1)).join(', ')
        return [days, [value(r, 'beginTime'), value(r, 'endTime')].filter(Boolean).map(clock).join(' – '), value(r, 'bldgDesc'), value(r, 'roomCode')].filter(Boolean).join(' ')
      }).filter(Boolean)
      return { crn, days: WEEKDAYS.map(d => d.key).filter(d => meetings.some(r => value(r, d.toLowerCase() + 'Day').trim() !== '')), details: sectionDetails(first), title: value(first, 'courseTitle'), start: value(first, 'ptrmStartDate'), end: value(first, 'ptrmEndDate'), status: value(first, 'fwSectOpenInd'), formats, meetings: [...new Set(descriptions)].sort() }
    }).sort((a, b) => a.crn.localeCompare(b.crn))
  })).sort((a, b) => a.name.localeCompare(b.name))
}
