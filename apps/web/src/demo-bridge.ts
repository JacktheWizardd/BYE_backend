import type { Bridge, Command, Profile, Professor, Snapshot, Term } from '@shared/types'
import { eligible, normalizedName, orderReviews, professors, resolve, suggestions } from '@shared/domain'
import { demoData, type DemoData } from './demo-data'

// A browser-only Bridge over bundled sample data. It follows the Electron Engine's flow
// (schedule → professors → profile preview → details) so the UI can later switch to a live
// implementation without changes. It makes no network requests.

export const DEMO_SUMMARY_MESSAGE = 'AI summaries are not part of the web demo. Ratings and original reviews are shown in full.'
export const PREVIEW_COUNT = 3
const message = (e: unknown) => e instanceof Error ? e.message : 'This operation could not finish. Try again.'
const unnamed = ['staff', 'tba', 'instructor to be announced']

function sleep(ms: number, signal: AbortSignal) {
  return new Promise<void>((resolve, reject) => {
    if (signal.aborted) return reject(signal.reason)
    const timer = setTimeout(() => { signal.removeEventListener('abort', abort); resolve() }, ms)
    const abort = () => { clearTimeout(timer); reject(signal.reason) }
    signal.addEventListener('abort', abort, { once: true })
  })
}

export class DemoBridge implements Bridge {
  private state: Snapshot = { operationId: '', professors: [], loading: false, previewPending: 0 }
  private listeners = new Set<(state: Snapshot) => void>()
  private run = new AbortController()
  private choices = new Map<string, string>()
  private tasks = new Set<Promise<void>>()
  private operations = 0

  /** `pace` scales every simulated delay; tests pass 0. */
  constructor(private data: DemoData = demoData, private pace = 1) {}

  subscribe(listener: (state: Snapshot) => void) {
    this.listeners.add(listener); listener(structuredClone(this.state))
    return () => { this.listeners.delete(listener) }
  }

  async command(command: Command): Promise<unknown> {
    switch (command.kind) {
      case 'terms': await sleep(this.ms(200), new AbortController().signal); return structuredClone(this.data.terms)
      case 'suggest': return suggestions(command.query, this.rows(command.term))
      case 'search': this.search(command.query, command.term); return
      case 'stop': this.stop(); return
      case 'retry': this.track(this.lookup(this.professor(command.professorId), this.run.signal, 0)); return
      case 'discover': this.track(this.discover(command.professorId)); return
      case 'dismiss': this.professor(command.professorId).choosing = false; this.emit(); return
      case 'select': this.track(this.select(command.professorId, command.profileId)); return
      case 'details': this.track(this.details(command.professorId)); return
      case 'summary': { const p = this.professor(command.professorId); p.summary = undefined; p.summaryIssue = DEMO_SUMMARY_MESSAGE; this.emit(); return }
      case 'source': throw new Error('Links to the PCC schedule and Rate My Professors are turned off in the demo.')
    }
  }

  /** Resolves once every simulated request has finished. */
  async idle() { while (this.tasks.size) await Promise.allSettled([...this.tasks]) }

  private ms(base: number) { return base * this.pace }
  private emit() {
    this.state.previewPending = this.state.professors.filter(p => p.state === 'pending' || p.state === 'loading').length
    const snapshot = structuredClone(this.state)
    for (const listener of this.listeners) listener(snapshot)
  }
  private track(task: Promise<void>) {
    const tracked = task.catch(e => { if (e?.name !== 'AbortError') { this.state.issue = message(e); this.emit() } }).finally(() => this.tasks.delete(tracked))
    this.tasks.add(tracked)
  }
  private rows(termCode: string) {
    const rows = this.data.schedules[termCode]
    if (!rows) throw new Error('Choose a published PCC semester.')
    return rows
  }
  private professor(id: string) {
    const p = this.state.professors.find(p => p.id === id)
    if (!p) throw new Error('This professor is no longer in the current search.')
    return p
  }
  private choiceKey(p: Professor) { return `${normalizedName(p.name)}|${p.subject}` }
  private source(id: string) {
    const profile = this.data.profiles.find(p => p.id === id)
    if (!profile) throw new Error('This profile is not in the sample data.')
    return profile
  }
  private candidates(name: string): Profile[] { return eligible(name, this.data.profiles).map(p => ({ ...structuredClone(p), reviews: [] })) }
  // Like an RMP preview page: professor-wide scores plus the newest few reviews.
  private preview(id: string): Profile {
    const source = this.source(id), reviews = orderReviews(source.reviews).slice(0, PREVIEW_COUNT)
    return { ...structuredClone(source), reviews: structuredClone(reviews), coverage: { all: { reviewIDs: reviews.map(r => r.id), hasNextPage: source.reviews.length > reviews.length, updatedAt: Date.now() } } }
  }

