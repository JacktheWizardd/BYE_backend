import type { Section } from '@shared/types'

// Mirrors Section.fits(availableDays:) and Section.formatLabel in Sources/ClasswiseCore/Models.swift.

export const WEEKDAYS = [
  { key: 'Mon', short: 'M', label: 'Monday' }, { key: 'Tue', short: 'T', label: 'Tuesday' }, { key: 'Wed', short: 'W', label: 'Wednesday' },
  { key: 'Thu', short: 'Th', label: 'Thursday' }, { key: 'Fri', short: 'F', label: 'Friday' }, { key: 'Sat', short: 'Sa', label: 'Saturday' },
  { key: 'Sun', short: 'Su', label: 'Sunday' }
] as const
export type Weekday = typeof WEEKDAYS[number]['key']

export const fullyOnline = (s: Section) => s.formats.length > 0 && s.formats.every(f => f === 'OD')

/** Days a section meets on, read from the shared domain's meeting descriptions ("Mon, Wed 8:00 AM – …"). */
export function meetingDays(s: Section): Set<Weekday> {
  const days = new Set<Weekday>()
  for (const meeting of s.meetings) for (const match of meeting.matchAll(/\b(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\b/g)) days.add(match[1] as Weekday)
  return days
}

/** True when the section meets on every picked day. Fully online sections always fit; unannounced days never do. */
export function fits(s: Section, picked: readonly Weekday[]): boolean {
  if (!picked.length || fullyOnline(s)) return true
  const days = meetingDays(s)
  return days.size > 0 && picked.every(d => days.has(d))
}

export function formatLabel(s: Section): string {
  if (fullyOnline(s)) return 'Online · async'
  if (s.formats.includes('HY')) return 'Hybrid'
  if (s.formats.length && s.formats.every(f => ['OD', 'OL', 'OS', 'ON'].includes(f))) return 'Online · live'
  return 'In person'
}

/** "SINGLE VARIABLE CALCULUS I" → "Single variable calculus I" */
export function titleCase(title: string): string {
  const words = title.trim().toLowerCase().split(/\s+/).map(w => /^[ivx]+$/.test(w) ? w.toUpperCase() : w)
  const text = words.join(' ')
  return text.charAt(0).toUpperCase() + text.slice(1)
}
