import { setTimeout as delay } from 'node:timers/promises'
import type { Profile, Review, Row, Term } from '../shared/types'
import { eligible, suggestions } from '../shared/domain'
import { NETWORK_RETIRED_MESSAGE } from '../shared/features'
export class IdentityError extends Error { constructor() { super('The returned profile identity could not be verified. Choose a profile again.'); this.name = 'IdentityError' } }
export const check = (signal: AbortSignal) => signal.throwIfAborted()
const malformed = () => new Error('The source returned an unsupported response. Please try again later.')
export type Fetcher = typeof fetch
/** Used by the final, offline release: every request is refused before it leaves the app. */
export const offlineFetch: Fetcher = async () => { throw new Error(NETWORK_RETIRED_MESSAGE) }
export async function jsonResponse(response: Response, limit: number, signal: AbortSignal): Promise<any> {
  if (!response.body || !response.ok) throw new Error(`Source unavailable (HTTP ${response.status}). Please try again.`)
  const reader = response.body.getReader(), chunks: Uint8Array[] = []; let size = 0
  try {
    while (true) {
      check(signal); const { done, value } = await reader.read(); if (done) break
      size += value.length; if (size > limit) throw malformed(); chunks.push(value)
    }
    return JSON.parse(Buffer.concat(chunks).toString('utf8'))
  } finally { await reader.cancel().catch(() => {}) }
}
export class PCC {
  private entries = new Map<string, { rows: Row[]; time: number }>()
  private flights = new Map<string, Promise<Row[]>>()
  constructor(private request: Fetcher = fetch, private now = Date.now) {}
  private async get(path: string) {
    const signal = AbortSignal.timeout(35000)
    const response = await this.request('https://prod-apiweb.pasadena.edu/api/' + path, { signal, redirect: 'error', credentials: 'omit' })
    return jsonResponse(response, 32 * 1024 * 1024, signal)
  }
  async terms(): Promise<Term[]> {
    const result = await this.get('getClassScheduleTerms')
    if (!Array.isArray(result)) throw malformed()
    return result.filter(x => x.termDisplayControl === 'Y' && /^\d{6}$/.test(x.termCode) && typeof x.termName === 'string').sort((a, b) => b.termCode.localeCompare(a.termCode))
  }
  async schedule(term: string, force = false): Promise<Row[]> {
    if (!/^\d{6}$/.test(term)) throw new Error('Choose a published PCC semester.')
    const running = this.flights.get(term); if (running) return running
    const old = this.entries.get(term), age = this.now() - (old?.time ?? 0)
    if (!force && old && age >= 0 && age < 300000) return old.rows
    const flight = this.get('classSchedule/' + term).then(rows => {
      if (!Array.isArray(rows) || rows.some(r => !r || typeof r !== 'object')) throw malformed()
      this.entries.set(term, { rows, time: this.now() }); return rows
    }).finally(() => this.flights.delete(term))
    this.flights.set(term, flight); return flight
  }
  async suggest(term: string, query: string) { return suggestions(query, await this.schedule(term)) }
}
export function retryAfter(value: string | null, now = Date.now()): number | undefined {
  if (value === null) return undefined
  const seconds = Number(value)
  if (value.trim() && Number.isFinite(seconds)) return Math.max(0, seconds * 1000)
  const date = Date.parse(value); return Number.isFinite(date) ? Math.max(0, date - now) : undefined
}
export class Transport {
  private active = 0; private nextStart = 0; private cooldown = 0
  constructor(private request: Fetcher = fetch, private spacing = 100, private retryDelay = 500) {}
  private async acquire(signal: AbortSignal) {
    while (this.active >= 2) await delay(10, undefined, { signal })
    check(signal); this.active++
    try {
      const start = Math.max(Date.now(), this.nextStart); this.nextStart = start + this.spacing
      await delay(Math.max(0, start - Date.now()), undefined, { signal })
      while (this.cooldown > Date.now()) await delay(this.cooldown - Date.now(), undefined, { signal })
      check(signal)
    } catch (e) { this.active--; throw e }
  }
  async send(query: string, variables: object, signal: AbortSignal): Promise<any> {
    for (let attempt = 0; attempt < 3; attempt++) {
      await this.acquire(signal)
      let wait: number | undefined
      try {
        const timeout = AbortSignal.any([signal, AbortSignal.timeout(25000)]), started = Date.now()
        // A separate header deadline matches the request timeout; the body keeps the total deadline.
        const headerSignal = AbortSignal.any([timeout, AbortSignal.timeout(15000)])
        const response = await this.request('https://www.ratemyprofessors.com/graphql', {
          method: 'POST', body: JSON.stringify({ query, variables }), signal: headerSignal,
          headers: { Accept: 'application/json', 'Content-Type': 'application/json', 'User-Agent': 'BYE-CrossPlatform/0.1' }, redirect: 'error', credentials: 'omit', cache: 'no-store'
        })
        check(signal)
        if (response.ok) {
          const envelope = await jsonResponse(response, 4 * 1024 * 1024, AbortSignal.any([signal, AbortSignal.timeout(Math.max(1, 25000 - (Date.now() - started)))]))
          if (!envelope?.data || (envelope.errors && (!Array.isArray(envelope.errors) || envelope.errors.length))) throw malformed()
          return envelope.data
        }
        await response.body?.cancel()
        if (attempt === 2 || ![429, 500, 502, 503, 504].includes(response.status)) throw new Error(response.status === 429 ? 'RMP is limiting requests. Try again later.' : `RMP is unavailable (HTTP ${response.status}). Try again.`)
        wait = retryAfter(response.headers.get('retry-after')) ?? this.retryDelay * 2 ** attempt
        if (wait > 30000) throw new Error('RMP requested a longer cooldown. Try again later.')
        this.cooldown = Math.max(this.cooldown, Date.now() + wait)
      } catch (error) {
        check(signal)
        const retryable = error instanceof TypeError || (error instanceof Error && ['TimeoutError', 'AbortError'].includes(error.name))
        if (attempt === 2 || !retryable) throw error
        wait = this.retryDelay * 2 ** attempt
      } finally { this.active-- }
      await delay(wait ?? 0, undefined, { signal })
    }
    throw new Error('Could not connect to RMP.')
  }
}
// Query design adapted from Amaan's MIT client; see bundled THIRD_PARTY_NOTICES.
const fields = 'id legacyId firstName lastName department school { id legacyId name }'
const searchQuery = `query BYESearch($query: TeacherSearchQuery!, $count: Int!, $cursor: String) { search: newSearch { teachers(query: $query, first: $count, after: $cursor) { edges { node { ${fields} } } pageInfo { hasNextPage endCursor } } } }`
const profileQuery = `query BYEProfile($id: ID!, $count: Int!, $cursor: String, $courseFilter: String) { node(id: $id) { ... on Teacher { ${fields} avgRating avgDifficulty numRatings wouldTakeAgainPercent courseCodes { courseName courseCount } ratings(first: $count, after: $cursor, courseFilter: $courseFilter) { edges { node { id comment helpfulRating difficultyRating date class isForOnlineClass } } pageInfo { hasNextPage endCursor } } } } }`
export function numericID(global: unknown, legacy: unknown, kind: string): string {
  let decoded: string | undefined
  if (global != null) {
    if (typeof global !== 'string') throw new IdentityError()
    const text = Buffer.from(global, 'base64').toString('utf8'), prefix = kind + '-'
    if (!text.startsWith(prefix) || !/^[1-9]\d*$/.test(text.slice(prefix.length))) throw new IdentityError()
    decoded = text.slice(prefix.length)
  }
  if (legacy != null) {
    if (!Number.isSafeInteger(legacy) || Number(legacy) <= 0 || (decoded && decoded !== String(legacy))) throw new IdentityError()
    return String(legacy)
  }
  if (!decoded) throw new IdentityError(); return decoded
}
const score = (n: any) => typeof n === 'number' && Number.isFinite(n) && n >= 1 && n <= 5 ? n : undefined
export function profileFrom(t: any): Profile {
  if (!t || typeof t.firstName !== 'string' || !t.firstName.trim() || typeof t.lastName !== 'string' || !t.lastName.trim() || typeof t.school?.name !== 'string') throw new IdentityError()
  if (t.courseCodes != null && !Array.isArray(t.courseCodes)) throw malformed()
  return { id: numericID(t.id, t.legacyId, 'Teacher'), firstName: t.firstName, lastName: t.lastName, school: t.school.name,
    schoolID: Number(numericID(t.school.id, t.school.legacyId, 'School')), department: typeof t.department === 'string' ? t.department : '',
    rating: score(t.avgRating), difficulty: score(t.avgDifficulty), ratingCount: Number.isInteger(t.numRatings) && t.numRatings >= 0 ? t.numRatings : undefined,
    wouldTakeAgain: typeof t.wouldTakeAgainPercent === 'number' && t.wouldTakeAgainPercent >= 0 && t.wouldTakeAgainPercent <= 100 ? t.wouldTakeAgainPercent : undefined,
    courseCounts: (t.courseCodes ?? []).map((x: any) => { if (typeof x.courseName !== 'string') throw malformed(); return { label: x.courseName, count: Number.isInteger(x.courseCount) && x.courseCount >= 0 ? x.courseCount : undefined } }), reviews: [], coverage: {} }
}
function connection(c: any, count: number, cursor?: string) {
  if (!Array.isArray(c?.edges) || c.edges.length > count || typeof c.pageInfo?.hasNextPage !== 'boolean') throw malformed()
  const { hasNextPage, endCursor } = c.pageInfo
  if (hasNextPage && (typeof endCursor !== 'string' || !endCursor || endCursor === cursor)) throw new Error('RMP pagination stopped progressing. Retrieved reviews remain available.')
  return { hasNextPage, nextCursor: typeof endCursor === 'string' ? endCursor : undefined }
}
export interface ReviewPage { profile: Profile; ids: string[]; hasNextPage: boolean; nextCursor?: string }
export class RMP {
  constructor(private transport = new Transport()) {}
  async search(name: string, signal: AbortSignal, cursor?: string) {
    const data = await this.transport.send(searchQuery, { query: { text: name, schoolID: Buffer.from('School-2649').toString('base64') }, count: 20, cursor: cursor ?? null }, signal)
    const c = data.search?.teachers, info = connection(c, 20, cursor)
    return { profiles: c.edges.map((e: any) => profileFrom(e.node)) as Profile[], ...info }
  }
  async candidates(name: string, signal: AbortSignal, discoverAll = false) {
    let found: Profile[] = [], cursor: string | undefined; const visited = new Set<string>()
    for (let i = 0; i < 4; i++) {
      try {
        const page = await this.search(name, signal, cursor); check(signal)
        found = eligible(name, [...found, ...page.profiles])
        if (found.length && !discoverAll) return found
        if (!page.hasNextPage) break
        if (visited.has(page.nextCursor!)) throw malformed()
        visited.add(page.nextCursor!); cursor = page.nextCursor
      } catch (error) { check(signal); if (found.length) return found; throw error }
    }
    return found
  }
  async page(id: string, count: number, signal: AbortSignal, cursor?: string, filter?: string): Promise<ReviewPage> {
    if (!/^[1-9]\d*$/.test(id)) throw new IdentityError()
    count = Math.min(50, Math.max(1, count))
    const data = await this.transport.send(profileQuery, { id: Buffer.from('Teacher-' + id).toString('base64'), count, cursor: cursor ?? null, courseFilter: filter ?? null }, signal)
    const p = profileFrom(data.node); if (p.id !== id) throw new IdentityError()
    const c = data.node.ratings, info = connection(c, count, cursor), ids: string[] = []
    p.reviews = c.edges.flatMap((edge: any): Review[] => {
      const r = edge.node; if (typeof r?.id !== 'string' || !r.id || ids.includes(r.id)) throw malformed(); ids.push(r.id)
      if (r.comment == null || r.comment === '') return []
      if (typeof r.comment !== 'string') throw malformed()
      if (!r.comment.trim()) return []
      return [{ id: r.id, text: r.comment, course: typeof r.class === 'string' ? r.class : '', date: typeof r.date === 'string' ? r.date : '', rating: score(r.helpfulRating), difficulty: score(r.difficultyRating), online: typeof r.isForOnlineClass === 'boolean' ? r.isForOnlineClass : undefined }]
    })
    return { profile: p, ids, ...info }
  }
}