  stop() {
    this.run.abort(); this.run = new AbortController()
    this.state.loading = false
    for (const p of this.state.professors) {
      if (p.state === 'pending' || p.state === 'loading') { p.state = p.profile ? 'ready' : 'unavailable'; p.issue = 'Stopped. Try again to retrieve this profile.' }
      if (p.detailLoading) p.reviewIssue = 'Stopped. Retrieved reviews are still available.'
      p.detailLoading = false; p.summaryLoading = false
    }
    this.emit()
  }

  private search(query: string, term: Term) {
    this.stop()
    const signal = this.run.signal
    this.state = { operationId: `demo-${++this.operations}`, professors: [], term, loading: true, previewPending: 0 }; this.emit()
    this.track((async () => {
      try {
        await sleep(this.ms(400), signal)
        const published = this.data.terms.find(t => t.termCode === term.termCode)
        if (!published) throw new Error('Choose a published PCC semester.')
        const rows = this.rows(published.termCode), course = resolve(query, rows)
        this.state.course = course; this.state.term = published; this.state.professors = professors(rows, course)
        if (!this.state.professors.length) this.state.issue = 'No matching sections were published for this course and semester.'
        this.emit()
        await Promise.all(this.state.professors.map((p, i) => this.lookup(p, signal, i)))
      } catch (e) { if (!signal.aborted) this.state.issue = message(e) }
      finally { if (!signal.aborted) { this.state.loading = false; this.emit() } }
    })())
  }

  private async lookup(p: Professor, signal: AbortSignal, order: number) {
    if (unnamed.includes(p.name.toLowerCase())) { p.state = 'unavailable'; p.issue = 'PCC has not named an instructor for this section yet.'; this.emit(); return }
    if (p.state === 'loading') return
    p.state = 'loading'; p.issue = undefined; this.emit()
    try {
      await sleep(this.ms(500 + order * 280), signal)
      const options = this.candidates(p.name), remembered = this.choices.get(this.choiceKey(p))
      p.candidates = options
      if (remembered && options.some(o => o.id === remembered)) { p.profile = this.preview(remembered); p.state = 'ready'; this.emit(); return }
      if (options.length > 1) { p.profile = undefined; p.state = 'choose'; this.emit(); return }
      if (!options.length) throw new Error('No matching PCC profile was found on Rate My Professors.')
      p.profile = this.preview(options[0].id); p.state = 'ready'; this.emit()
    } catch (e) { if (!signal.aborted) { p.state = 'unavailable'; p.issue = message(e); this.emit() } }
  }

  private async discover(id: string) {
    const p = this.professor(id), signal = this.run.signal
    p.choosing = true; p.issue = undefined; this.emit()
    await sleep(this.ms(250), signal)
    p.candidates = this.candidates(p.name); this.emit()
  }

  private async select(id: string, profileId: string) {
    const p = this.professor(id), signal = this.run.signal
    if (!p.candidates.some(c => c.id === profileId)) throw new Error('Choose a profile from the current list.')
    p.profile = undefined; p.reviewIssue = undefined; p.summaryIssue = undefined; p.choosing = false; p.state = 'loading'; this.emit()
    try {
      await sleep(this.ms(400), signal)
      p.profile = this.preview(profileId); p.state = 'ready'; p.issue = undefined
      this.choices.set(this.choiceKey(p), profileId); this.emit()
    } catch (e) { if (!signal.aborted) { p.state = 'unavailable'; p.issue = message(e); this.emit() } }
  }

  // Loads every sample review (the real app pages through up to 50 per filter).
  private async details(id: string) {
    const p = this.professor(id), signal = this.run.signal
    if (!p.profile || p.detailLoading || !p.profile.coverage.all?.hasNextPage) return
    const expected = p.profile.id
    p.detailLoading = true; p.reviewIssue = undefined; this.emit()
    try {
      await sleep(this.ms(700), signal)
      if (p.profile?.id !== expected) return
      const reviews = orderReviews(this.source(expected).reviews).slice(0, 50)
      p.profile = { ...p.profile, reviews: structuredClone(reviews), coverage: { all: { reviewIDs: reviews.map(r => r.id), hasNextPage: false, updatedAt: Date.now() } } }
    } finally { if (!signal.aborted) { p.detailLoading = false; this.emit() } }
  }
}
