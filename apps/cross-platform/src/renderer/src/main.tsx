import React, { useEffect, useRef, useState } from 'react'
import { createRoot } from 'react-dom/client'
import type { Bridge, Command, Course, Professor, Section, Snapshot, Suggestion, Term, Weekday } from '../../shared/types'
import { REVIEW_SORTS, WEEKDAYS, dateLabel, displayTitle, excerpt, filterFinished, filterReviews, filterSections, formatLabel, fullyOnline, orderProfessors, orderReviews, preferredFilter, requestLabel, sameCourse, scheduleNotAnnounced } from '../../shared/domain'
import { AI_SUMMARIES_ENABLED, AI_SUMMARIES_UNAVAILABLE_NOTE } from '../../shared/features'
import './style.css'
declare global { interface Window { bye: Bridge } }
// The layout follows the Mac app's 0.4.0 screens (Sources/Classwise/Views); keep the two in step.
const empty: Snapshot = { operationId: '', professors: [], loading: false, previewPending: 0 }
const score = (n?: number) => n === undefined ? '—' : n.toFixed(1)
const plural = (n: number, word: string) => `${n} ${n === 1 ? word : word + 's'}`
const PROFESSOR_SORTS = [['rating', 'Highest rated'], ['difficulty', 'Lowest difficulty'], ['reviews', 'Student reviews']] as const
const DISCLAIMER = 'Ratings reflect student feedback across reviewed courses. They don’t guarantee a grade.'
type Run = (command: Command) => void

/** The BYE wordmark: Libre Baskerville Bold over a yellow highlighter swipe. */
function Brand({ compact = false }: { compact?: boolean }) {
  return <span className={`brand${compact ? ' compact' : ''}`} role="img" aria-label="BYE, Before You Enroll"><b className="wordmark">BYE</b>{!compact && <span className="muted">Before You Enroll</span>}</span>
}
const Eyebrow = ({ children }: { children: React.ReactNode }) => <span className="eyebrow">{children}</span>
const Chip = ({ children }: { children: React.ReactNode }) => <span className="chip">{children}</span>
const Tag = ({ children, kind = 'info' }: { children: React.ReactNode; kind?: 'info' | 'term' | 'signal' }) => <span className={`tag ${kind}`}>{children}</span>
const RatingBar = ({ value }: { value?: number }) => <span className="rating-bar" aria-hidden="true"><i style={{ width: `${Math.min(1, Math.max(0, (value ?? 0) / 5)) * 100}%` }} /></span>

function DaysPicker({ days, setDays }: { days: Weekday[]; setDays: (days: Weekday[]) => void }) {
  const toggle = (day: Weekday) => setDays(WEEKDAYS.map(d => d.key).filter(k => k === day ? !days.includes(day) : days.includes(k)))
  return <div className="days-picker">
    <div className="row"><span className="field-label" id="days-label">Class days</span>{days.length > 0 && <button type="button" className="text-link" onClick={() => setDays([])}>Clear</button>}</div>
    <div className="days" role="group" aria-labelledby="days-label">{WEEKDAYS.map(d =>
      <button type="button" key={d.key} className="day" aria-pressed={days.includes(d.key)} aria-label={d.label} onClick={() => toggle(d.key)}>{d.short}</button>)}</div>
    <span className="muted small">{days.length ? 'Shows classes that meet on every picked day. Fully online classes still show.' : 'Any day'}</span>
  </div>
}
function OnlineToggle({ onlineOnly, setOnlineOnly }: { onlineOnly: boolean; setOnlineOnly: (on: boolean) => void }) {
  return <label className="checkbox"><input type="checkbox" checked={onlineOnly} onChange={e => setOnlineOnly(e.target.checked)} /> Fully online only</label>
}

