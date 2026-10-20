import { setTimeout as delay } from 'node:timers/promises'
import { jsonResponse, retryAfter } from './network'

export class ReadError extends Error {
  constructor(readonly code: string, message: string, readonly retryMs = 0) { super(message) }
}
export interface CachedResponse { body: any; etag?: string }
/** Fixed-origin, GET-only transport. No tokens, URLs or response text enter diagnostics. */
export class ReadAPI {
  private tail: Promise<unknown> = Promise.resolve()
  private cooldown = 0
  constructor(readonly base: string, private key = '', private request: typeof fetch = fetch) {}
  async get(route: string, signal: AbortSignal, previous?: CachedResponse): Promise<CachedResponse> {
    const before = this.tail
    let release!: () => void
    this.tail = new Promise<void>(r => { release = r })
    try {
      await before.catch(() => {}); signal.throwIfAborted()
      if (this.cooldown > Date.now()) throw new ReadError('RATE_LIMITED', 'BYE is busy. Please wait before retrying.', this.cooldown - Date.now())
      for (let attempt = 0; attempt < 2; attempt++) {
        const deadline = AbortSignal.any([signal, AbortSignal.timeout(20_000)])
        try {
          const response = await this.request(this.base + route, { method: 'GET', signal: deadline, redirect: 'error', credentials: 'omit', cache: 'no-store',
            headers: { Accept: 'application/json', ...(this.key ? { apikey: this.key } : {}), ...(previous?.etag ? { 'If-None-Match': previous.etag } : {}) } })
          if (response.status === 304) { await response.body?.cancel(); if (!previous) throw new ReadError('INVALID_RESPONSE', 'BYE returned an unsupported response.'); return previous }
          if (!response.ok) {
            await response.body?.cancel()
            if (response.status === 429) { const ms = Math.max(1000, retryAfter(response.headers.get('retry-after')) ?? 60_000); this.cooldown = Date.now() + ms; throw new ReadError('RATE_LIMITED', 'BYE is busy. Please wait before retrying.', ms) }
            if (response.status >= 500 && attempt === 0) { await delay(500, undefined, { signal }); continue }
            throw new ReadError(response.status === 401 ? 'UNAUTHORIZED' : response.status === 404 ? 'NOT_FOUND' : 'UNAVAILABLE', response.status === 401 ? 'The BYE application key is unavailable or no longer active. Update the app configuration.' : response.status === 404 ? 'This course or semester is not available in BYE.' : 'BYE is temporarily unavailable. Try again shortly.')
          }
          const body = await jsonResponse(response, 8 * 1024 * 1024, deadline)
          if (!body || typeof body !== 'object' || !('data' in body)) throw new ReadError('INVALID_RESPONSE', 'BYE returned an unsupported response.')
          return { body, etag: response.headers.get('etag') ?? undefined }
        } catch (e) {
          signal.throwIfAborted()
          if (e instanceof ReadError) throw e
          if (attempt === 0 && (e instanceof TypeError || (e instanceof Error && ['TimeoutError', 'AbortError'].includes(e.name)))) { await delay(500, undefined, { signal }); continue }
          throw new ReadError('NETWORK_ERROR', 'Could not connect to BYE. Check your connection and try again.')
        }
      }
      throw new ReadError('UNAVAILABLE', 'BYE is temporarily unavailable.')
    } finally { release() }
  }
}
