import { mkdir, readFile, rename, stat, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { randomUUID } from 'node:crypto'
import type { Course, Professor, Section, SourceMeta, Suggestion, Term, Weekday } from '../shared/types'
import { ReadAPI, ReadError, type CachedResponse } from './read-api'

export const SCHEDULE_URL = 'https://nahvhampsxtasfwvvfei.supabase.co/functions/v1/bye-schedule-api'
export interface ScheduleResult { course: Course; professors: Professor[]; source?: SourceMeta; catalogVersion?: string; offline?: boolean }
export interface ScheduleProvider {
  terms(signal?: AbortSignal): Promise<Term[]>
  suggest(term: string, query: string): Promise<Suggestion[]>
  search(term: string, query: string, refresh: boolean, signal: AbortSignal): Promise<ScheduleResult>
  update?(term: string, current: ScheduleResult, crns: string[], signal: AbortSignal): Promise<ScheduleResult>
}
interface WireCourse { key: string; subject: string; number: string; title: string }
export interface WireMeeting { startDate: string | null; endDate: string | null; days: string[]; beginTime: string | null; endTime: string | null; formatCode: string | null; formatDescription: string | null; campus: string | null; building: string | null; room: string | null; sourceFields: Record<string, unknown> }
export interface WireSection { crn: string; courseKey: string; units: string | null; information: Record<string, unknown>; meetings: WireMeeting[]; instructors: { assignmentId: string; role: string; name: string | null }[]; availability: null | { statusCode: string | null; seatsAvailable: number | null; capacity: number | null; waitlistCount: number | null; waitlistCapacity: number | null } }
const normalized = (s: string) => s.toUpperCase().replace(/\s/g, '').replace(/\d+/, n => String(Number(n)))
const course = (c: WireCourse): Course => ({ subject: c.subject, number: c.number, key: c.subject + c.number, display: c.key, matchingKey: normalized(c.key) })
const invalid = () => new ReadError('INVALID_RESPONSE', 'BYE returned an unsupported schedule response.')
const text = (v: unknown): v is string => typeof v === 'string' && v.length <= 10000
const optionalText = (v: unknown) => v === null || text(v)
const days: Weekday[] = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
export function sourceMetadata(meta: any): SourceMeta {
  const time = typeof meta?.sourceCheckedAt === 'string' ? Date.parse(meta.sourceCheckedAt) : NaN
  return { source: 'pcc', retrievedAt: Number.isFinite(time) ? time : 0, expiresAt: Number.isFinite(time) ? time + 900_000 : 0, stale: meta?.stale !== false || !Number.isFinite(time) }
}
function validateCourses(data: unknown): WireCourse[] {
  if (!Array.isArray(data) || data.length > 10000 || data.some(c => !c || ![c.key, c.subject, c.number, c.title].every(text) || c.key !== `${c.subject} ${c.number}`)) throw invalid()
  return data
}
function validateSections(data: unknown): WireSection[] {
  if (!Array.isArray(data) || data.length > 10000) throw invalid()
  for (const s of data) {
    if (!s || !/^\d{5}$/.test(s.crn) || !text(s.courseKey) || !optionalText(s.units) || !s.information || typeof s.information !== 'object' || !Array.isArray(s.meetings) || !Array.isArray(s.instructors)) throw invalid()
    for (const m of s.meetings) if (!m || !Array.isArray(m.days) || m.days.some((d: string) => typeof d !== 'string' || !days.some(day => day.toLowerCase() === d.toLowerCase())) || ![m.startDate,m.endDate,m.beginTime,m.endTime,m.formatCode,m.campus,m.building,m.room].every(optionalText)) throw invalid()
    for (const i of s.instructors) if (!i || !text(i.assignmentId) || !['primary','secondary'].includes(i.role) || !optionalText(i.name)) throw invalid()
    validateAvailability(s.availability)
  }
  return data
}
function validateAvailability(a: any) {
  if (a !== null && (!a || !optionalText(a.statusCode) || ['seatsAvailable','capacity','waitlistCount','waitlistCapacity'].some(k => a[k] !== null && !Number.isSafeInteger(a[k])))) throw invalid()
}
const clock = (s: string | null) => { if (!s) return ''; const m = s.replace(':','').match(/^(\d{2})(\d{2})$/); if (!m) return s; const h = Number(m[1]); return `${h % 12 || 12}:${m[2]} ${h < 12 ? 'AM' : 'PM'}` }
export function mapSections(c: WireCourse, rows: WireSection[], meta: any): ScheduleResult {
  const source = sourceMetadata(meta), groups = new Map<string, Professor>()
  for (const row of rows) {
    if (row.courseKey !== c.key) throw invalid()
    const starts = row.meetings.map(m => m.startDate).filter((x): x is string => !!x).sort(), ends = row.meetings.map(m => m.endDate).filter((x): x is string => !!x).sort()
    const scheduled = row.meetings.filter(m => m.formatCode !== 'OD')
    const section: Section = { formatUnknown:!row.meetings.length || row.meetings.some(m => !m.formatCode), information:structuredClone(row.information), crn: row.crn, title: c.title, start: starts[0] ?? '', end: ends.at(-1) ?? '', formats: [...new Set(row.meetings.map(m => m.formatCode).filter((s): s is string => !!s))],
      days: days.filter(d => scheduled.some(m => m.days.some(x => x.toLowerCase() === d.toLowerCase()))), unannouncedMeetings: scheduled.some(m => !m.days.length),
      meetings: row.meetings.filter(m => m.formatCode !== 'OD').map(m => {
        const when = [m.days.map(d => days.find(x => x.toLowerCase() === d.toLowerCase())!).join(', '), [clock(m.beginTime), clock(m.endTime)].filter(Boolean).join(' – ')].filter(Boolean).join(' ') || 'Time TBA'
        return [when, [m.building, m.room].filter(Boolean).join(' '), m.startDate && m.endDate ? `${m.startDate} – ${m.endDate}` : 'Dates not announced'].filter(Boolean).join(' · ')
      }), status: row.availability?.statusCode ?? '', source,
      details: { termPart: [...new Set(row.meetings.map(m => m.sourceFields?.ptrmDesc).filter((x): x is string => typeof x === 'string'))].join(' · '), campus: [...new Set(row.meetings.map(m => m.campus).filter(Boolean))].join(' · '), units: row.units ?? '' } }
    applyAvailability(section, row.availability, source)
    for (const name of new Set(row.instructors.length ? row.instructors.map(i => i.name?.trim() || 'Instructor to be announced') : ['Instructor to be announced'])) {
      // Course-local display grouping, never a global identity or an RMP ID.
      const id = name.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase()
      const p = groups.get(id) ?? { id, name, subject: c.subject, state: 'pending' as const, sections: [], candidates: [] }
      p.sections.push(structuredClone(section)); groups.set(id, p)
    }
  }
  return { course: course(c), professors: [...groups.values()].sort((a,b) => a.name.localeCompare(b.name)), source, catalogVersion: meta.catalogVersion }
}
function applyAvailability(s: Section, a: WireSection['availability'], source: SourceMeta) {
  s.source = source
  s.details = { termPart: s.details?.termPart ?? '', campus: s.details?.campus ?? '', units: s.details?.units ?? '', ...(!source.stale && a ? { seatsOpen: a.seatsAvailable ?? undefined, capacity: a.capacity ?? undefined, waitlistCount: a.waitlistCount ?? undefined, waitlistCapacity: a.waitlistCapacity ?? undefined } : {}) }
  if (a) s.status = a.statusCode ?? ''
}
/** Cache contains public schedule data only, never keys, reviews or student preferences. */
export class ScheduleAPI implements ScheduleProvider {
  private entries = new Map<string, CachedResponse>()
  private loaded: Promise<void> | undefined
  private disk: Promise<unknown> = Promise.resolve()
  private api: ReadAPI
  private startupChecked = false
  private catalogs = new Map<string,Promise<{rows:WireCourse[];offline:boolean}>>()
  constructor(key: string, private file?: string, request: typeof fetch = fetch) { this.api = new ReadAPI(SCHEDULE_URL, key, request) }
  private async load() {
    return this.loaded ??= (async () => { if (!this.file) return; try { if ((await stat(this.file)).size > 8 * 1024 * 1024) return; const data = JSON.parse(await readFile(this.file, 'utf8')); if (data.version === 1 && Array.isArray(data.entries)) for (const [k,v] of data.entries.slice(-12)) if (typeof k === 'string' && /^\/v1\/terms(?:\/\d{6}\/(?:catalog|manifest|courses\/[^/]+\/sections))?$/.test(k) && v?.body) this.entries.set(k,v) } catch { /* Corrupt cache is a miss. */ } })()
  }
  private remember(route: string, value: CachedResponse) {
    this.entries.delete(route); this.entries.set(route,value)
    while (this.entries.size > 12) this.entries.delete(this.entries.keys().next().value!)
    while (this.entries.size > 1 && Buffer.byteLength(JSON.stringify([...this.entries])) > 8 * 1024 * 1024) this.entries.delete(this.entries.keys().next().value!)
    if (!this.file) return
    const file = this.file, contents = JSON.stringify({ version: 1, entries: [...this.entries].filter(([k]) => !k.includes('/availability')) })
    this.disk = this.disk.catch(() => {}).then(async () => { await mkdir(path.dirname(file),{recursive:true}); const tmp = file + '.' + randomUUID() + '.tmp'; await writeFile(tmp,contents); await rename(tmp,file) }).catch(() => {})
  }
  private async read(route: string, signal: AbortSignal, cached = false) {
    await this.load(); signal.throwIfAborted()
    const old = this.entries.get(route)
    if (cached && old) return { ...old.body, offline: false }
    try { const result = await this.api.get(route,signal,old); signal.throwIfAborted(); this.remember(route,result); return { ...result.body, offline: false } }
    catch (e) { signal.throwIfAborted(); if (e instanceof ReadError && ['UNAUTHORIZED','NOT_FOUND','INVALID_RESPONSE'].includes(e.code)) throw e; if (!old) throw e; return { ...old.body, meta: { ...old.body.meta, stale:true }, offline:true } }
  }
  async terms(signal = AbortSignal.timeout(25_000)): Promise<Term[]> {
    await this.load()
    const saved = this.entries.get('/v1/terms')?.body
    if (!this.startupChecked && saved) {
      this.startupChecked = true
      // Previously imported terms and catalog stay usable immediately when offline.
      const terms = this.parseTerms(saved.data)
      void this.read('/v1/terms',signal).then(async result => { const fresh=this.parseTerms(result.data); if (fresh[0] && !result.offline) await this.catalog(fresh[0].termCode,signal,true) }).catch(() => {})
      return terms
    }
    this.startupChecked = true
    const result = await this.read('/v1/terms',signal)
    const terms = this.parseTerms(result.data)
    // Startup revalidation is bounded to the imported term; suggestions can use the saved catalog meanwhile.
    if (terms[0] && !result.offline) void this.catalog(terms[0].termCode,signal,true).catch(() => {})
    return terms
  }
  private parseTerms(data: any): Term[] {
    if (!Array.isArray(data) || data.length > 100 || data.some((t: any) => !/^\d{6}$/.test(t.termCode) || !text(t.name))) throw invalid()
    return data.map((t: any) => ({termCode:t.termCode,termName:t.name,termDisplayControl:'Y'}))
  }
  private async catalog(term: string, signal: AbortSignal, force = false) {
    if (!/^\d{6}$/.test(term)) throw new ReadError('INVALID_QUERY','Choose a supported semester.')
    await this.load(); signal.throwIfAborted()
    const route = `/v1/terms/${term}/catalog`, saved = this.entries.get(route)
    if (!force && saved) return {rows:validateCourses(saved.body.data),offline:false}
    let flight = this.catalogs.get(term)
    if (!flight) {
      // Suggestions share the public catalog request; an obsolete query cannot enqueue another semester download.
      flight = this.read(route,AbortSignal.timeout(25_000)).then(result => ({rows:validateCourses(result.data),offline:!!result.offline})).finally(() => this.catalogs.delete(term))
      this.catalogs.set(term,flight)
    }
    return new Promise<{rows:WireCourse[];offline:boolean}>((resolve,reject) => {
      const abort = () => reject(signal.reason)
      signal.addEventListener('abort',abort,{once:true})
      flight!.then(result => { signal.removeEventListener('abort',abort); if (!signal.aborted) resolve(result) },e => { signal.removeEventListener('abort',abort); reject(e) })
    })
  }
  async suggest(term: string, query: string) {
    const {rows} = await this.catalog(term,AbortSignal.timeout(25_000)), needle = query.trim().toUpperCase(), compact = query.replace(/\s/g,'').toUpperCase()
    if (!needle || query.length > 100) return []
    return rows.map(c => ({ c, rank:c.key.replace(/\s/g,'') === compact ? 0 : normalized(c.key) === normalized(query) ? 1 : normalized(c.key).startsWith(normalized(query)) ? 2 : c.title.toUpperCase().startsWith(needle) ? 3 : c.title.toUpperCase().includes(needle) ? 4 : 99 })).filter(x => x.rank < 99).sort((a,b) => a.rank-b.rank || a.c.key.localeCompare(b.c.key)).slice(0,20).map(({c}) => ({course:course(c),title:c.title}))
  }
  async search(term: string, query: string, refresh: boolean, signal: AbortSignal): Promise<ScheduleResult> {
    const catalog = await this.catalog(term,signal,true), exact = catalog.rows.find(c => c.key.replace(/\s/g,'').toUpperCase() === query.replace(/\s/g,'').toUpperCase()), matches = catalog.rows.filter(c => normalized(c.key) === normalized(query))
    if (!exact && matches.length > 1) throw new ReadError('AMBIGUOUS','More than one course matches. Choose an official course from the suggestions.')
    const c = exact ?? matches[0]
    if (!c) throw new ReadError('NOT_FOUND','This course is not available in the selected BYE semester.')
    const result = await this.read(`/v1/terms/${term}/courses/${encodeURIComponent(c.key)}/sections`,signal)
    return { ...mapSections(c,validateSections(result.data),result.meta), offline:result.offline || catalog.offline }
  }
  async update(term: string, current: ScheduleResult, crns: string[], signal: AbortSignal): Promise<ScheduleResult> {
    const m = await this.read(`/v1/terms/${term}/manifest`,signal)
    if (!m.data || !text(m.data.catalogVersion)) throw invalid()
    if (m.data.catalogVersion !== current.catalogVersion && !m.offline) return this.search(term,current.course.display,true,signal)
    const next = structuredClone(current), byCRN = new Map<string, WireSection['availability']>()
    let source = sourceMetadata(m.meta), offline = m.offline
    for (let at=0;at<crns.length;at+=100) {
      const result = await this.read(`/v1/terms/${term}/availability?crns=${crns.slice(at,at+100).join(',')}`,signal)
      if (!Array.isArray(result.data) || result.data.length > 100) throw invalid()
      for (const item of result.data) { if (!crns.includes(item.crn)) throw invalid(); validateAvailability(item.availability); byCRN.set(item.crn,item.availability) }
      source = sourceMetadata(result.meta); offline ||= result.offline
    }
    for (const p of next.professors) for (const s of p.sections) if (byCRN.has(s.crn)) applyAvailability(s,byCRN.get(s.crn)!,source)
    next.source = source; next.offline = offline
    return next
  }
}