/** Open seats with a capacity bar and the waitlist, from PCC's schedule. */
function SeatMeter({ s }: { s: Section }) {
  const d = s.details, open = d?.seatsOpen
  if (open === undefined) return <div className="seat-meter"><span className="muted small">Seats unavailable</span></div>
  const full = open === 0, count = d?.waitlistCount, capacity = d?.waitlistCapacity
  const wait = count === undefined ? '' : capacity === undefined ? `Waitlist ${count}` : `Waitlist ${count} of ${capacity}`
  const waitlist = full ? (wait ? 'Full · ' + wait.toLowerCase() : 'Full') : wait
  // The bar fills as seats are taken, so a full class reads as a full bar: black while plentiful, yellow at 10 or fewer, red at 5 or fewer.
  const taken = d?.capacity ? Math.min(1, Math.max(0, (d.capacity - open) / d.capacity)) : 0
  return <div className="seat-meter" role="img" aria-label={`${open} seats open. ${waitlist}`}>
    <div><b className="seat-count">{open}</b> <span className="muted small">{d?.capacity === undefined ? (open === 1 ? 'seat open' : 'seats open') : `of ${d.capacity} seats open`}</span></div>
    <span className="seat-bar"><i className={open <= 5 ? 'low' : open <= 10 ? 'few' : ''} style={{ width: `${taken * 100}%` }} /></span>
    {waitlist && <span className={`small ${full ? 'signal' : 'muted'}`}>{waitlist}</span>}
  </div>
}
/** One PCC section: CRN, format and term tags, schedule, location and units, and open seats. */
function ClassCard({ s }: { s: Section }) {
  const d = s.details
  const detail = [d?.campus && !fullyOnline(s) ? d.campus : '', dateLabel(s), d?.units ? (d.units === '1' ? '1 unit' : `${d.units} units`) : ''].filter(Boolean).join(' · ')
  return <article className="class-card">
    <div className="class-main">
      <div className="tags"><Chip>CRN {s.crn}</Chip><Tag>{formatLabel(s)}</Tag>{d?.termPart && <Tag kind="term">{d.termPart}</Tag>}</div>
      {fullyOnline(s) ? <p className="when">No scheduled meetings</p> : !s.meetings.length ? <p className="when">Schedule not announced</p> : <>
        {s.meetings.map(m => <p className="when" key={m}>{m}</p>)}
        {scheduleNotAnnounced(s) && !s.meetings.some(m => m.includes('TBA') || m.includes('no set')) && <p className="muted small">Some meetings not announced</p>}
      </>}
      <p className="muted small">{detail}</p>
    </div>
    <SeatMeter s={s} />
  </article>
}
function ScoreCard({ value, title, helper }: { value?: number; title: string; helper: string }) {
  return <div className="score-card" role="group" aria-label={`${title}: ${value === undefined ? 'not available' : `${value.toFixed(1)} out of 5`}. ${helper}`}>
    <div><b className="score">{score(value)}</b>{value !== undefined && <span className="muted out-of">/ 5</span>}</div>
    <strong>{title}</strong>
    <span className="muted small">{value === undefined ? 'Not available' : helper}</span>
  </div>
}

