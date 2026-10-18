import { randomUUID } from 'node:crypto'
import { setTimeout as delay } from 'node:timers/promises'
import type { Course, Profile, Professor, Snapshot, Term } from '../shared/types'
import { eligible, identity, orderReviews, professors, resolve } from '../shared/domain'
import { check, IdentityError, PCC, RMP } from './network'
import { Store } from './storage'
import type { SummaryProvider } from './summary'
import { AI_SUMMARIES_ENABLED, AI_SUMMARIES_DISABLED_MESSAGE } from '../shared/features'
const message = (e: unknown) => e instanceof Error ? e.message : 'This operation could not finish. Try again.'
export class Queue {
  private active = 0
  pending = 0
  constructor(private limit: number, private blocked = () => false) {}
  async run<T>(signal: AbortSignal, work: () => Promise<T>): Promise<T> {
    this.pending++
    let acquired = false
    try {
      while (this.active >= this.limit || this.blocked()) await delay(10, undefined, { signal })
      check(signal); this.active++; acquired = true
      return await work()
    } finally { if (acquired) this.active--; this.pending-- }
  }
}
export class Engine {
  state: Snapshot = { operationId: randomUUID(), professors: [], loading: false, previewPending: 0 }
  private run = new AbortController()
  private versions = new Map<string, AbortController>()
  private previews = new Queue(2)
  private details = new Queue(1, () => this.previews.pending > 0)
  private summaries = new Queue(1, () => this.previews.pending > 0)
  private tasks = new Set<Promise<unknown>>()
  private jobs = new Map<string, Promise<void>>()
  constructor(readonly pcc: Pick<PCC, 'terms' | 'schedule' | 'suggest'>, readonly rmp: Pick<RMP, 'candidates' | 'page'>, readonly store: Store, readonly ai: SummaryProvider, private publish: (state: Snapshot) => void, private summariesEnabled = () => AI_SUMMARIES_ENABLED) {}
  emit() { this.state.previewPending = this.previews.pending; this.publish(structuredClone(this.state)) }
  private launch(key: string, task: () => Promise<void>) {
    if (this.jobs.has(key)) return this.jobs.get(key)!
    const operation = this.state.operationId
    const promise = task().catch(e => { if (this.state.operationId === operation && !this.run.signal.aborted && !['AbortError', 'TimeoutError'].includes(e?.name)) { this.state.issue = message(e); this.emit() } }).finally(() => { if (this.jobs.get(key) === promise) this.jobs.delete(key); this.tasks.delete(promise) })
    this.jobs.set(key, promise); this.tasks.add(promise); return promise
  }
  async idle() { while (this.tasks.size) await Promise.all([...this.tasks]) }
  private professor(id: string) { const p = this.state.professors.find(p => p.id === id); if (!p) throw new Error('This professor is no longer in the current search.'); return p }
  private context(p: Professor, replace = false) {
    if (replace) this.versions.get(p.id)?.abort()
    let local = this.versions.get(p.id)
    if (!local || local.signal.aborted) { local = new AbortController(); this.versions.set(p.id, local) }
    return AbortSignal.any([this.run.signal, local.signal])
  }
  stop() {
    this.run.abort(); this.versions.forEach(c => c.abort()); this.versions.clear(); this.run = new AbortController()
    this.state.loading = false
    for (const p of this.state.professors) {
      if (p.state === 'pending' || p.state === 'loading') { p.state = p.profile ? 'ready' : 'unavailable'; p.issue = 'Stopped. Try again to retrieve this profile.' }
      if (p.detailLoading) p.reviewIssue = 'Stopped. Retrieved reviews are still available.'
      if (p.summaryLoading) p.summaryIssue = 'Stopped. Retry summary when ready.'
      p.detailLoading = false; p.summaryLoading = false; p.discoveryLoading = false; p.choosing = false
    }
    this.emit()
  }
  search(query: string, term: Term, refresh = false) {
    this.stop()
    const operationId = randomUUID(), signal = this.run.signal
    this.state = { operationId, professors: [], term, loading: true, previewPending: 0 }; this.emit()
    return this.launch('search-' + operationId, async () => {
      try {
        const terms = await this.pcc.terms(); check(signal)
        const published = terms.find(t => t.termCode === term.termCode)
        if (!published) throw new Error('Choose a published PCC semester.')
        const rows = await this.pcc.schedule(published.termCode, refresh); check(signal)
        const c = resolve(query, rows); this.state.course = c; this.state.term = published; this.state.professors = professors(rows, c)
        if (!this.state.professors.length) this.state.issue = 'No matching sections were published for this course and semester.'
        this.emit()
        await Promise.all(this.state.professors.map(p => this.lookup(p, refresh, this.context(p))))
      } catch (e) { if (!signal.aborted) this.state.issue = message(e) }
      finally { if (!signal.aborted) { this.state.loading = false; this.emit() } }
    })
  }
  private async save(p: Professor, signal: AbortSignal) {
    check(signal)
    if (p.profile) await this.store.setProfile(p.profile, () => !signal.aborted)
    check(signal)
    if (p.profile) await this.store.setIndex(p.name, p.subject, p.profile.id, () => !signal.aborted)
  }
  private verify(p: Professor, profile: Profile, expected: string) {
    if (profile.id !== expected || !identity(p.name, profile)) throw new IdentityError()
  }
  private async preview(p: Professor, id: string, signal: AbortSignal) {
    const page = await this.rmp.page(id, 3, signal); check(signal); this.verify(p, page.profile, id)
    page.profile.coverage.all = { reviewIDs: page.ids, hasNextPage: page.hasNextPage, nextCursor: page.nextCursor, updatedAt: Date.now() }
    return page.profile
  }
  private async lookup(p: Professor, refresh: boolean, signal: AbortSignal) {
    if (['staff', 'tba', 'instructor to be announced'].includes(p.name.toLowerCase())) { p.state = 'unavailable'; p.issue = 'PCC has not named an instructor.'; this.emit(); return }
    p.state = 'loading'; p.issue = undefined; this.emit()
    try {
      await this.previews.run(signal, async () => {
        this.emit()
        const choice = await this.store.choice(p.name, p.subject); check(signal)
        const cachedID = !refresh ? await this.store.index(p.name, p.subject) : undefined; check(signal)
        if (!refresh && (choice || cachedID)) {
          const cached = await this.store.profile(choice ?? cachedID!); check(signal)
          if (cached && identity(p.name, cached)) { p.profile = cached; p.state = 'ready'; this.emit(); return }
        }
        let options: Profile[] = []
        if (choice) {
          try { p.profile = await this.preview(p, choice, signal); check(signal); p.state = 'ready'; await this.save(p, signal); this.emit(); return }
          catch (e) {
            check(signal)
            if (!(e instanceof IdentityError)) throw e
            await this.store.setChoice(p.name, p.subject, undefined, () => !signal.aborted); await this.store.setIndex(p.name, p.subject, undefined, () => !signal.aborted); check(signal)
            options = (await this.rmp.candidates(p.name, signal, true).catch(() => { check(signal); return [] })).filter(x => x.id !== choice)
            check(signal); p.profile = undefined; p.summary = undefined; p.candidates = options; p.state = 'choose'; this.emit(); return
          }
        }
        options = await this.rmp.candidates(p.name, signal); check(signal); p.candidates = options
        if (options.length > 1) { p.profile = undefined; p.summary = undefined; await this.store.setIndex(p.name, p.subject, undefined, () => !signal.aborted); check(signal); p.state = 'choose'; this.emit(); return }
        if (!options.length) throw new Error('No matching PCC profile could be confirmed. Try again or check RMP.')
        try { p.profile = await this.preview(p, options[0].id, signal) }
        catch (e) { check(signal); if (e instanceof IdentityError) { p.profile = undefined; p.summary = undefined; await this.store.setIndex(p.name, p.subject, undefined, () => !signal.aborted); check(signal); p.candidates = options.filter(x => x.id !== options[0].id); p.state = 'choose'; this.emit(); return } throw e }
        check(signal); p.state = 'ready'; p.summary = undefined; await this.save(p, signal); this.emit()
      })
    } catch (e) { if (!signal.aborted) { p.state = 'unavailable'; p.issue = message(e); this.emit() } }
    finally { if (!signal.aborted) this.emit() }
  }
  retry(id: string) {
    const p = this.professor(id)
    if (p.state === 'loading') return Promise.resolve()
    const signal = this.context(p, true)
    p.detailLoading = false; p.summaryLoading = false; p.discoveryLoading = false
    return this.launch(`retry-${this.state.operationId}-${id}`, () => this.lookup(p, true, signal))
  }
  discover(id: string) {
    const p = this.professor(id), signal = this.context(p)
    // Only an explicit command owns the dialog; background work never opens it.
    for (const other of this.state.professors) other.choosing = other.id === id
    const key = `discover-${this.state.operationId}-${id}`
    if (this.jobs.has(key)) { this.emit(); return this.jobs.get(key)! }
    p.issue = undefined; p.candidates = []; p.discoveryLoading = true; this.emit()
    return this.launch(key, async () => {
      try { const candidates = await this.previews.run(signal, () => this.rmp.candidates(p.name, signal, true)); check(signal); p.candidates = candidates }
      catch (e) { if (!signal.aborted) p.issue = message(e) }
      finally { if (!signal.aborted) { p.discoveryLoading = false; this.emit() } }
    })
  }
  dismiss(id: string) { this.professor(id).choosing = false; this.emit() }
  select(id: string, profileId: string) {
    const p = this.professor(id)
    const jobKey = `select-${this.state.operationId}-${id}-${profileId}`
    if (this.jobs.has(jobKey)) return this.jobs.get(jobKey)!
    if (!p.candidates.some(x => x.id === profileId)) throw new Error('Choose a profile from the current candidate list.')
    const signal = this.context(p, true)
    p.profile = undefined; p.summary = undefined; p.summaryIssue = undefined; p.reviewIssue = undefined; p.detailLoading = false; p.summaryLoading = false; p.choosing = false; p.discoveryLoading = false; p.state = 'loading'; this.emit()
    return this.launch(jobKey, async () => {
      try {
        const profile = await this.previews.run(signal, () => this.preview(p, profileId, signal)); check(signal)
        p.profile = profile; p.state = 'ready'; p.issue = undefined
        await this.store.setChoice(p.name, p.subject, profileId, () => !signal.aborted); check(signal); await this.save(p, signal); this.emit()
      } catch (e) {
        if (!signal.aborted) {
          p.issue = message(e); p.state = e instanceof IdentityError ? 'choose' : 'unavailable'
          if (e instanceof IdentityError) { await this.store.setChoice(p.name, p.subject, undefined, () => !signal.aborted); await this.store.setIndex(p.name, p.subject, undefined, () => !signal.aborted); check(signal); p.candidates = p.candidates.filter(x => x.id !== profileId) }
          this.emit()
        }
      }
    })
  }
  expand(id: string, filter?: string) {
    const p = this.professor(id)
    if (!p.profile || p.detailLoading) return Promise.resolve()
    const signal = this.context(p), expected = p.profile.id, key = filter === undefined ? 'all' : 'course|' + filter
    return this.launch(`details-${this.state.operationId}-${id}-${key}`, async () => {
      p.detailLoading = true; p.reviewIssue = undefined; this.emit()
      try {
        await this.details.run(signal, async () => {
          const visited = new Set<string>()
          for (let pageNumber = 0; pageNumber < 10; pageNumber++) {
            check(signal)
            const current = p.profile!; this.verify(p, current, expected)
            const coverage = current.coverage[key] ?? { reviewIDs: [], hasNextPage: true, updatedAt: Date.now() }
            if (!coverage.hasNextPage || coverage.reviewIDs.length >= 50) return
            const page = await this.rmp.page(expected, Math.min(20, 50 - coverage.reviewIDs.length), signal, coverage.nextCursor, filter); check(signal); this.verify(p, page.profile, expected)
            const newIDs = page.ids.filter(x => !coverage.reviewIDs.includes(x))
            if (page.hasNextPage && (!newIDs.length || !page.nextCursor || visited.has(page.nextCursor))) throw new Error('RMP pagination stopped progressing. Retrieved reviews remain available.')
            if (page.nextCursor) visited.add(page.nextCursor)
            const merged = page.profile
            merged.reviews = orderReviews([...new Map([...current.reviews, ...merged.reviews].map(r => [r.id, r])).values()])
            merged.coverage = { ...current.coverage, [key]: { reviewIDs: [...coverage.reviewIDs, ...newIDs].slice(0, 50), nextCursor: page.nextCursor, hasNextPage: page.hasNextPage, updatedAt: Date.now() } }
            p.profile = merged; p.summary = undefined; await this.save(p, signal); this.emit()
          }
          throw new Error('RMP pagination reached its safety limit. Retrieved reviews remain available.')
        })
      } catch (e) {
        if (!signal.aborted) {
          p.reviewIssue = message(e)
          if (e instanceof IdentityError) { await this.store.setChoice(p.name, p.subject, undefined, () => !signal.aborted); await this.store.setIndex(p.name, p.subject, undefined, () => !signal.aborted); check(signal); p.profile = undefined; p.summary = undefined; p.state = 'choose'; p.candidates = [] }
        }
      } finally { if (!signal.aborted) { p.detailLoading = false; this.emit() } }
    })
  }
  summarize(id: string) {
    const p = this.professor(id), c = this.state.course
    if (!this.summariesEnabled()) {
      p.summary = undefined; p.summaryLoading = false; p.summaryIssue = AI_SUMMARIES_DISABLED_MESSAGE
      this.emit(); return Promise.resolve()
    }
    if (!p.profile || !c) return Promise.resolve()
    const signal = this.context(p), expected = p.profile.id
    return this.launch(`summary-${this.state.operationId}-${id}`, async () => {
      // Wait for any requested detail pass before choosing evidence.
      const detailJobs = [...this.jobs].filter(([key]) => key.startsWith(`details-${this.state.operationId}-${id}-`)).map(([, job]) => job)
      await Promise.all(detailJobs); check(signal)
      p.summaryLoading = true; p.summaryIssue = undefined; this.emit()
      try {
        await this.summaries.run(signal, async () => {
          check(signal); if (p.profile?.id !== expected) throw new IdentityError()
          const reviews = structuredClone(p.profile.reviews), fingerprint = JSON.stringify(reviews)
          const summary = await this.store.summary(expected, c, this.ai.cacheIdentity, reviews) ?? await this.ai.summarize(reviews, c, signal)
          check(signal)
          if (p.profile?.id !== expected || JSON.stringify(p.profile.reviews) !== fingerprint) return
          p.summary = summary; await this.store.setSummary(expected, c, summary, reviews, () => !signal.aborted && p.profile?.id === expected && JSON.stringify(p.profile.reviews) === fingerprint); check(signal); this.emit()
        })
      } catch (e) { if (!signal.aborted) p.summaryIssue = message(e) }
      finally { if (!signal.aborted) { p.summaryLoading = false; this.emit() } }
    })
  }
}
