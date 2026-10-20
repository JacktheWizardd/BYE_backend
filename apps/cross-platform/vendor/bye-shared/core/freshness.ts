import type { Section, SourceMeta } from './types'

// Web sources retain their five-minute policy. The schedule service supplies its own deadline.
export const availabilityDeadline = (source: SourceMeta) => source.expiresAt ?? source.retrievedAt + 300_000
export function staleSource(source: SourceMeta | undefined, now = Date.now()) {
  return !!source && (source.stale || !Number.isFinite(source.retrievedAt) || now < source.retrievedAt || now >= availabilityDeadline(source))
}
export function openSeatTotal(sections: Section[], now = Date.now()) {
  const unique = [...new Map(sections.map(s => [s.crn, s])).values()]
  // A partial sum would look like a complete count; keep unavailable totals unknown.
  if (!unique.length || unique.some(s => staleSource(s.source, now) || s.details?.seatsOpen === undefined)) return undefined
  return unique.reduce((n, s) => n + s.details!.seatsOpen!, 0)
}