function SearchScreen(props: { terms: Term[]; termLoading: boolean; termCode: string; setTermCode: (code: string) => void; query: string; setQuery: (q: string) => void; days: Weekday[]; setDays: (d: Weekday[]) => void; onlineOnly: boolean; setOnlineOnly: (on: boolean) => void; pending: boolean; progress: string; error: string; search: (text?: string) => void; cancel: () => void; retryTerms: () => void }) {
  const { terms, termLoading, termCode, setTermCode, query, setQuery, pending, error, search } = props
  const [focused, setFocused] = useState(false), [items, setItems] = useState<Suggestion[]>([]), [index, setIndex] = useState(-1)
  const sequence = useRef(0), input = useRef<HTMLInputElement>(null)
  useEffect(() => { input.current?.focus() }, [])
  useEffect(() => {
    const id = ++sequence.current
    if (!termCode || !query.trim() || !focused) { setItems([]); return }
    const timer = setTimeout(() => {
      window.bye.command({ kind: 'suggest', term: termCode, query }).then(result => { if (sequence.current === id) { setItems(result as Suggestion[]); setIndex(-1) } }).catch(() => { if (sequence.current === id) setItems([]) })
    }, 180)
    return () => clearTimeout(timer)
  }, [query, termCode, focused])
  // Open only while typing: closed when the field is empty, unfocused, or already holds an exact course code.
  const open = focused && items.length > 0 && !items.some(s => s.course.display.toLowerCase() === query.trim().toLowerCase())
  const choose = (s: Suggestion) => { setQuery(s.course.display); setItems([]); input.current?.focus() }
  return <div className="screen search-screen">
    <header className="search-top"><Brand /><span className="college">Pasadena City College</span></header>
    <main className="search-main">
      <form className="search-form" onSubmit={e => { e.preventDefault(); if (open && index >= 0 && items[index]) choose(items[index]); else if (!pending) search() }}>
        <Eyebrow>A little clarity before you enroll</Eyebrow>
        <h1 className="hero">Find your<br /><span className="swipe">professor.</span></h1>
        <p className="lead muted">Your class. Your semester. A clearer choice.</p>
        <div className="search-fields">
          <div className="field course-field">
            <label htmlFor="course" className="field-label">Class</label>
            <input ref={input} id="course" role="combobox" aria-autocomplete="list" aria-expanded={open} aria-controls="course-options" aria-activedescendant={open && index >= 0 ? `suggestion-${index}` : undefined}
              aria-description="For example, ETH 014 or POLS C1000" placeholder="Enter your course" value={query} autoComplete="off" spellCheck={false}
              onFocus={() => setFocused(true)} onBlur={() => setFocused(false)} onChange={e => setQuery(e.target.value)} onKeyDown={e => {
                if (e.key === 'ArrowDown' && open) { e.preventDefault(); setIndex(i => Math.min(i + 1, items.length - 1)) }
                if (e.key === 'ArrowUp' && open) { e.preventDefault(); setIndex(i => Math.max(i - 1, 0)) }
                if (e.key === 'Escape') setItems([])
              }} />
            {open && <ul className="suggestions" id="course-options" role="listbox" aria-label="Matching PCC courses">{items.map((s, i) =>
              <li id={`suggestion-${i}`} key={s.course.key} role="option" aria-selected={index === i} className={index === i ? 'active' : ''} onMouseDown={e => { e.preventDefault(); choose(s) }}>
                <span className="mono">{s.course.display}</span><span className="muted">{displayTitle(s.title)}</span>
              </li>)}</ul>}
            <span className="muted small">Example: ETH 014 or POLS C1000</span>
          </div>
          <div className="field term-field">
            <label htmlFor="term" className="field-label">Semester</label>
            <select id="term" value={termCode} disabled={termLoading || !terms.length} onChange={e => setTermCode(e.target.value)}>
              {!terms.length && <option value="">{termLoading ? 'Loading semesters…' : 'Select semester'}</option>}
              {terms.map(t => <option key={t.termCode} value={t.termCode}>{t.termName}</option>)}
            </select>
          </div>
        </div>
        <DaysPicker days={props.days} setDays={props.setDays} />
        <OnlineToggle onlineOnly={props.onlineOnly} setOnlineOnly={props.setOnlineOnly} />
        <div className="row start search-action">
          <button className="pill primary" type="submit" disabled={pending || !terms.length || !query.trim()}>Find professors <span aria-hidden="true">→</span></button>
          {pending && <><span className="spinner" aria-hidden="true" /><button type="button" className="text-link" onClick={props.cancel}>Cancel</button></>}
        </div>
        {pending && <p className="muted small" role="status">{props.progress}</p>}
        {error && <div role="alert"><p className="muted">{error}</p>{!terms.length && !termLoading && <button type="button" className="text-link" onClick={props.retryTerms}>Retry semesters</button>}</div>}
      </form>
    </main>
    <footer className="search-foot muted"><span>One simple search.</span><span>Made for a more informed choice.</span></footer>
  </div>
}

function ProfessorCard({ p, selected, select, run }: { p: Professor; selected: boolean; select: () => void; run: Run }) {
  const sections = plural(p.sections.length, 'section'), profile = p.profile
  return <div className={`professor-card${selected ? ' selected' : ''}`}>
    <button className="card-button" aria-pressed={selected} onClick={select}>
      <span className="card-top">
        <span className="card-text">
          <strong className="card-name">{p.name}</strong>
          {profile ? <>
            <span>Difficulty {score(profile.difficulty)} · {profile.wouldTakeAgain === undefined ? 'take-again rate unavailable' : `${Math.round(profile.wouldTakeAgain)}% would take again`}</span>
            <span>{profile.ratingCount === undefined ? 'Rating count unavailable' : `${profile.ratingCount} ratings`} · {sections}</span>
          </> : <>
            <span>{p.state === 'choose' ? 'Two or more RMP profiles · Choose profile' : p.state === 'unavailable' ? 'Cannot retrieve RMP info' : p.state === 'loading' ? 'Checking RMP…' : 'Not checked yet'}</span>
            <span>{sections}</span>
          </>}
        </span>
        <b className={`card-score${profile ? '' : ' muted'}`}>{score(profile?.rating)}</b>
      </span>
      {profile && <RatingBar value={profile.rating} />}
    </button>
    {p.state === 'choose' && <button className="text-link" onClick={() => run({ kind: 'discover', professorId: p.id })}>Choose profile</button>}
    {(p.state === 'unavailable' || p.state === 'pending') && <button className="text-link" onClick={() => run({ kind: 'retry', professorId: p.id })}>Try again</button>}
    {p.state === 'unavailable' && <button className="text-link muted" onClick={() => run({ kind: 'source', target: 'rmp', professorId: p.id })}>Check on RMP ↗</button>}
  </div>
}

