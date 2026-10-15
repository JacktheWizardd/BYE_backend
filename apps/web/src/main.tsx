import React, { useEffect, useRef, useState } from 'react'
import { createRoot } from 'react-dom/client'
import '@fontsource/schibsted-grotesk/400.css'
import '@fontsource/schibsted-grotesk/600.css'
import '@fontsource/schibsted-grotesk/700.css'
import '@fontsource/jetbrains-mono/500.css'
import type { Command, Course, Professor, Section, Snapshot, Suggestion, Term } from '@shared/types'
import { filterReviews, orderProfessors, orderReviews, sameCourse } from '@shared/domain'
import { DemoBridge } from './demo-bridge'
import { demoSeats } from './demo-data'
import { WEEKDAYS, fits, formatLabel, titleCase, type Weekday } from './schedule'
import './styles.css'

const bridge = new DemoBridge()
const empty: Snapshot = { operationId: '', professors: [], loading: false, previewPending: 0 }
const EXAMPLES = ['MATH 5A', 'ETH 014', 'ENGL 1A']
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
const PHONE = '(max-width: 759px)'
type Screen = 'search' | 'list' | 'report'
interface Recent { display: string; title: string }

const score = (n?: number) => n === undefined ? '—' : n.toFixed(1)
const day = (s: string) => { const [, m, d] = s.slice(0, 10).split('-').map(Number); return m ? `${MONTHS[m - 1]} ${d}` : '' }
const monthYear = (s: string) => { const [y, m] = s.slice(0, 7).split('-').map(Number); return y && m ? `${MONTHS[m - 1]} ${y}` : 'Date unavailable' }
const plural = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`
const courseLabel = (label: string) => label.replace(/^([A-Z]+)(\d)/, '$1 $2')
const isPhone = () => typeof matchMedia === 'function' && matchMedia(PHONE).matches
const unnamed = (p: Professor) => p.issue?.startsWith('PCC has not') ?? false

// Recent searches stay in this browser only; storage can be unavailable (private mode), so failures are ignored.
function loadRecent(): Recent[] { try { return JSON.parse(localStorage.getItem('bye-recent') ?? '[]').slice(0, 3) } catch { return [] } }
function saveRecent(list: Recent[]) { try { localStorage.setItem('bye-recent', JSON.stringify(list)) } catch { /* not available */ } }

function Wordmark() { return <span className="wordmark"><b>BYE</b></span> }
function Bar({ value, label, max = 5 }: { value?: number; label: string; max?: number }) {
  return <span className="bar" role="img" aria-label={`${label} ${value === undefined ? 'unknown' : value} out of ${max}`}><i style={{ width: `${((value ?? 0) / max) * 100}%` }} /></span>
}
function DemoBanner() { return <div className="demo-banner" role="note"><b>Demo</b> · sample data<span className="wide-only">, not real professors. Schedules, ratings and reviews are made up to show how BYE works.</span></div> }

function CourseField(props: { term: string; query: string; setQuery: (q: string) => void; onPick: (q: string) => void; recent: Recent[] }) {
  const { term, query, setQuery, onPick, recent } = props
  const [open, setOpen] = useState(false), [items, setItems] = useState<Suggestion[]>([]), [index, setIndex] = useState(-1)
  const sequence = useRef(0), input = useRef<HTMLInputElement>(null)
  useEffect(() => {
    const id = ++sequence.current
    if (!open || !term || !query.trim()) { setItems([]); return }
    const timer = setTimeout(() => {
      bridge.command({ kind: 'suggest', term, query }).then(r => { if (sequence.current === id) { setItems(r as Suggestion[]); setIndex(-1) } }).catch(() => setItems([]))
    }, 100)
    return () => clearTimeout(timer)
  }, [query, term, open])
  const pick = (display: string) => { setQuery(display); setOpen(false); setItems([]); input.current?.blur(); onPick(display) }
  const showRecent = open && !query.trim() && recent.length > 0
  const needle = query.trim().toLowerCase()
  const mark = (title: string) => {
    const text = titleCase(title), at = needle ? text.toLowerCase().indexOf(needle) : -1
    return at < 0 ? text : <>{text.slice(0, at)}<b>{text.slice(at, at + needle.length)}</b>{text.slice(at + needle.length)}</>
  }
  return <div className={`course-field${open ? ' focused' : ''}`}>
    <div className="field-box">
      <svg className="search-glyph" viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7" /><path d="m20 20-3.6-3.6" /></svg>
      <input ref={input} id="course" role="combobox" aria-autocomplete="list" aria-expanded={items.length > 0} aria-controls="course-options"
        aria-activedescendant={index >= 0 ? `suggestion-${index}` : undefined} placeholder="MATH 5A or a class title" value={query}
        autoComplete="off" autoCorrect="off" autoCapitalize="characters" spellCheck={false} enterKeyHint="search"
        onFocus={() => setOpen(true)} onBlur={() => setTimeout(() => setOpen(false), 120)} onChange={e => { setQuery(e.target.value); setOpen(true) }}
        onKeyDown={e => {
          if (e.key === 'ArrowDown' && items.length) { e.preventDefault(); setIndex(i => Math.min(i + 1, items.length - 1)) }
          if (e.key === 'ArrowUp' && items.length) { e.preventDefault(); setIndex(i => Math.max(i - 1, 0)) }
          if (e.key === 'Escape') { setOpen(false); setItems([]) }
          if (e.key === 'Enter' && index >= 0 && items[index]) { e.preventDefault(); pick(items[index].course.display) }
        }} />
      {query && <button type="button" className="clear" aria-label="Clear" onMouseDown={e => e.preventDefault()} onClick={() => { setQuery(''); input.current?.focus() }}>×</button>}
    </div>
    {(items.length > 0 || showRecent) && <div className="suggestions">
      {items.length > 0 && <><div className="eyebrow">Classes</div>
        <ul id="course-options" role="listbox">{items.map((s, i) =>
          <li id={`suggestion-${i}`} key={s.course.key} role="option" aria-selected={index === i} className={index === i ? 'active' : ''} onMouseDown={e => { e.preventDefault(); pick(s.course.display) }}>
            <span className="code">{s.course.display}</span><span>{mark(s.title)}</span>
          </li>)}</ul></>}
      {showRecent && <><div className="eyebrow">Recent</div>
        <ul>{recent.map(r => <li key={r.display} onMouseDown={e => { e.preventDefault(); pick(r.display) }}><span className="code">{r.display}</span><span className="muted">{r.title}</span></li>)}</ul></>}
    </div>}
  </div>
}

function SearchView(props: { terms: Term[]; termCode: string; setTermCode: (t: string) => void; query: string; setQuery: (q: string) => void; days: Weekday[]; setDays: React.Dispatch<React.SetStateAction<Weekday[]>>; recent: Recent[]; search: (q?: string) => void; error: string }) {
  const { terms, termCode, setTermCode, query, setQuery, days, setDays, recent, search, error } = props
  const toggle = (d: Weekday) => setDays(prev => prev.includes(d) ? prev.filter(x => x !== d) : WEEKDAYS.map(w => w.key).filter(k => k === d || prev.includes(k)))
  return <div className="screen search-screen">
    <header className="topbar">
      <a className="home" href="../" aria-label="BYE home"><Wordmark /><span className="tagline">Before You Enroll</span></a>
      <a className="text-link" href="../">About</a>
    </header>
    <main className="search-main">
      <form className="search-form" onSubmit={e => { e.preventDefault(); search() }}>
        <div>
          <span className="eyebrow wide-only">For PCC students · web demo</span>
          <h1>Find your <span className="swipe">professor.</span></h1>
          <p className="muted">Every section of a PCC class, with ratings and reviews.</p>
        </div>
        <div className="field">
          <label htmlFor="course">Class</label>
          <CourseField term={termCode} query={query} setQuery={setQuery} onPick={q => search(q)} recent={recent} />
        </div>
        <div className="field">
          <label htmlFor="term">Semester</label>
          <select id="term" value={termCode} disabled={!terms.length} onChange={e => setTermCode(e.target.value)}>
            {!terms.length && <option value="">Loading semesters…</option>}
            {terms.map(t => <option key={t.termCode} value={t.termCode}>{t.termName}</option>)}
          </select>
        </div>
        <div className="field">
          <div className="row"><span className="label" id="days-label">Class days</span>{days.length ? <button type="button" className="text-link" onClick={() => setDays([])}>Clear</button> : <span className="muted small">Optional</span>}</div>
          <div className="days" role="group" aria-labelledby="days-label">{WEEKDAYS.map(d =>
            <button type="button" key={d.key} className="day" aria-pressed={days.includes(d.key)} aria-label={d.label} onClick={() => toggle(d.key)}>{d.short}</button>)}</div>
          <span className="muted small">Only classes meeting on these days. Online classes always show.</span>
        </div>
        {error && <p className="notice" role="alert"><b>Problem</b> {error}</p>}
        <div className="examples"><span className="muted small">Try</span>{EXAMPLES.map(x => <button key={x} type="button" className="chip" onClick={() => { setQuery(x); search(x) }}>{x}</button>)}</div>
        <div className="search-action"><button className="button primary wide" type="submit" disabled={!termCode || !query.trim()}>Find professors <span aria-hidden="true">→</span></button></div>
      </form>
    </main>
  </div>
}

function ProfessorCard({ p, selected, onOpen }: { p: Professor; selected: boolean; onOpen: () => void }) {
  const formats = [...new Set(p.sections.map(formatLabel))].join(', ')
  const where = `${plural(p.sections.length, 'section')} · ${formats}`
  const className = `prof-card${selected ? ' selected' : ''}${unnamed(p) ? ' dashed' : ''}`
  if (p.profile) return <button className={className} aria-pressed={selected} onClick={onOpen}>
    <b className="name">{p.name}</b><span className="big">{score(p.profile.rating)}</span>
    <small>Difficulty {score(p.profile.difficulty)}{p.profile.wouldTakeAgain === undefined ? '' : ` · ${p.profile.wouldTakeAgain}% would take again`}</small>
    <small>{where}</small>
    <Bar value={p.profile.rating} label="Rating" />
  </button>
  if (p.state === 'choose') return <button className={className} aria-pressed={selected} onClick={onOpen}>
    <b className="name">{p.name}</b><span className="side-action">Choose →</span>
    <small className="ink">{p.candidates.length > 1 ? `${p.candidates.length} RMP profiles match` : 'Choose an RMP profile'}</small><small>{where}</small>
  </button>
  if (p.state === 'unavailable') return <button className={className} aria-pressed={selected} onClick={onOpen}>
    <b className="name">{p.name}</b>{!unnamed(p) && <span className="big muted">—</span>}
    <small>{unnamed(p) ? "PCC hasn't named an instructor yet" : <><span className="signal">Cannot retrieve RMP info.</span> Tap to try again.</>}</small><small>{where}</small>
  </button>
  return <button className={className} aria-pressed={selected} aria-busy="true" onClick={onOpen}>
    <b className="name">{p.name}</b><span className="big muted">—</span><small>Checking RMP…</small><small>{where}</small>
  </button>
}

function SectionCard({ s, days }: { s: Section; days: Weekday[] }) {
  const seats = demoSeats[s.crn], full = seats && seats.open === 0, other = !fits(s, days)
  return <article className={`section-card${other ? ' other-days' : ''}`}>
    <div>
      <div className="tags"><span className="chip">CRN {s.crn}</span><span className="tag">{formatLabel(s)}</span>{other && <span className="tag outline">Other days</span>}</div>
      {s.meetings.length ? s.meetings.map(m => <p className="when" key={m}>{m}</p>) : <p className="when">No scheduled meetings</p>}
      <p className="muted small">{day(s.start)} – {day(s.end)}</p>
    </div>
    {seats && <div className={`seats${full ? ' full' : ''}`}>
      <div className="seats-label"><b>{seats.open}</b> of {seats.capacity} seats open</div>
      <div className="seats-bar"><i style={{ width: `${(seats.open / seats.capacity) * 100}%` }} /></div>
      <div className="seats-wait">{full ? `Full · waitlist ${seats.waitlist} of ${seats.waitCapacity}` : `Waitlist ${seats.waitlist} of ${seats.waitCapacity}`}</div>
    </div>}
  </article>
}

function Report({ p, course, days, back, command }: { p: Professor; course: Course; days: Weekday[]; back: () => void; command: (c: Command) => void }) {
  const [filter, setFilter] = useState('this'), [sort, setSort] = useState('recent'), [visible, setVisible] = useState(4)
  useEffect(() => { setFilter('this'); setVisible(4) }, [p.id])
  const profile = p.profile
  const reviews = profile ? orderReviews(filterReviews(profile, course, filter), sort) : []
  const counts = profile?.courseCounts.filter(x => x.label) ?? []
  const thisCount = counts.find(x => sameCourse(course, x.label))?.count
  const chips = [{ value: 'this', label: `This class${thisCount === undefined ? '' : ` · ${thisCount}`}` }, { value: 'all', label: 'All' },
    ...counts.filter(x => !sameCourse(course, x.label)).map(x => ({ value: x.label, label: `${courseLabel(x.label)}${x.count === undefined ? '' : ` · ${x.count}`}` }))]
  return <article className="report" aria-label={`Report for ${p.name}`}>
    <header className="report-bar">
      <button className="back" onClick={back}><span aria-hidden="true">←</span> Professors</button>
      <span className="chip">{course.display}</span>
    </header>
    <div className="report-body">
      <div>
        <span className="eyebrow">Professor report</span>
        <h2 className="report-name">{p.name}</h2>
        <p className="meta">{profile?.department ? `${profile.department} · ` : ''}Pasadena City College
          {p.candidates.length > 1 && profile && <button className="text-link" onClick={() => command({ kind: 'discover', professorId: p.id })}>Change profile</button>}</p>
      </div>

      {(p.state === 'loading' || p.state === 'pending') && <p className="placeholder" role="status">Checking RMP for {p.name}…</p>}
      {p.state === 'choose' && <div className="callout"><p><b>{p.candidates.length} RMP profiles match {p.name}.</b> Pick the one that teaches {course.display}. BYE keeps them separate and never guesses.</p>
        <button className="button primary wide" onClick={() => command({ kind: 'discover', professorId: p.id })}>Choose profile <span aria-hidden="true">→</span></button></div>}
      {p.state === 'unavailable' && (unnamed(p)
        ? <div className="callout"><p><b>No instructor named yet.</b> PCC hasn't announced who teaches this section. Check back closer to the start of the semester.</p></div>
        : <div className="callout card" role="status"><p><b className="signal">Cannot retrieve RMP info.</b> {p.issue} The class sections below are still up to date.</p>
          <button className="button secondary wide" onClick={() => command({ kind: 'retry', professorId: p.id })}>Try again</button></div>)}

      {profile && <section aria-label="Scores" className="block">
        <div className="stats">
          <div className="stat"><b>{score(profile.rating)}<small>/5</small></b><span>Rating</span><Bar value={profile.rating} label="Rating" /></div>
          <div className="stat"><b>{score(profile.difficulty)}<small>/5</small></b><span>Difficulty</span><Bar value={profile.difficulty} label="Difficulty" /></div>
          <div className="stat"><b>{profile.wouldTakeAgain === undefined ? '—' : `${profile.wouldTakeAgain}%`}</b><span>Would take again</span></div>
        </div>
        <p className="muted small">{plural(profile.ratingCount ?? 0, 'rating')} across all courses · lower difficulty means easier · sample data</p>
      </section>}

      <section className="block">
        <h3>Sections <span className="muted">· {p.sections.length}</span></h3>
        <div className="section-list">{p.sections.map(s => <SectionCard key={s.crn} s={s} days={days} />)}</div>
      </section>

      {profile && <section className="block">
        <div className="row"><h3>Student reviews</h3>
          <select className="bare-select" aria-label="Sort reviews" value={sort} onChange={e => setSort(e.target.value)}>
            <option value="recent">Newest</option><option value="highest">Highest rating</option><option value="lowest">Lowest rating</option><option value="difficulty">Lowest difficulty</option>
          </select></div>
        <div className="chip-row" role="group" aria-label="Review course">{chips.map(c =>
          <button key={c.value} type="button" className="pill" aria-pressed={filter === c.value} onClick={() => { setFilter(c.value); setVisible(4) }}>{c.label}</button>)}</div>
        {p.detailLoading && <p className="muted small" role="status">Quick preview · loading every review…</p>}
        {reviews.slice(0, visible).map(r => <article className="review-card" key={r.id}>
          <div className="row"><span className="chip">{courseLabel(r.course) || 'Course unspecified'}</span><span className="muted small">Posted {monthYear(r.date)}</span></div>
          <p>{r.text}</p>
          <p className="muted small">Rating {r.rating ?? '—'} · Difficulty {r.difficulty ?? '—'}</p>
        </article>)}
        {!reviews.length && !p.detailLoading && <p className="muted">No reviews match this filter. Try All.</p>}
        {visible < reviews.length && <button className="button secondary wide" onClick={() => setVisible(n => n + 6)}>Show more reviews</button>}
        <p className="muted small center">Ratings reflect student feedback. They don't guarantee a grade.</p>
      </section>}
    </div>
  </article>
}

function Chooser({ p, course, command, onSelect }: { p?: Professor; course?: Course; command: (c: Command) => void; onSelect: (profileId: string) => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => {
    const dialog = ref.current
    if (p?.choosing && dialog && !dialog.open) dialog.showModal()
    if (!p?.choosing && dialog?.open) dialog.close()
  }, [p?.choosing, p?.id])
  const close = () => { if (p) command({ kind: 'dismiss', professorId: p.id }) }
  return <dialog ref={ref} className="sheet" aria-labelledby="chooser-title" onCancel={e => { e.preventDefault(); close() }} onClick={e => { if (e.target === ref.current) close() }}>
    <span className="grabber" aria-hidden="true" />
    <h2 id="chooser-title">Which {p?.name} teaches {course?.display ?? 'this class'}?</h2>
    <p className="muted">{p && p.candidates.length > 1 ? `${p.candidates.length} Rate My Professors profiles share this name.` : 'Confirm the Rate My Professors profile.'} Pick one and BYE will remember it for {course?.subject ?? 'this subject'} classes.</p>
    {!p?.candidates.length && <p className="muted" role="status">Looking for profiles…</p>}
    {p?.candidates.map((c, i) => <div className="candidate" key={c.id}>
      <b>{c.firstName} {c.lastName}</b>
      <span>{c.department || 'Department unavailable'}</span>
      <span className="muted small">Pasadena City College · {plural(c.ratingCount ?? 0, 'rating')}</span>
      <button className={`button ${i === 0 ? 'primary' : 'secondary'} wide`} onClick={() => onSelect(c.id)}>Use this profile</button>
    </div>)}
    <button className="button ghost wide" onClick={close}>Not now</button>
  </dialog>
}

function App() {
  const [state, setState] = useState(empty), [terms, setTerms] = useState<Term[]>([]), [termCode, setTermCode] = useState('')
  const [query, setQuery] = useState(''), [screen, setScreen] = useState<Screen>('search'), [error, setError] = useState('')
  const [selected, setSelected] = useState(''), [sort, setSort] = useState('rating'), [days, setDays] = useState<Weekday[]>([])
  const [showOther, setShowOther] = useState(false), [recent, setRecent] = useState<Recent[]>(loadRecent)
  const lastOperation = useRef(''), opened = useRef(''), listScroll = useRef(0)
  const command = (c: Command) => { bridge.command(c).catch(e => setError(e instanceof Error ? e.message : 'This action failed. Try again.')) }

  // Each screen is a history entry, so the phone's back gesture returns to the previous screen instead of leaving.
  function go(next: Screen) {
    if (next === screen) return
    if (screen === 'list') listScroll.current = window.scrollY
    history.pushState({ bye: next }, ''); setScreen(next); window.scrollTo(0, 0)
  }
  useEffect(() => {
    history.replaceState({ bye: 'search' }, '')
    const onPop = (e: PopStateEvent) => {
      const next: Screen = e.state?.bye ?? 'search'
      setScreen(next)
      if (next === 'list') requestAnimationFrame(() => window.scrollTo(0, listScroll.current))
    }
    addEventListener('popstate', onPop)
    const unsubscribe = bridge.subscribe(setState)
    bridge.command({ kind: 'terms' }).then(r => { const t = r as Term[]; setTerms(t); setTermCode(t[0]?.termCode ?? '') })
    return () => { removeEventListener('popstate', onPop); unsubscribe() }
  }, [])
  useEffect(() => { if (state.operationId !== lastOperation.current) { lastOperation.current = state.operationId; opened.current = ''; setSelected(''); setShowOther(false) } }, [state.operationId])

  const course = state.course
  const title = titleCase(state.professors[0]?.sections[0]?.title ?? '')
  useEffect(() => {
    if (!course) return
    const next = [{ display: course.display, title }, ...loadRecent().filter(r => r.display !== course.display)].slice(0, 3)
    saveRecent(next); setRecent(next)
  }, [course?.key])

  const sorted = course ? orderProfessors(state.professors, sort, course) : state.professors
  const fitting = sorted.filter(p => p.sections.some(s => fits(s, days)))
  const otherDays = sorted.filter(p => !fitting.includes(p))
  const list = showOther ? [...fitting, ...otherDays] : fitting
  const p = state.professors.find(x => x.id === selected) ?? list[0]
  const chooser = state.professors.find(x => x.choosing)

  // Load every review once a report is open and the quick previews have settled, like the desktop app.
  useEffect(() => {
    if (!p?.profile || p.state !== 'ready' || state.previewPending) return
    if (isPhone() && screen !== 'report') return
    const key = `${state.operationId}|${p.id}|${p.profile.id}`
    if (opened.current !== key) { opened.current = key; command({ kind: 'details', professorId: p.id }) }
  }, [p?.id, p?.profile?.id, p?.state, state.previewPending, screen])

  function search(text = query) {
    const term = terms.find(t => t.termCode === termCode)
    if (!term || !text.trim()) return
    setError(''); command({ kind: 'search', query: text, term }); go('list')
  }
  function open(x: Professor) {
    setSelected(x.id)
    if (x.state === 'choose') command({ kind: 'discover', professorId: x.id })
    else if (isPhone()) go('report')
  }
  const back = () => history.back()
  const checked = state.professors.filter(x => x.state !== 'pending' && x.state !== 'loading').length
  const sections = state.professors.reduce((n, x) => n + x.sections.length, 0)
  const dayText = days.length ? ` · ${days.join(', ')}` : ''

  return <div className="app">
    <DemoBanner />
    {screen === 'search' ? <SearchView terms={terms} termCode={termCode} setTermCode={setTermCode} query={query} setQuery={setQuery} days={days} setDays={setDays} recent={recent} search={search} error={error} /> :
      <div className={`screen results on-${screen}`}>
        <header className="results-bar">
          <div className="results-row">
            <button className="icon-button" onClick={back} aria-label="Change search"><span aria-hidden="true">←</span></button>
            <a className="home wide-only" href="../" aria-label="BYE home"><Wordmark /></a>
            <div className="results-title">
              <span className="title-line">{course ? <span className="chip">{course.display}</span> : <span className="muted">Finding sections…</span>}{title && <span className="course-title">{title}</span>}</span>
              <span className="muted small">{state.term?.termName}{dayText}</span>
            </div>
            {state.loading ? <button className="text-link" onClick={() => command({ kind: 'stop' })}>Stop</button> : <button className="text-link" onClick={back}>Edit</button>}
          </div>
          {state.professors.length > 0 && state.loading && <div className="progress" role="status">
            <span className="bar thin" role="progressbar" aria-label="Checking RMP" aria-valuemin={0} aria-valuemax={state.professors.length} aria-valuenow={checked}><i style={{ width: `${(checked / state.professors.length) * 100}%` }} /></span>
            <span>Checking RMP… {checked} of {state.professors.length}</span>
          </div>}
        </header>
        <div className="panes">
          <aside className="list-pane" aria-label="Professors">
            <div className="row baseline"><h1 className="list-title">Professors</h1>{course && <span className="muted small">{plural(state.professors.length, 'professor')} · {plural(sections, 'section')}</span>}</div>
            <div className="chip-row" role="group" aria-label="Sort professors">{[['rating', 'Rating'], ['difficulty', 'Difficulty'], ['reviews', 'Reviews']].map(([value, label]) =>
              <button key={value} type="button" className="pill" aria-pressed={sort === value} onClick={() => setSort(value)}>{label}</button>)}</div>
            {state.issue && <p className="notice" role="status"><b>Problem</b> {state.issue}</p>}
            {error && <p className="notice" role="alert"><b>Problem</b> {error}</p>}
            {!course && state.loading && <p className="placeholder" role="status">Reading the PCC schedule…</p>}
            <div className="card-list">{list.map(x => <ProfessorCard key={x.id} p={x} selected={!isPhone() && p?.id === x.id} onOpen={() => open(x)} />)}</div>
            {otherDays.length > 0 && <p className="muted small other-note">{plural(otherDays.length, 'professor')} only {otherDays.length === 1 ? 'teaches' : 'teach'} on other days. <button className="text-link" onClick={() => setShowOther(v => !v)}>{showOther ? 'Hide' : 'Show'}</button></p>}
          </aside>
          <section className="report-pane">{p && course ? <Report p={p} course={course} days={days} back={back} command={command} /> :
            !state.loading && <div className="empty"><h2>No sections to show</h2><p className="muted">Try another class, like MATH 5A.</p></div>}</section>
        </div>
      </div>}
    <Chooser p={chooser} course={course} command={command} onSelect={profileId => {
      if (!chooser) return
      command({ kind: 'select', professorId: chooser.id, profileId }); setSelected(chooser.id)
      if (isPhone() && screen === 'list') go('report')
    }} />
  </div>
}

createRoot(document.getElementById('root')!).render(<App />)
