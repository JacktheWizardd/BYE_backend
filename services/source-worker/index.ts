import { PCC, RMP } from '../web-api/src/network'
import { SourceService, errorResponse, type Cache, type CacheEntry, type SourceConfig } from '../web-api/src/service'
import type { ApiResults } from '@bye/contracts/api'

interface Env { SOURCES: DurableObjectNamespace; LIVE_APP_ENABLED?: string; RMP_AUTHORIZED?: string; RMP_PERMISSION_REF?: string; RMP_CACHE_SECONDS?: string; CACHE_EPOCH?: string }
/** Chunk serialized entries so a complete semester never occupies one storage value. */
export class DurableCache implements Cache {
  constructor(private storage: DurableObjectStorage) {}
  async get<T>(key: string): Promise<CacheEntry<T> | undefined> {
    const metadata = await this.storage.get<{ count: number; generation: string; expires: number }>('entry:' + key)
    if (!metadata) return
    if (metadata.expires <= Date.now()) { await this.delete(key); return }
    const parts = new Map<string, string>()
    for (let start = 0; start < metadata.count; start += 128) {
      const batch = await this.storage.get<string>(Array.from({ length: Math.min(128, metadata.count - start) }, (_, i) => `chunk:${key}:${metadata.generation}:${start + i}`))
      for (const [k, v] of batch) parts.set(k, v)
    }
    const chunks = Array.from({ length: metadata.count }, (_, i) => parts.get(`chunk:${key}:${metadata.generation}:${i}`))
    if (chunks.some(x => x === undefined)) return
    try { return JSON.parse(chunks.join('')) } catch { await this.delete(key); return }
  }
  async put<T>(key: string, value: CacheEntry<T>) {
    const text = JSON.stringify(value), generation = crypto.randomUUID(), size = 24_000, count = Math.ceil(text.length / size)
    if (text.length > 32 * 1024 * 1024) throw new Error('Cache entry too large')
    await this.storage.transaction(async tx => {
      const old = await tx.get<{ count: number; generation: string }>('entry:' + key)
      if (old) for (let i = 0; i < old.count; i++) await tx.delete(`chunk:${key}:${old.generation}:${i}`)
      for (let i = 0; i < count; i++) await tx.put(`chunk:${key}:${generation}:${i}`, text.slice(i * size, (i + 1) * size))
      await tx.put('entry:' + key, { count, generation, expires: value.expiresAt ?? value.time + 86_400_000 })
    })
  }
  async purgeExpired() {
    let cursor: string | undefined
    do {
      const entries = await this.storage.list<{ expires: number }>({ prefix: 'entry:', limit: 128, ...(cursor ? { startAfter: cursor } : {}) })
      for (const [key, value] of entries) if (value.expires <= Date.now()) await this.delete(key.slice(6))
      cursor = entries.size === 128 ? [...entries.keys()].at(-1) : undefined
    } while (cursor)
  }
  async delete(key: string) {
    await this.storage.transaction(async tx => {
      const old = await tx.get<{ count: number; generation: string }>('entry:' + key)
      if (old) for (let i = 0; i < old.count; i++) await tx.delete(`chunk:${key}:${old.generation}:${i}`)
      await tx.delete('entry:' + key)
    })
  }
}
export class Sources {
  private service: SourceService
  private cache: DurableCache
  constructor(private state: DurableObjectState, env: Env) {
    const seconds = Number(env.RMP_CACHE_SECONDS ?? 0)
    const config: SourceConfig = { enabled: env.LIVE_APP_ENABLED === 'true', rmpAuthorized: env.RMP_AUTHORIZED === 'true', rmpPermissionRef: env.RMP_PERMISSION_REF ?? '', rmpCacheSeconds: Number.isFinite(seconds) && seconds >= 0 ? seconds : 0 }
    this.cache = new DurableCache(state.storage)
    this.service = new SourceService(new PCC(), new RMP(), this.cache, config)
    state.blockConcurrencyWhile(async () => { const epoch = env.CACHE_EPOCH ?? 'v1'; if (await state.storage.get('cache-epoch') !== epoch) { await state.storage.deleteAll(); await state.storage.put('cache-epoch', epoch) }; if (await state.storage.getAlarm() === null) await state.storage.setAlarm(Date.now() + 3_600_000) })
  }
  async alarm() { await this.cache.purgeExpired(); await this.state.storage.setAlarm(Date.now() + 3_600_000) }
  async fetch(request: Request) {
    const started = Date.now(), url = new URL(request.url), kind = url.pathname.split('/').at(-1)!
    if (kind === 'status') return Response.json({ enabled: this.service.config.enabled, rmpConfigured: this.service.config.rmpAuthorized && !!this.service.config.rmpPermissionRef.trim() }, { headers: { 'Cache-Control': 'no-store' } })
    try {
      if (!['terms', 'courses', 'sections', 'candidates', 'profile', 'reviews'].includes(kind)) return new Response('Not found', { status: 404 })
      const result = await this.service.operation(kind as keyof ApiResults, url.searchParams, request.headers.get('X-BYE-Client') ?? 'unknown')
      console.log(JSON.stringify({ operation: kind, status: 200, elapsedMs: Date.now() - started, stale: result.meta.stale, cacheStatus: result.meta.cacheStatus, ageMs: Date.now() - result.meta.retrievedAt }))
      return Response.json(result, { headers: { 'Cache-Control': 'no-store' } })
    } catch (error) {
      const response = errorResponse(error)
      console.log(JSON.stringify({ operation: kind, status: response.status, elapsedMs: Date.now() - started }))
      return response
    }
  }
}
// No public upstream proxy: only the bound Durable Object accepts source operations.
export default { fetch() { return new Response('Not found', { status: 404 }) } }