/** What the results open on: neutral facts about the class and a nudge to pick a professor. It never names, ranks or recommends anyone. */
function CourseOverview({ course, title, summary, professors }: { course?: Course; title: string; summary: string; professors: Professor[] }) {
  const seen = new Set<string>(), sections = professors.flatMap(p => p.sections).filter(s => !seen.has(s.crn) && !!seen.add(s.crn))
  const known = sections.map(s => s.details?.seatsOpen).filter((n): n is number => n !== undefined)
  const breakdown = (labels: string[]) => [...labels.reduce((m, l) => m.set(l, (m.get(l) ?? 0) + 1), new Map<string, number>())].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).map(([l, n]) => `${l} ${n}`).join(' · ')
  const formats = breakdown(sections.map(formatLabel)), terms = breakdown(sections.map(s => s.details?.termPart ?? '').filter(Boolean))
  return <div className="overview" aria-label="Course overview">
    <Eyebrow>Course overview</Eyebrow>
    <div className="row start">{course && <Chip>{course.display}</Chip>}<span className="muted">{summary}</span></div>
    <h2 className="display-38">{title}</h2>
    <div className="stat-row">
      <div className="panel stat"><b>{sections.length}</b><span className="muted small">{sections.length === 1 ? 'section' : 'sections'}</span></div>
      <div className="panel stat"><b>{professors.length}</b><span className="muted small">{professors.length === 1 ? 'professor' : 'professors'}</span></div>
      <div className="panel stat"><b>{known.length ? known.reduce((a, b) => a + b, 0) : '—'}</b><span className="muted small">seats open</span></div>
    </div>
    {(formats || terms) && <dl className="facts">{formats && <><dt>Format</dt><dd className="muted">{formats}</dd></>}{terms && <><dt>Term</dt><dd className="muted">{terms}</dd></>}</dl>}
    <div className="nudge"><span aria-hidden="true">←</span><span>Choose a professor on the left to see their sections, ratings and student reviews.</span></div>
    <p className="muted small">{DISCLAIMER}</p>
  </div>
}

