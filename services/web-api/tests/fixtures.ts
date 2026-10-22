import { setTimeout as delay } from 'node:timers/promises'
import { SourceService, SCHEDULE_TTL, type Cache, type CacheEntry, type SourceConfig } from '../src/service'
import { IdentityError } from '../src/network'
import type { Profile } from '@bye/contracts/types'
import { demoData, demoSeats, FALL } from './source-data'
import { normalizedName } from '@bye/source-domain'

export class MemoryCache implements Cache {
  entries = new Map<string, CacheEntry<unknown>>()
  async get<T>(key: string) { return structuredClone(this.entries.get(key)) as CacheEntry<T> | undefined }
  async put<T>(key: string, value: CacheEntry<T>) { this.entries.set(key, structuredClone(value)) }
  async delete(key: string) { this.entries.delete(key) }
}
const config: SourceConfig = { enabled: true, rmpAuthorized: true, rmpPermissionRef: 'fictional-test-only', rmpCacheSeconds: 60 }
export function setup(overrides: Partial<SourceConfig> = {}) {
  let now = Date.now(), schedules = 0, profiles = 0, fail = false
  const cache = new MemoryCache()
  const rmp = {
    candidates: async (name: string) => demoData.profiles.filter(p => normalizedName(p.firstName + ' ' + p.lastName) === normalizedName(name)).map(p => ({ ...structuredClone(p), reviews: [] })),
    page: async (id: string, count: number, _signal: AbortSignal, cursor?: string, filter?: string) => {
      profiles++; await delay(1)
      const p = structuredClone(demoData.profiles.find(p => p.id === id)!)
      if (!p) throw new IdentityError()
      const rows = p.reviews.filter(r => !filter || r.course === filter), offset = Number(cursor ?? 0)
      p.reviews = rows.slice(offset, offset + count); p.coverage = {}
      return { profile: p, ids: p.reviews.map(r => r.id), hasNextPage: offset + count < rows.length, nextCursor: offset + count < rows.length ? String(offset + count) : undefined }
    }
  }
  const pcc = { terms: async () => structuredClone(demoData.terms), schedule: async () => { schedules++; await delay(2); if (fail) throw new Error('PCC offline'); return structuredClone(demoData.schedules[FALL.termCode]).map(row => { const seats = demoSeats[String(row.crn)]; return { ...row, ...(seats ? { seatsAvail: seats.open, maxEnrl: seats.capacity, waitCount: seats.waitlist, waitCapacity: seats.waitCapacity, ptrmDesc: 'Full term', campDesc: 'Main campus', creditHrLow: '3' } : {}) } }) } }
  return { service: new SourceService(pcc, rmp, cache, { ...config, ...overrides }, () => now), cache, rmp, pcc, counts: () => ({ schedules, profiles }), advance: (ms: number) => { now += ms }, fail: () => { fail = true } }
}
