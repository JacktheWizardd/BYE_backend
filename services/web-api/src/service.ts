import { course, eligible, identity, normalizedName, professors, resolve, suggestions } from '@bye/source-domain'
import type { Profile, Row, Term } from '@bye/contracts/types'
import type { ApiResults, Envelope } from '@bye/contracts/api'
import { UpstreamLimitError, IdentityError, type PCC, type RMP } from './network'

export class ApiError extends Error {
  constructor(readonly status: number, readonly code: string, message: string, readonly retryAfter?: number) { super(message) }
}
export interface CacheEntry<T> { data: T; time: number; expiresAt?: number }
export interface Cache { get<T>(key: string): Promise<CacheEntry<T> | undefined>; put<T>(key: string, value: CacheEntry<T>): Promise<void>; delete(key: string): Promise<void> }
export interface SourceConfig { enabled: boolean; rmpAuthorized: boolean; rmpPermissionRef: string; rmpCacheSeconds: number }
export const SCHEDULE_TTL = 300_000
const STALE_LIMIT = 24 * 60 * 60_000
export const unavailable = () => new ApiError(503, 'LIVE_DISABLED', 'The live beta is not available yet. You can use the sample demo.', 60)
const input = (value: string | null, max: number, label: string) => { if (!value || value.length > max || /[\x00-\x1f]/.test(value)) throw new ApiError(400, 'INVALID_INPUT', `Choose a valid ${label}.`); return value }