function Report({ p, course, state, run }: { p: Professor; course: Course; state: Snapshot; run: Run }) {
  const profile = p.profile
  const [filter, setFilterValue] = useState(() => preferredFilter(profile, course)), [chosen, setChosen] = useState(false)
  const [sort, setSort] = useState('recent'), [limit, setLimit] = useState(3)
  const root = useRef<HTMLElement>(null)
  useEffect(() => { setFilterValue(preferredFilter(profile, course)); setChosen(false); setSort('recent'); setLimit(3); root.current?.scrollTo(0, 0) }, [p.id, profile?.id, course.key])
  useEffect(() => { if (!chosen) setFilterValue(preferredFilter(profile, course)) }, [profile?.reviews.length])
  const setFilter = (value: string) => { setFilterValue(value); setChosen(true); setLimit(3) }
  const reviews = profile ? orderReviews(filterReviews(profile, course, filter), sort) : []
  const exact = profile?.reviews.filter(r => sameCourse(course, r.course)).length ?? 0
  const counts = new Map((profile?.courseCounts ?? []).filter(x => x.label).map(x => [x.label, x.count]))
  for (const review of profile?.reviews ?? []) if (review.course && !counts.has(review.course)) counts.set(review.course, undefined)
  const choices = [...counts].sort((a, b) => a[0].localeCompare(b[0], 'en', { numeric: true }))
  const all = profile?.coverage.all, complete = !!all && (!all.hasNextPage || all.reviewIDs.length >= 50)
  const checking = state.loading || state.previewPending > 0, label = requestLabel(course, filter)
  const name = profile ? `${profile.firstName} ${profile.lastName}` : p.name
  return <main className="report" ref={root} aria-label="Professor report">
    <header className="report-header">
      <Eyebrow>Professor profile</Eyebrow>
      <h2 className="display-38">{name}</h2>
      {profile ? <>
        <span className="muted">{[profile.department, profile.school].filter(Boolean).join(' · ')}</span>
        <button className="text-link" disabled={p.state === 'loading'} onClick={() => run({ kind: 'discover', professorId: p.id })}>Change profile</button>
        {p.issue && <span className="muted small">{p.issue}</span>}
        {name !== p.name && <span className="muted small">Listed at PCC as {p.name}</span>}
      </> : <span className="muted">Teaching {course.display} at Pasadena City College</span>}
    </header>
    <section className="stack" aria-label="PCC class sections">
      <Eyebrow>PCC class sections</Eyebrow>
      {p.sections.map(s => <ClassCard key={s.crn} s={s} />)}
      <div><button className="pill" onClick={() => run({ kind: 'source', target: 'pcc' })}>PCC schedule ↗</button></div>
    </section>
    {profile ? <>
      <div className="score-row">
        <ScoreCard value={profile.rating} title="Student rating" helper="Higher means better rated" />
        <ScoreCard value={profile.difficulty} title="Difficulty" helper="Lower means easier" />
      </div>
      <div className="row muted small"><span>{profile.ratingCount === undefined ? 'Overall rating count unavailable' : `Based on ${profile.ratingCount} RMP ratings across courses`}</span>{profile.wouldTakeAgain !== undefined && <span>{Math.round(profile.wouldTakeAgain)}% would take again</span>}</div>
      {AI_SUMMARIES_ENABLED ? <Summary p={p} course={course} run={run} /> : <p className="panel small muted" role="status">{AI_SUMMARIES_UNAVAILABLE_NOTE}</p>}
      <section className="stack" aria-label="Student reviews">
        <Eyebrow>Student reviews</Eyebrow>
        {!complete && <p className="muted small" role="status">{p.reviewIssue ?? (checking ? 'Quick preview · Up to three reviews. More feedback loads after everyone’s ratings are checked.' : p.detailLoading ? 'Quick preview · Loading more reviews for this professor…' : 'Quick preview · More feedback loads when you open this report.')}</p>}
        <div className="row">
          <select aria-label="Review course" className="review-filter" value={filter} onChange={e => setFilter(e.target.value)}>
            <option value="this">This course · {course.display}</option>
            <option value="all">All courses</option>
            {choices.map(([label, count]) => <option key={label} value={label}>{count === undefined ? `${label} (source count unavailable)` : `${label} (${count} on RMP)`}</option>)}
          </select>
          <select aria-label="Sort reviews" value={sort} onChange={e => { setSort(e.target.value); setLimit(3) }}>{REVIEW_SORTS.map(([value, text]) => <option key={value} value={value}>{text}</option>)}</select>
        </div>
        <p className="muted small">Showing {reviews.length} downloaded reviews for this filter (up to 50). Changing the filter uses saved reviews.</p>
        {filter === 'all' && exact === 0 && !chosen ? <p className="row start small muted">No reviews mention {course.display} yet, so all courses are shown.
          <button className="text-link" disabled={checking || p.detailLoading} onClick={() => { setFilter('this'); run({ kind: 'details', professorId: p.id, filter: course.key }) }}>Find {course.display} reviews</button></p>
          : filter === 'this' && exact === 0 && <p className="muted small">No downloaded reviews exactly match {course.display}. More may be available on RMP under this or another course label.</p>}
        {complete && p.reviewIssue && <p className="muted small" role="status">{p.reviewIssue}</p>}
        {label !== undefined && (!filterFinished(profile, course, filter) ? <div className="stack tight">
          <div><button className="pill" disabled={checking || p.detailLoading} onClick={() => run({ kind: 'details', professorId: p.id, filter: label })}>{p.detailLoading ? 'Loading reviews…' : 'Find more for this class'}</button></div>
          <p className="muted small">{filter === 'this' ? 'Requests this course label from RMP, as listed by PCC.' : 'Requests this class label from RMP. Reviews for other classes and overall scores stay separate.'}</p>
        </div> : <p className="muted small">Finished this filter’s retrieval, or reached the 50-rating limit. Source totals may include reviews without text.</p>)}
        {!reviews.length && <p className="muted">No review text available for this filter.</p>}
        {reviews.slice(0, limit).map(r => <article className="review" key={r.id}>
          <div className="review-heading">{r.course ? <strong className="chip">{r.course}</strong> : <strong>Course not specified</strong>}<span className="muted small">Rating {score(r.rating)}/5 · Difficulty {score(r.difficulty)}/5</span></div>
          <p className="review-text">{excerpt(r)}</p>
          <div className="row small"><span className="muted">{r.date ? `Posted ${r.date.slice(0, 10)}` : 'Posted date unavailable'}</span><button className="text-link plain" onClick={() => run({ kind: 'source', target: 'rmp', professorId: p.id })}>Original on RMP ↗</button></div>
        </article>)}
        {reviews.length > limit && <button className="pill wide" onClick={() => setLimit(n => n + 5)}>View more reviews</button>}
        <p className="muted small">Excerpts from accessible reviews, not the complete RMP review history. Dates indicate when reviews were posted.</p>
      </section>
    </> : <div className="panel stack">
      <h3 className="display-22">{p.state === 'choose' ? 'Choose profile' : p.state === 'unavailable' ? 'Cannot retrieve RMP info' : p.state === 'loading' ? 'Finding student feedback…' : 'Student feedback hasn’t been checked yet.'}</h3>
      <p className="muted">{p.issue ?? 'PCC sections are available above. Ratings and reviews will appear here when retrieved.'}</p>
      {p.state === 'unavailable' && <div><Tag kind="signal">Unavailable</Tag></div>}
      <div className="row start">
        {p.state === 'choose' && <button className="pill primary" onClick={() => run({ kind: 'discover', professorId: p.id })}>Choose profile</button>}
        {(p.state === 'unavailable' || p.state === 'pending' || (p.state === 'choose' && !p.candidates.length)) && <button className="pill" onClick={() => run({ kind: 'retry', professorId: p.id })}>Try again</button>}
        <button className="pill" onClick={() => run({ kind: 'source', target: 'rmp', professorId: p.id })}>Check on RMP ↗</button>
      </div>
    </div>}
    <div className="row start">
      <button className="pill" onClick={() => run({ kind: 'source', target: 'rmp', professorId: p.id })}>Rate My Professors ↗</button>
      <button className="pill" onClick={() => run({ kind: 'source', target: 'review', professorId: p.id })}>Write a review ↗</button>
    </div>
  </main>
}

