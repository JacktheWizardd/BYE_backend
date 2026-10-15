import React, { useEffect, useRef, useState } from 'react'
import { createRoot } from 'react-dom/client'
import '@fontsource/schibsted-grotesk/400.css'
import '@fontsource/schibsted-grotesk/500.css'
import '@fontsource/schibsted-grotesk/600.css'
import '@fontsource/schibsted-grotesk/700.css'
import '@fontsource/jetbrains-mono/500.css'
import type { Command, Course, Professor, Section, Snapshot, Suggestion, Term } from '@shared/types'
import { delivery, filterReviews, orderProfessors, orderReviews } from '@shared/domain'
import { DemoBridge } from './demo-bridge'
import './styles.css'

const bridge = new DemoBridge()
const empty: Snapshot = { operationId: '', professors: [], loading: false, previewPending: 0 }
const EXAMPLES = ['ETH 014', 'MATH 5A', 'ENGL 1A']
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
const score = (n?: number) => n === undefined ? '—' : n.toFixed(1)
const day = (s: string) => { const [, m, d] = s.slice(0, 10).split('-').map(Number); return m ? `${MONTHS[m - 1]} ${d}` : '' }
const monthYear = (s: string) => { const [y, m] = s.slice(0, 7).split('-').map(Number); return y && m ? `${MONTHS[m - 1]} ${y}` : 'Date unavailable' }
const format = (s: Section) => delivery(s).split(' · ')[0]
const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`
const courseLabel = (label: string) => label.replace(/^([A-Z]+)(\d)/, '$1 $2')

function Wordmark() { return <span className="wordmark" aria-label="BYE"><span>BYE</span></span> }

function Bar({ value, label }: { value?: number; label: string }) {
  return <span className="bar" role="img" aria-label={`${label} ${score(value)} out of 5`}><span style={{ width: `${((value ?? 0) / 5) * 100}%` }} /></span>
}

function CourseField({ term, query, setQuery, onPick }: { term: string; query: string; setQuery: (q: string) => void; onPick: (q: string) => void }) {
  const [open, setOpen] = useState(false), [items, setItems] = useState<Suggestion[]>([]), [index, setIndex] = useState(-1)
  const sequence = useRef(0)
  useEffect(() => {
    const id = ++sequence.current
    if (!open || !term || !query.trim()) { setItems([]); return }
    const timer = setTimeout(() => {
      bridge.command({ kind: 'suggest', term, query }).then(r => { if (sequence.current === id) { setItems(r as Suggestion[]); setIndex(-1) } }).catch(() => setItems([]))
    }, 120)
    return () => clearTimeout(timer)
  }, [query, term, open])
  const pick = (s: Suggestion) => { setQuery(s.course.display); setOpen(false); setItems([]); onPick(s.course.display) }
  return <div className="course-field">
    <svg className="search-glyph" viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7" /><path d="m20 20-3.6-3.6" /></svg>
    <input id="course" role="combobox" aria-autocomplete="list" aria-expanded={items.length > 0} aria-controls="course-options"
      aria-activedescendant={index >= 0 ? `suggestion-${index}` : undefined} placeholder="Course code or title, like MATH 5A" value={query} autoComplete="off" spellCheck={false}
      onFocus={() => setOpen(true)} onBlur={() => setTimeout(() => setOpen(false), 100)} onChange={e => { setQuery(e.target.value); setOpen(true) }}
      onKeyDown={e => {
        if (e.key === 'ArrowDown' && items.length) { e.preventDefault(); setIndex(i => Math.min(i + 1, items.length - 1)) }
        if (e.key === 'ArrowUp' && items.length) { e.preventDefault(); setIndex(i => Math.max(i - 1, 0)) }
        if (e.key === 'Escape') { setOpen(false); setItems([]) }
        if (e.key === 'Enter' && index >= 0 && items[index]) { e.preventDefault(); pick(items[index]) }
      }} />
    {items.length > 0 && <ul className="suggestions" id="course-options" role="listbox">{items.map((s, i) =>
      <li id={`suggestion-${i}`} key={s.course.key} role="option" aria-selected={index === i} className={index === i ? 'active' : ''} onMouseDown={e => { e.preventDefault(); pick(s) }}>
        <span className="code">{s.course.display}</span><span>{s.title.toLowerCase()}</span>
      </li>)}</ul>}
  </div>
}

function SearchView(props: { terms: Term[]; termCode: string; setTermCode: (t: string) => void; query: string; setQuery: (q: string) => void; search: (q?: string) => void; error: string }) {
  const { terms, termCode, setTermCode, query, setQuery, search, error } = props
  return <main className="search-view">
    <div className="search-column">
      <span className="eyebrow">For PCC students · Web demo</span>
      <h1>Find your <span className="swipe">professor.</span></h1>
      <p className="lead">Type a course to see every section next to student ratings and reviews. Then decide for yourself.</p>
      <form onSubmit={e => { e.preventDefault(); search() }}>
        <label className="field-label" htmlFor="course">Class</label>
        <CourseField term={termCode} query={query} setQuery={setQuery} onPick={q => search(q)} />
        <label className="field-label" htmlFor="term">Semester</label>
        <select id="term" value={termCode} disabled={!terms.length} onChange={e => setTermCode(e.target.value)}>
          {!terms.length && <option value="">Loading semesters…</option>}
          {terms.map(t => <option key={t.termCode} value={t.termCode}>{t.termName}</option>)}
        </select>
        <button className="button primary wide" type="submit" disabled={!termCode || !query.trim()}>Find professors <span aria-hidden="true">→</span></button>
      </form>
      {error && <p className="notice" role="alert"><b>Problem</b> {error}</p>}
      <div className="examples"><span>Try</span>{EXAMPLES.map(x => <button key={x} type="button" className="chip" onClick={() => { setQuery(x); search(x) }}>{x}</button>)}</div>
    </div>
  </main>
}

function ProfessorCard({ p, selected, onSelect }: { p: Professor; selected: boolean; onSelect: () => void }) {
  const formats = [...new Set(p.sections.map(format))].join(', ')
  const status = p.state === 'choose' ? 'Choose a profile' : p.state === 'unavailable' ? (p.issue?.startsWith('PCC has not') ? 'No instructor named yet' : 'Cannot retrieve RMP info') : p.state !== 'ready' ? 'Checking RMP…' : `${p.profile?.ratingCount ?? '—'} ratings`
  return <button className={`professor-card${selected ? ' selected' : ''}`} aria-pressed={selected} onClick={onSelect}>
    <span className="card-name">{p.name}</span>
    <span className="card-meta">{plural(p.sections.length, 'section')} · {formats}</span>
    {p.profile ? <span className="card-scores">
      <span className="card-score"><b>{score(p.profile.rating)}</b><Bar value={p.profile.rating} label="Rating" /></span>
      <span className="card-diff">Difficulty <b>{score(p.profile.difficulty)}</b></span>
    </span> : <span className={`card-status ${p.state}`}>{status}</span>}
    {p.profile && <span className="card-foot">{status}</span>}
  </button>
}

function SectionCard({ s }: { s: Section }) {
  return <article className="section-card">
    <div className="row"><span className="code">CRN {s.crn}</span><span className={`tag ${s.status === 'O' ? 'open' : 'closed'}`}>{s.status === 'O' ? 'Open' : s.status === 'C' ? 'Closed' : 'Status unknown'}</span></div>
    <p className="section-format">{delivery(s)}</p>
    {s.meetings.length ? s.meetings.map(m => <p className="small" key={m}>{m}</p>) : <p className="small muted">No scheduled meetings</p>}
    <p className="small muted">{day(s.start)} – {day(s.end)}</p>
  </article>
}

function Report({ p, course, back, command }: { p: Professor; course: Course; back: () => void; command: (c: Command) => void }) {
  const [filter, setFilter] = useState('this'), [sort, setSort] = useState('recent'), [visible, setVisible] = useState(4)
  useEffect(() => { setFilter('this'); setVisible(4) }, [p.id])
  const profile = p.profile
  const reviews = profile ? orderReviews(filterReviews(profile, course, filter), sort) : []
  const labels = (profile?.courseCounts ?? []).filter(x => x.label)
  return <article className="report" aria-label={`Report for ${p.name}`}>
    <button className="back button ghost" onClick={back}>← All professors</button>
    <header className="report-head">
      <span className="eyebrow">Professor report</span>
      <h2>{p.name}</h2>
      <p className="muted">{profile?.department ? `${profile.department} · ` : ''}Pasadena City College</p>
    </header>

    {p.state === 'loading' || p.state === 'pending' ? <p className="placeholder" role="status">Checking RMP for {p.name}…</p> : null}
    {p.state === 'choose' && <div className="callout"><p><b>{p.candidates.length} PCC profiles match {p.name}.</b> Pick the one that teaches {course.display}. BYE keeps them separate and never guesses.</p><button className="button primary" onClick={() => command({ kind: 'discover', professorId: p.id })}>Choose profile →</button></div>}
    {p.state === 'unavailable' && <div className="callout problem"><p><b className="signal">Cannot retrieve RMP info.</b> {p.issue}</p>{!p.issue?.startsWith('PCC has not') && <button className="button secondary" onClick={() => command({ kind: 'retry', professorId: p.id })}>Try again</button>}</div>}

    <section className="block">
      <h3>Sections <span className="muted">· {course.display}</span></h3>
      <div className="section-grid">{p.sections.map(s => <SectionCard key={s.crn} s={s} />)}</div>
    </section>

    {profile && <>
      <section className="block">
        <div className="score-grid">
          <div className="score-card"><span className="label">Rating</span><span className="score">{score(profile.rating)}<small>/ 5</small></span><Bar value={profile.rating} label="Rating" /><span className="hint">Higher means students rated the teaching better</span></div>
          <div className="score-card"><span className="label">Difficulty</span><span className="score">{score(profile.difficulty)}<small>/ 5</small></span><Bar value={profile.difficulty} label="Difficulty" /><span className="hint">Lower means easier</span></div>
        </div>
        <p className="source-line">{profile.wouldTakeAgain === undefined ? '' : `${profile.wouldTakeAgain}% would take again · `}{plural(profile.ratingCount ?? 0, 'rating')} · Scores cover every course this professor teaches · Sample data
          {p.candidates.length > 1 && <> · <button className="link" onClick={() => command({ kind: 'discover', professorId: p.id })}>Change profile</button></>}</p>
      </section>

      <section className="block summary-panel">
        <div className="row"><h3>Summary</h3><span className="tag dashed">Not in demo</span></div>
        <p className="muted">The Mac app can summarize reviews on your device. The web demo shows the original reviews only.</p>
      </section>

      <section className="block">
        <div className="row wrap"><h3>Reviews <span className="muted">({reviews.length})</span></h3>
          <div className="filters">
            <label>Course<select value={filter} onChange={e => { setFilter(e.target.value); setVisible(4) }}>
              <option value="this">This course</option><option value="all">All courses</option>
              {labels.map(x => <option key={x.label} value={x.label}>{courseLabel(x.label)}{x.count === undefined ? '' : ` (${x.count})`}</option>)}
            </select></label>
            <label>Sort<select value={sort} onChange={e => setSort(e.target.value)}>
              <option value="recent">Most recent</option><option value="highest">Highest rating</option><option value="lowest">Lowest rating</option><option value="difficulty">Lowest difficulty</option>
            </select></label>
          </div>
        </div>
        {p.detailLoading && <p className="muted small" role="status">Quick preview · loading every review…</p>}
        <div className="review-list">{reviews.slice(0, visible).map(r => <article className="review-card" key={r.id}>
          <div className="row"><span className="code">{courseLabel(r.course) || 'Course unspecified'}</span><span className="small muted">Posted {monthYear(r.date)}</span></div>
          <p>{r.text}</p>
          <p className="small muted">Rating {r.rating ?? "—"} / 5 · Difficulty {r.difficulty ?? "—"} / 5</p>
        </article>)}</div>
        {!reviews.length && !p.detailLoading && <p className="muted">No reviews match this filter. Try All courses.</p>}
        {visible < reviews.length && <button className="button secondary" onClick={() => setVisible(n => n + 6)}>Show more reviews</button>}
        <p className="small muted">Ratings reflect student feedback. They don't guarantee a grade.</p>
      </section>
    </>}
  </article>
}

function Chooser({ p, command }: { p?: Professor; command: (c: Command) => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => {
    const dialog = ref.current
    if (p?.choosing && dialog && !dialog.open) dialog.showModal()
    if (!p?.choosing && dialog?.open) dialog.close()
  }, [p?.choosing, p?.id])
  return <dialog ref={ref} className="chooser" aria-labelledby="chooser-title" onCancel={e => { e.preventDefault(); if (p) command({ kind: 'dismiss', professorId: p.id }) }}>
    <h2 id="chooser-title">Which {p?.name} teaches this class?</h2>
    <p className="muted">These Rate My Professors profiles share the name. Pick one, and BYE will remember it for this subject.</p>
    {!p?.candidates.length && <p className="muted" role="status">Looking for profiles…</p>}
    {p?.candidates.map(c => <div className="candidate" key={c.id}>
      <div><b>{c.firstName} {c.lastName}</b><p className="small muted">{c.department || 'Department unavailable'} · {plural(c.ratingCount ?? 0, 'rating')}</p></div>
      <button className="button primary" onClick={() => command({ kind: 'select', professorId: p.id, profileId: c.id })}>Use this profile</button>
    </div>)}
    <div className="row end"><button className="button secondary" onClick={() => p && command({ kind: 'dismiss', professorId: p.id })}>Cancel</button></div>
  </dialog>
}

function App() {
  const [state, setState] = useState(empty), [terms, setTerms] = useState<Term[]>([]), [termCode, setTermCode] = useState('')
  const [query, setQuery] = useState(''), [view, setView] = useState<'search' | 'results'>('search'), [error, setError] = useState('')
  const [selected, setSelected] = useState(''), [sort, setSort] = useState('rating'), [pane, setPane] = useState<'list' | 'report'>('list')
  const lastOperation = useRef(''), opened = useRef('')
  const command = (c: Command) => { bridge.command(c).catch(e => setError(e instanceof Error ? e.message : 'This action failed. Try again.')) }
  useEffect(() => {
    const unsubscribe = bridge.subscribe(setState)
    bridge.command({ kind: 'terms' }).then(r => { const t = r as Term[]; setTerms(t); setTermCode(t[0]?.termCode ?? '') })
    return unsubscribe
  }, [])
  useEffect(() => {
    if (state.operationId !== lastOperation.current) { lastOperation.current = state.operationId; opened.current = ''; setSelected('') }
  }, [state.operationId])
  const course = state.course
  const list = course ? orderProfessors(state.professors, sort, course) : state.professors
  const p = state.professors.find(x => x.id === selected) ?? list[0]
  // Load full reviews once the report is open and previews have settled, like the desktop app.
  useEffect(() => {
    if (!p?.profile || p.state !== 'ready' || state.previewPending) return
    const key = `${state.operationId}|${p.id}|${p.profile.id}`
    if (opened.current !== key) { opened.current = key; command({ kind: 'details', professorId: p.id }) }
  }, [p?.id, p?.profile?.id, p?.state, state.previewPending])
  function search(text = query) {
    const term = terms.find(t => t.termCode === termCode)
    if (!term || !text.trim()) return
    setError(''); setView('results'); setPane('list'); command({ kind: 'search', query: text, term })
  }
  const checked = state.professors.filter(x => x.state !== 'pending' && x.state !== 'loading').length
  const sections = state.professors.reduce((n, x) => n + x.sections.length, 0)

  return <div className="app">
    <div className="demo-banner" role="note"><b>Demo</b> · sample data, not real professors. Schedules, ratings and reviews are made up to show how BYE works.</div>
    <header className="toolbar">
      <button className="home" onClick={() => setView('search')} aria-label="BYE home"><Wordmark /><span className="tagline">Before You Enroll</span></button>
      {view === 'results' && <div className="toolbar-actions">
        {course && <span className="course-chip"><span className="code">{course.display}</span><span className="muted">{state.term?.termName}</span></span>}
        {state.loading && <button className="button secondary small" onClick={() => command({ kind: 'stop' })}>Stop</button>}
        <button className="button secondary small" onClick={() => { if (course) setQuery(course.display); setView('search') }}>Change search</button>
      </div>}
    </header>

    {view === 'search' ? <SearchView terms={terms} termCode={termCode} setTermCode={setTermCode} query={query} setQuery={setQuery} search={search} error={error} /> :
      <div className={`results pane-${pane}`}>
        <aside className="sidebar" aria-label="Professors">
          <div className="sidebar-head">
            <div><h2>Professors</h2><p className="muted small">{course ? `${plural(sections, 'section')} · ${plural(state.professors.length, 'professor')}` : 'Finding sections…'}</p></div>
            <label className="sort">Sort<select value={sort} onChange={e => setSort(e.target.value)}><option value="rating">Rating</option><option value="difficulty">Difficulty</option><option value="reviews">Reviews for this course</option></select></label>
          </div>
          {state.issue && <p className="notice" role="status"><b>Problem</b> {state.issue}</p>}
          {error && <p className="notice" role="alert"><b>Problem</b> {error}</p>}
          {!course && state.loading && <p className="placeholder" role="status">Reading the PCC schedule…</p>}
          <div className="card-list">{list.map(x => <ProfessorCard key={x.id} p={x} selected={p?.id === x.id} onSelect={() => { setSelected(x.id); setPane('report'); window.scrollTo(0, 0) }} />)}</div>
        </aside>
        <section className="report-pane">{p && course ? <Report p={p} course={course} back={() => setPane('list')} command={command} /> : !state.loading && <div className="empty"><h2>No sections to show</h2><p className="muted">Try another course, like MATH 5A.</p></div>}</section>
      </div>}

    <footer className="statusbar">
      <span>Sample data · nothing leaves this page</span>
      {view === 'results' && state.professors.length > 0 && <span className="progress">
        {state.loading ? `Checking RMP… ${checked} of ${state.professors.length}` : `${checked} of ${state.professors.length} checked`}
        <span className="meter" role="progressbar" aria-valuemin={0} aria-valuemax={state.professors.length} aria-valuenow={checked}><span style={{ width: `${(checked / state.professors.length) * 100}%` }} /></span>
      </span>}
    </footer>
    <Chooser p={state.professors.find(x => x.choosing)} command={command} />
  </div>
}

createRoot(document.getElementById('root')!).render(<App />)