/** One instance is owned by a single PCC Durable Object, not by each visitor. */
export class SourceService {
  private flights = new Map<string, Promise<Envelope<unknown>>>()
  private requests = new Map<string, { count: number; until: number }>()
  constructor(private pcc: Pick<PCC, 'terms' | 'schedule'>, private rmp: Pick<RMP, 'candidates' | 'page'>, private cache: Cache, readonly config: SourceConfig, private now = Date.now) {}
  private limit(client: string) {
    const now = this.now()
    for (const [key, value] of this.requests) if (value.until <= now) this.requests.delete(key)
    const old = this.requests.get(client)
    if (!old && this.requests.size >= 2000) throw new ApiError(503, 'BUSY', 'BYE is busy. Try again shortly.', 30)
    const bucket = old ?? { count: 0, until: now + 60_000 }
    if (++bucket.count > 120) throw new ApiError(429, 'RATE_LIMITED', 'Too many requests. Try again in a minute.', Math.max(1, Math.ceil((bucket.until - now) / 1000)))
    this.requests.set(client, bucket)
  }
  private async cached<T>(key: string, source: 'pcc' | 'rmp', ttl: number, load: () => Promise<T>, allowStale = false): Promise<Envelope<T>> {
    const old = await this.cache.get<T>(key), age = old ? this.now() - old.time : Infinity
    if (old && age >= 0 && age < ttl) return { data: old.data, meta: { source, retrievedAt: old.time, stale: false, cacheStatus: 'hit' as const } }
    const running = this.flights.get(key)
    if (running) return running as Promise<Envelope<T>>
    if (this.flights.size >= 40) throw new ApiError(503, 'BUSY', 'BYE is busy. Try again shortly.', 10)
    const flight = (async () => {
      try {
        const data = await load(), time = this.now()
        if (ttl > 0) await this.cache.put(key, { data, time, expiresAt: time + (allowStale ? STALE_LIMIT : ttl) })
        return { data, meta: { source, retrievedAt: time, stale: false, cacheStatus: 'miss' as const } }
      } catch (error) {
        if (allowStale && old && age >= 0 && age < STALE_LIMIT) return { data: old.data, meta: { source, retrievedAt: old.time, stale: true, cacheStatus: 'stale' as const }, warning: 'PCC could not be refreshed. Showing an older schedule; seat counts are hidden.' }
        throw error
      } finally { this.flights.delete(key) }
    })()
    this.flights.set(key, flight as Promise<Envelope<unknown>>)
    return flight
  }
  private terms() { return this.cached('terms', 'pcc', 6 * 60 * 60_000, () => this.pcc.terms(), true) }
  private async schedule(term: string) {
    if (!/^\d{6}$/.test(term)) throw new ApiError(400, 'INVALID_TERM', 'Choose a published PCC semester.')
    const published = await this.terms()
    if (!published.data.some(t => t.termCode === term)) throw new ApiError(400, 'INVALID_TERM', 'Choose a published PCC semester.')
    return this.cached<Row[]>('schedule:' + term, 'pcc', SCHEDULE_TTL, () => this.pcc.schedule(term, true), true)
  }
  private requireRMP() {
    if (!this.config.rmpAuthorized || !this.config.rmpPermissionRef.trim()) throw new ApiError(503, 'RMP_NOT_AUTHORIZED', 'Ratings and reviews are awaiting authorized source access.', 60)
  }
  async operation<K extends keyof ApiResults>(kind: K, params: URLSearchParams, client: string): Promise<Envelope<ApiResults[K]>> {
    if (!this.config.enabled) throw unavailable()
    this.limit(client)
    if (kind === 'terms') return this.terms() as Promise<Envelope<ApiResults[K]>>
    const term = input(params.get('term'), 6, 'semester'), schedule = await this.schedule(term)
    if (kind === 'courses') {
      const query = input(params.get('query'), 120, 'course search')
      return { ...schedule, data: suggestions(query, schedule.data) } as Envelope<ApiResults[K]>
    }
    const query = input(params.get('course') ?? params.get('query'), 24, 'course')
    let c
    try { c = resolve(query, schedule.data) } catch (e) { throw new ApiError(400, 'INVALID_COURSE', e instanceof Error ? e.message : 'Choose a course.') }
    const list = professors(schedule.data, c)
    for (const p of list) for (const s of p.sections) {
      s.source = schedule.meta
      if (schedule.meta.stale && s.details) { s.details.seatsOpen = undefined; s.details.capacity = undefined; s.details.waitlistCount = undefined; s.details.waitlistCapacity = undefined }
    }
    if (kind === 'sections') return { ...schedule, data: { course: c, professors: list } } as Envelope<ApiResults[K]>
    this.requireRMP()
    const instructor = input(params.get('instructor'), 160, 'PCC instructor')
    const p = list.find(p => normalizedName(p.name) === normalizedName(instructor))
    if (!p || ['staff', 'tba', 'instructor to be announced'].includes(p.name.toLowerCase())) throw new ApiError(400, 'INVALID_INSTRUCTOR', 'Choose an instructor from this PCC course.')
    const ttl = Math.max(0, Math.min(this.config.rmpCacheSeconds, 86_400)) * 1000
    if (kind === 'candidates') {
      return await this.cached(`candidates:${normalizedName(p.name)}`, 'rmp', ttl, async () => eligible(p.name, await this.rmp.candidates(p.name, AbortSignal.timeout(60_000), true))) as Envelope<ApiResults[K]>
    }
    const id = input(params.get('id'), 16, 'profile')
    if (!/^[1-9]\d*$/.test(id)) throw new ApiError(400, 'INVALID_PROFILE', 'Choose a valid profile.')
    const filter = params.get('filter') ?? undefined, cursor = params.get('cursor') ?? undefined
    if (filter !== undefined) { input(filter, 32, 'review course'); try { course(filter) } catch { throw new ApiError(400, 'INVALID_FILTER', 'Choose a valid review course.') } }
    if (cursor !== undefined) input(cursor, 512, 'review cursor')
    const remainingRaw = params.get('remaining') ?? '20'
    if (!/^\d{1,2}$/.test(remainingRaw)) throw new ApiError(400, 'INVALID_PAGE', 'Choose a valid review page size.')
    const remaining = Number(remainingRaw)
    if (remaining < 1 || remaining > 50) throw new ApiError(400, 'INVALID_PAGE', 'Choose a valid review page size.')
    const count = kind === 'profile' ? 3 : Math.min(20, remaining)
    const key = JSON.stringify(['page', normalizedName(p.name), id, count, cursor ?? '', filter ?? ''])
    const result = await this.cached(key, 'rmp', ttl, async () => {
      const page = await this.rmp.page(id, count, AbortSignal.timeout(60_000), cursor, filter)
      if (page.profile.id !== id || !identity(p.name, page.profile)) throw new IdentityError()
      return page
    })
    if (!identity(p.name, result.data.profile) || result.data.profile.id !== id) { await this.cache.delete(key); throw new IdentityError() }
    result.data.profile.source = result.meta
    return result as Envelope<ApiResults[K]>
  }
}

export function errorResponse(error: unknown): Response {
  const known = error instanceof ApiError ? error : error instanceof UpstreamLimitError ? new ApiError(429, 'SOURCE_RATE_LIMITED', error.message, error.retryAfterSeconds) : error instanceof IdentityError ? new ApiError(409, 'IDENTITY_MISMATCH', error.message) : new ApiError(503, 'SOURCE_UNAVAILABLE', 'The source could not be retrieved. Please try again.', 15)
  return Response.json({ error: { code: known.code, message: known.message, retryable: known.status >= 500 || known.status === 429, retryAfter: known.retryAfter } }, { status: known.status, headers: { 'Cache-Control': 'no-store', ...(known.retryAfter ? { 'Retry-After': String(known.retryAfter) } : {}) } })
}