// Retained for builds with the AI policy enabled; the current Windows policy keeps it off.
function Summary({ p, course, run }: { p: Professor; course: Course; run: Run }) {
  const summary = p.summary
  return <section className="panel stack" aria-label="AI review summary">
    <div className="row"><Eyebrow>AI review summary</Eyebrow><Tag kind="signal">Experimental</Tag></div>
    {summary ? <>
      <p className="summary-text">{summary.overview}</p>
      <p className="muted small">Local AI · on your PC · Analyzed {summary.analyzedCount} complete reviews of {p.profile?.reviews.length ?? 0} downloaded · {summary.exactCourseCount} for {course.display}</p>
      {([['Common positives', summary.positives], ['Common concerns', summary.concerns]] as const).map(([title, points]) => <div key={title}><strong className="small">{title}</strong>
        {points.length ? points.map(point => <p className="small" key={point.text}>• {point.text}</p>) : <p className="muted small">No verified recurring theme in this sample.</p>}</div>)}
    </> : <p className="muted" role="status">{p.summaryIssue ?? (p.summaryLoading ? 'Preparing a summary on your PC…' : 'A summary will be prepared when this report opens. Ratings and original reviews are already available below.')}</p>}
    {p.summaryIssue && <div><button className="pill" disabled={p.summaryLoading} onClick={() => run({ kind: 'summary', professorId: p.id })}>Retry summary</button></div>}
  </section>
}

function Chooser({ p, run }: { p?: Professor; run: Run }) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => {
    const dialog = ref.current
    if (p?.choosing && dialog && !dialog.open) dialog.showModal()
    if (!p?.choosing && dialog?.open) dialog.close()
  }, [p?.choosing, p?.id])
  const close = () => { if (p) run({ kind: 'dismiss', professorId: p.id }) }
  return <dialog ref={ref} className="chooser" aria-labelledby="chooser-title" onCancel={e => { e.preventDefault(); close() }}>
    <h2 id="chooser-title" className="display-24">Choose RMP profile</h2>
    {p && <>
      <strong>{p.name}</strong>
      <span className="muted">{[p.subject, p.subjectDescription].filter(Boolean).join(' · ')}</span>
      <p className="muted">Profiles stay separate. Choose the profile you want to use for this PCC instructor and subject.</p>
      {p.issue && <div className="stack tight"><p className="muted">{p.issue}</p><div><button className="pill" onClick={() => run({ kind: 'discover', professorId: p.id })}>Try again</button></div></div>}
      <div className="candidates">{p.candidates.map(c => <div className="panel candidate" key={c.id}>
        <strong>{c.firstName} {c.lastName}</strong>
        <span>Department: {c.department || 'Unavailable'}</span>
        <span className="muted">{c.school}</span>
        <div className="row">
          <button className="text-link plain" onClick={() => run({ kind: 'source', target: 'rmp', professorId: p.id, candidateId: c.id })}>View on RMP ↗</button>
          <button className="pill primary" aria-label={`Use this profile`} aria-description={`${c.firstName} ${c.lastName}, ${c.department || 'department unavailable'}, profile ${c.id}`} onClick={() => run({ kind: 'select', professorId: p.id, profileId: c.id })}>Use this profile</button>
        </div>
      </div>)}</div>
      {!p.candidates.length && !p.issue && <p className="muted">No eligible profile is available. Retry this professor or check the source.</p>}
    </>}
    <div className="row end"><button className="pill" onClick={close}>Close</button></div>
  </dialog>
}

function App() {
  const [state, setState] = useState(empty), [terms, setTerms] = useState<Term[]>([]), [termCode, setTermCode] = useState(''), [termLoading, setTermLoading] = useState(true)
  const [query, setQuery] = useState(''), [view, setView] = useState<'search' | 'results'>('search'), [pending, setPending] = useState(false), [error, setError] = useState('')
  const [days, setDays] = useState<Weekday[]>([]), [onlineOnly, setOnlineOnly] = useState(false), [sort, setSort] = useState('rating'), [showAll, setShowAll] = useState(false), [selected, setSelected] = useState('')
  const started = useRef(''), lastOperation = useRef(''), reportOpened = useRef(''), summarized = useRef('')
  const run: Run = command => { window.bye.command(command).catch(e => setError(e instanceof Error ? e.message : 'This action failed. Try again.')) }
  async function loadTerms() {
    setTermLoading(true); setError('')
    try { const result = await window.bye.command({ kind: 'terms' }) as Term[]; setTerms(result); setTermCode(old => result.some(t => t.termCode === old) ? old : result[0]?.termCode ?? ''); if (!result.length) setError('PCC has no published semesters right now.') }
    catch (e) { setError(e instanceof Error ? e.message : 'PCC semesters are unavailable. Try again.') }
    finally { setTermLoading(false) }
  }
  useEffect(() => { const unsubscribe = window.bye.subscribe(setState); void loadTerms(); return unsubscribe }, [])
  // A new search opens on the course overview; no professor opens automatically.
  useEffect(() => { if (state.operationId !== lastOperation.current) { lastOperation.current = state.operationId; setSelected(''); setShowAll(false); reportOpened.current = ''; summarized.current = '' } }, [state.operationId])
  useEffect(() => {
    if (!pending || state.operationId === started.current) return
    if (state.course) { setPending(false); setView('results'); setQuery(state.course.display) }
    else if (!state.loading) { setPending(false); if (state.issue) setError(state.issue) }
  }, [pending, state])

  const course = state.course
  const filtered = course ? orderProfessors(filterSections(state.professors, days, onlineOnly), sort, course) : []
  const displayed = showAll ? filtered : filtered.slice(0, 5)
  const p = filtered.find(x => x.id === selected), chooser = state.professors.find(x => x.choosing)
  // Incoming ratings may reorder the top five. Keep the report the student opened; if filters hide it, return to the course overview.
  useEffect(() => { if (selected && course && !filtered.some(x => x.id === selected)) setSelected('') })
  useEffect(() => {
    if (!p?.profile || p.state !== 'ready' || state.previewPending || state.loading) return
    const key = `${state.operationId}|${p.id}|${p.profile.id}`
    if (reportOpened.current !== key) { reportOpened.current = key; run({ kind: 'details', professorId: p.id }) }
  }, [p?.id, p?.profile?.id, p?.state, state.previewPending, state.loading])
  useEffect(() => {
    if (!AI_SUMMARIES_ENABLED || !p?.profile || p.detailLoading || p.state !== 'ready' || state.loading || state.previewPending) return
    const key = `${state.operationId}|${p.id}|${p.profile.id}|${JSON.stringify(p.profile.reviews)}`
    if (summarized.current !== key) { summarized.current = key; run({ kind: 'summary', professorId: p.id }) }
  }, [p?.id, p?.profile, p?.detailLoading, p?.state, state.loading, state.previewPending])

  function search(refresh = false, text = query) {
    const term = refresh ? state.term : terms.find(t => t.termCode === termCode)
    if (!term || !text.trim()) return
    setError(''); started.current = state.operationId
    if (!refresh) setPending(true)
    run({ kind: 'search', query: text, term, refresh })
  }
  const stop = () => { setPending(false); run({ kind: 'stop' }) }
  const checked = state.professors.filter(x => x.state !== 'pending' && x.state !== 'loading').length
  const sectionCount = new Set(filtered.flatMap(x => x.sections.map(s => s.crn))).size
  const title = displayTitle(state.professors[0]?.sections[0]?.title ?? '')
  const summary = [state.term?.termName ?? '', WEEKDAYS.filter(d => days.includes(d.key)).map(d => d.key).join(', '), onlineOnly ? 'Fully online' : ''].filter(Boolean).join(' · ')

  if (view === 'search') return <>
    <SearchScreen terms={terms} termLoading={termLoading} termCode={termCode} setTermCode={setTermCode} query={query} setQuery={setQuery} days={days} setDays={setDays} onlineOnly={onlineOnly} setOnlineOnly={setOnlineOnly}
      pending={pending} progress={state.professors.length ? `Checking ratings · ${checked} of ${state.professors.length}` : 'Finding classes at PCC…'} error={error} search={() => search()} cancel={stop} retryTerms={() => void loadTerms()} />
  </>
  return <div className="screen results">
    <header className="results-top">
      <Brand compact /><span className="divider" aria-hidden="true" />
      {course && <Chip>{course.display}</Chip>}
      <strong className="truncate">{title}</strong>
      <span className="muted truncate">{summary}</span>
      <span className="spacer" />
      <button className="pill" disabled={state.loading} onClick={() => course && search(true, course.display)}>Refresh</button>
      <button className="pill" onClick={() => { stop(); setError(''); setView('search') }}>Change search</button>
    </header>
    <div className="panes">
      <aside className="sidebar" aria-label="Professor results">
        <Eyebrow>Your options</Eyebrow>
        <h2 className="display-24">Professors</h2>
        <span className="muted small">{plural(sectionCount, 'section')} · {plural(filtered.length, 'professor')}</span>
        <select aria-label="Sort professors" value={sort} onChange={e => setSort(e.target.value)}>{PROFESSOR_SORTS.map(([value, text]) => <option key={value} value={value}>{text}</option>)}</select>
        <div className="filter-card">
          <span className="field-label">Filters</span>
          <OnlineToggle onlineOnly={onlineOnly} setOnlineOnly={setOnlineOnly} />
          <DaysPicker days={days} setDays={setDays} />
        </div>
        {state.loading && <p className="muted small">Ratings appear as each professor is checked. Pending results are not ranked yet.</p>}
        <div className="card-list">{displayed.map(x => <ProfessorCard key={x.id} p={x} selected={x.id === selected} select={() => { setSelected(x.id); setError('') }} run={run} />)}</div>
        {!showAll && filtered.length > 5 && <button className="pill wide" onClick={() => setShowAll(true)}>View all {filtered.length} professors</button>}
        {showAll && filtered.length > 5 && <div><button className="pill" onClick={() => setShowAll(false)}>Show top five</button></div>}
        <p className="muted small">{DISCLAIMER}</p>
      </aside>
      {p && course ? <Report key={p.id} p={p} course={course} state={state} run={run} /> : !filtered.length && !state.loading ? <div className="empty">
        <h2 className="display-28">No matching classes</h2>
        <p className="muted">{days.length ? (onlineOnly ? 'Try changing or clearing Class days, or turning off Fully online only.' : 'Try changing or clearing Class days to see other schedules.') : onlineOnly ? 'Try turning off Fully online only.' : state.issue ?? 'PCC may not offer this course in the selected semester.'}</p>
        <div className="row center">{days.length > 0 && <button className="pill primary" onClick={() => setDays([])}>Clear days</button>}{onlineOnly && <button className={`pill${days.length ? '' : ' primary'}`} onClick={() => setOnlineOnly(false)}>Show all formats</button>}</div>
        <button className="text-link plain" onClick={() => run({ kind: 'source', target: 'pcc' })}>Check PCC’s schedule ↗</button>
      </div> : <CourseOverview course={course} title={title} summary={summary} professors={filtered} />}
    </div>
    <footer className="results-foot">
      {state.loading ? <><span className="progress-meter" role="progressbar" aria-label="Progress" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(state.professors.length ? checked / state.professors.length * 100 : 0)}><i style={{ width: `${Math.max(8, 120 * (state.professors.length ? checked / state.professors.length : 0))}px` }} /></span>
        <span>{state.professors.length ? `Checking ratings · ${checked} of ${state.professors.length}` : 'Finding classes at PCC…'}</span><button className="text-link" onClick={stop}>Cancel</button></>
        : p?.detailLoading || p?.summaryLoading ? <><span className="spinner" aria-hidden="true" /><span>Loading this professor’s report…</span><button className="text-link" onClick={stop}>Stop loading</button></>
        : <><span className="dot" aria-hidden="true" /><span className="muted">{AI_SUMMARIES_ENABLED ? 'PCC schedule · Rate My Professors · AI summaries run on your PC' : 'PCC schedule · Rate My Professors'}</span></>}
      <span className="spacer" />
      {(error || state.issue) && <span className="muted" role="status">{error || state.issue}</span>}
    </footer>
    <Chooser p={chooser} run={run} />
  </div>
}
createRoot(document.getElementById('root')!).render(<App />)
