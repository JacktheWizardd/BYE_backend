import React, { useEffect, useRef, useState } from 'react'
import { createRoot } from 'react-dom/client'
import type { Bridge, Command, Professor, Snapshot, Suggestion, Term } from '../../shared/types'
import { delivery, filterReviews, orderProfessors, orderReviews } from '../../shared/domain'
import './style.css'
declare global { interface Window { bye: Bridge } }
const empty: Snapshot = { operationId: '', professors: [], loading: false, previewPending: 0 }
const score = (n?: number) => n === undefined ? '—' : n.toFixed(1)
function App() {
  const [state, setState] = useState(empty), [terms, setTerms] = useState<Term[]>([]), [termCode, setTermCode] = useState('')
  const [query, setQuery] = useState(''), [suggestions, setSuggestions] = useState<Suggestion[]>([]), [suggestionIndex, setSuggestionIndex] = useState(-1)
  const [selected, setSelected] = useState(''), [sort, setSort] = useState('rating'), [filter, setFilter] = useState('this'), [reviewSort, setReviewSort] = useState('recent')
  const [visible, setVisible] = useState(3), [error, setError] = useState(''), [searching, setSearching] = useState(false), [termLoading, setTermLoading] = useState(true)
  const dialogRef = useRef<HTMLDialogElement>(null), reportRef = useRef<HTMLElement>(null), sequence = useRef(0), lastOperation = useRef(''), reportOpened = useRef(''), summarized = useRef('')
  const p = state.professors.find(x => x.id === selected), c = state.course
  const command = async (cmd: Command) => { try { await window.bye.command(cmd) } catch (e) { setError(e instanceof Error ? e.message : 'This action failed. Try again.') } }
  async function loadTerms() {
    setTermLoading(true); setError('')
    try { const result = await window.bye.command({ kind: 'terms' }) as Term[]; setTerms(result); setTermCode(old => result.some(t => t.termCode === old) ? old : result[0]?.termCode ?? ''); if (!result.length) setError('PCC has no published semesters right now.') }
    catch (e) { setError(e instanceof Error ? e.message : 'PCC semesters are unavailable. Try again.') }
    finally { setTermLoading(false) }
  }
  useEffect(() => { const unsubscribe = window.bye.subscribe(setState); void loadTerms(); return unsubscribe }, [])
  useEffect(() => {
    if (state.operationId !== lastOperation.current) { lastOperation.current = state.operationId; setSelected(''); reportOpened.current = ''; summarized.current = ''; setFilter('this'); setVisible(3) }
    if (state.professors.length && !state.professors.some(x => x.id === selected)) setSelected(state.professors[0].id)
  }, [state.operationId, state.professors])
  useEffect(() => { if (state.course) setQuery(state.course.display) }, [state.course?.key])
  useEffect(() => {
    setFilter('this'); setVisible(3); summarized.current = ''; reportRef.current?.scrollTo(0, 0)
  }, [selected])
  useEffect(() => {
    if (!p?.profile || p.state !== 'ready' || state.previewPending || state.loading) return
    const key = `${state.operationId}|${p.id}|${p.profile.id}`
    if (reportOpened.current !== key) { reportOpened.current = key; void command({ kind: 'details', professorId: p.id }) }
  }, [selected, p?.profile?.id, p?.state, state.previewPending, state.loading])
  useEffect(() => {
    if (!p?.profile || p.detailLoading || p.state !== 'ready' || state.loading || state.previewPending) return
    const key = `${state.operationId}|${p.id}|${p.profile.id}|${JSON.stringify(p.profile.reviews)}`
    if (summarized.current !== key) { summarized.current = key; void command({ kind: 'summary', professorId: p.id }) }
  }, [selected, p?.profile, p?.detailLoading, p?.state, state.loading, state.previewPending])
  useEffect(() => {
    const dialog = dialogRef.current
    if (p?.choosing && dialog && !dialog.open) dialog.showModal()
    if (!p?.choosing && dialog?.open) dialog.close()
  }, [p?.choosing, selected])
  useEffect(() => {
    const id = ++sequence.current
    if (!termCode || !query.trim() || !searching) { setSuggestions([]); return }
    const timer = setTimeout(() => {
      window.bye.command({ kind: 'suggest', term: termCode, query }).then(result => { if (sequence.current === id) { setSuggestions(result as Suggestion[]); setSuggestionIndex(-1) } }).catch(() => { if (sequence.current === id) setSuggestions([]) })
    }, 180)
    return () => clearTimeout(timer)
  }, [query, termCode, searching])
  function search(refresh = false) {
    const term = terms.find(t => t.termCode === termCode); if (!term || !query.trim()) return
    setError(''); setSearching(false); setSuggestions([]); reportOpened.current = ''; summarized.current = ''
    void command({ kind: 'search', query, term, refresh })
  }
  const list = c ? orderProfessors(state.professors, sort, c) : state.professors
  const reviews = p?.profile && c ? orderReviews(filterReviews(p.profile, c, filter), reviewSort) : []
  const counts = new Map((p?.profile?.courseCounts ?? []).map(x => [x.label, x.count]))
  for (const review of p?.profile?.reviews ?? []) if (review.course && !counts.has(review.course)) counts.set(review.course, undefined)
  function chooseProfessor(professor: Professor) { setSelected(professor.id); setError('') }
  return <div className="app">
    <header className="header"><div className="brand"><span className="brand-mark">b.</span><div><strong>BYE</strong><span>Before You Enroll</span></div></div><span className="beta">Cross-platform beta · Windows</span></header>
    <section className="search-panel" aria-label="Course search">
      <div><h1>Find your class. Know your professor.</h1><p className="muted">Published PCC sections, student ratings, and feedback in one place.</p></div>
      <form className="search-form" onSubmit={e => { e.preventDefault(); if (suggestionIndex >= 0 && suggestions[suggestionIndex]) { setQuery(suggestions[suggestionIndex].course.display); searchWithSuggestion(suggestions[suggestionIndex].course.display) } else search() }}>
        <div className="course-field"><label htmlFor="course">Course</label><input id="course" role="combobox" aria-autocomplete="list" aria-expanded={suggestions.length > 0} aria-controls="course-options" aria-activedescendant={suggestionIndex >= 0 ? `suggestion-${suggestionIndex}` : undefined} placeholder="e.g. MATH 5A" value={query} autoComplete="off" onFocus={() => setSearching(true)} onChange={e => { setQuery(e.target.value); setSearching(true) }} onKeyDown={e => {
          if (e.key === 'ArrowDown' && suggestions.length) { e.preventDefault(); setSuggestionIndex(i => Math.min(i + 1, suggestions.length - 1)) }
          if (e.key === 'ArrowUp' && suggestions.length) { e.preventDefault(); setSuggestionIndex(i => Math.max(i - 1, 0)) }
          if (e.key === 'Escape') { setSearching(false); setSuggestions([]) }
        }} />
        {suggestions.length > 0 && <ul className="suggestions" id="course-options" role="listbox">{suggestions.map((s, i) => <li id={`suggestion-${i}`} key={s.course.key} role="option" aria-selected={suggestionIndex === i} onMouseDown={e => e.preventDefault()}><button type="button" tabIndex={-1} onClick={() => { setQuery(s.course.display); setSearching(false); setSuggestions([]) }}><strong>{s.course.display}</strong><span>{s.title}</span></button></li>)}</ul>}</div>
        <div><label htmlFor="term">Semester</label><select id="term" value={termCode} disabled={termLoading} onChange={e => setTermCode(e.target.value)}>{!terms.length && <option value="">{termLoading ? 'Loading semesters…' : 'Semesters unavailable'}</option>}{terms.map(t => <option key={t.termCode} value={t.termCode}>{t.termName}</option>)}</select></div>
        <button className="primary" type="submit" disabled={!termCode || !query.trim()}>Find classes <span aria-hidden="true">↗</span></button>
      </form>
      {error && <div className="notice" role="alert">{error}{!terms.length && <button onClick={() => void loadTerms()}>Retry semesters</button>}</div>}
    </section>
    {(state.loading || state.course || state.issue) ? <>
      <div className="results-toolbar"><div><h2>{c?.display ?? 'Finding your class…'}</h2><span className="muted">{state.term?.termName}{state.professors.length > 0 && ` · ${state.professors.reduce((n, x) => n + x.sections.length, 0)} sections · ${state.professors.length} professors`}</span></div><div className="actions">{state.loading || p?.detailLoading || p?.summaryLoading ? <button onClick={() => void command({ kind: 'stop' })}>Stop</button> : null}<button onClick={() => { if (c && state.term) { setQuery(c.display); void command({ kind: 'search', query: c.display, term: state.term, refresh: true }) } }}>Refresh</button><button onClick={() => void command({ kind: 'source', target: 'pcc' })}>PCC schedule ↗</button></div></div>
      {state.issue && <p className="notice" role="status">{state.issue}</p>}
      {state.professors.length > 0 && <div className="results">
        <aside className="professor-list" aria-label="Professors"><div className="list-heading"><h3>Professors</h3><select aria-label="Sort professors" value={sort} onChange={e => setSort(e.target.value)}><option value="rating">Highest rated</option><option value="difficulty">Lowest difficulty</option><option value="reviews">Same-course reviews</option></select></div>
        {list.map(professor => <button className={`professor-card ${selected === professor.id ? 'selected' : ''}`} key={professor.id} aria-pressed={selected === professor.id} onClick={() => chooseProfessor(professor)}><strong>{professor.name}</strong><span className="muted">{professor.sections.length} {professor.sections.length === 1 ? 'section' : 'sections'}</span><div className="mini-scores"><span><b>{score(professor.profile?.rating)}</b> Rating</span><span><b>{score(professor.profile?.difficulty)}</b> Difficulty</span></div><span className="card-status">{professor.state === 'choose' ? 'Choose profile' : professor.state === 'unavailable' ? 'Cannot retrieve RMP info' : professor.state === 'loading' || professor.state === 'pending' ? 'Checking ratings…' : `${professor.profile?.ratingCount ?? '—'} source ratings`}</span></button>)}</aside>
        <main className="report" ref={reportRef} aria-label="Professor report">
          {p && <><div className="report-heading"><div><span className="eyebrow">PROFESSOR REPORT</span><h2>{p.name}</h2><span className="muted">{p.profile?.department || 'Pasadena City College'}</span></div><button onClick={() => void command({ kind: 'source', target: 'rmp', professorId: p.id })}>Check on RMP ↗</button></div>
          {p.issue && <p className="notice" role="status">{p.issue}</p>}
          {p.state === 'loading' || p.state === 'pending' ? <div className="placeholder" role="status">Retrieving verified ratings and reviews…</div> : null}
          {(p.state === 'choose' || p.state === 'unavailable') && <div className="actions"><button className="primary" onClick={() => void command({ kind: p.state === 'choose' ? 'discover' : 'retry', professorId: p.id })}>{p.state === 'choose' ? 'Choose profile' : 'Try again'}</button></div>}
          {p.profile && <>
            <div className="stats"><div><b>{score(p.profile.rating)}<small>/ 5</small></b><span>Overall rating</span></div><div><b>{score(p.profile.difficulty)}<small>/ 5</small></b><span>Difficulty</span></div><div><b>{p.profile.wouldTakeAgain === undefined ? '—' : `${Math.round(p.profile.wouldTakeAgain)}%`}</b><span>Would take again</span></div></div>
            <div className="source-line"><span>{p.profile.ratingCount ?? 'Unknown'} source ratings · Scores are professor-wide</span><button className="text-button" onClick={() => void command({ kind: 'discover', professorId: p.id })}>Change profile</button></div>
            <section className="summary card"><div className="section-heading"><h3>Student feedback</h3><span className="tag">Local AI</span></div>
            {p.summary ? <><p className="overview">{p.summary.overview}</p>{p.summary.positives.map(point => <p className="theme" key={'p' + point.text}><span className="theme-label">Positive</span>{point.text}<small>Supported by {point.reviewIDs.join(', ')}</small></p>)}{p.summary.concerns.map(point => <p className="theme" key={'c' + point.text}><span className="theme-label">Concern</span>{point.text}<small>Supported by {point.reviewIDs.join(', ')}</small></p>)}<p className="muted small">Analyzed {p.summary.analyzedCount} complete reviews of {p.profile.reviews.length} downloaded · {p.summary.exactCourseCount} for {c?.display}. {p.summary.exactCourseCount < p.summary.analyzedCount && 'Includes feedback from other courses.'} Reported experiences may differ from the current class.</p></> : <p className="muted" role="status">{p.summaryLoading ? 'Preparing a summary on your PC…' : p.detailLoading ? 'Original reviews are available while more feedback loads.' : 'Summary has not been prepared.'}</p>}
            {p.summaryIssue && <p className="notice" role="status">{p.summaryIssue}</p>}<button disabled={p.summaryLoading} onClick={() => void command({ kind: 'summary', professorId: p.id })}>{p.summaryLoading ? 'Preparing…' : p.summaryIssue ? 'Retry summary' : 'Prepare summary'}</button>
            </section>
            <section className="reviews"><div className="section-heading"><h3>Original reviews <span className="muted">({reviews.length})</span></h3><div className="filters"><label>Review course<select value={filter} onChange={e => { setFilter(e.target.value); setVisible(3) }}><option value="this">This course</option><option value="all">All courses</option>{[...counts].map(([label, count]) => <option key={label} value={label}>{label}{count === undefined ? '' : ` (${count})`}</option>)}</select></label><label>Sort<select value={reviewSort} onChange={e => setReviewSort(e.target.value)}><option value="recent">Most recent</option><option value="highest">Highest rating</option><option value="lowest">Lowest rating</option><option value="difficulty">Lowest difficulty</option></select></label></div></div>
            {reviews.slice(0, visible).map(r => <article className="review card" key={r.id}><div className="review-heading"><strong>{r.course || 'Course unspecified'}</strong><span className="muted small">{r.date ? `Posted ${r.date.slice(0, 10)}` : 'Posted date unavailable'}</span></div><div className="muted small">Rating {score(r.rating)} · Difficulty {score(r.difficulty)}{r.online === undefined ? '' : r.online ? ' · Online' : ' · In person'}</div><p>{r.text}</p><small className="muted">Source review ID: {r.id}</small></article>)}
            {!reviews.length && <p className="muted">No downloaded review text matches this filter.</p>}
            {p.reviewIssue && <p className="notice" role="status">{p.reviewIssue}</p>}
            <div className="actions">{visible < reviews.length && <button onClick={() => setVisible(n => n + 5)}>View more reviews</button>}<button disabled={p.detailLoading} onClick={() => void command({ kind: 'details', professorId: p.id, filter: filter === 'all' ? undefined : filter === 'this' ? c?.key : filter })}>{p.detailLoading ? 'Loading reviews…' : filter === 'all' ? 'Find more reviews' : 'Find more for this class'}</button></div>
            <p className="muted small">Filters use downloaded reviews. “Find more” requests source ratings, up to 50 per filter; some ratings have no written comment.</p></section>
          </>}
          <section className="sections"><h3>PCC sections</h3>{p.sections.map(s => <article className="section card" key={s.crn}><div className="section-heading"><strong>CRN {s.crn}</strong><span className="tag">{s.status === 'C' ? 'Closed' : s.status === 'O' ? 'Open' : s.status || 'Status unavailable'}</span></div><p>{s.title}</p><p>{delivery(s)}</p><p className="muted small">{s.start.slice(0, 10) || 'Start unavailable'} – {s.end.slice(0, 10) || 'End unavailable'}</p>{s.meetings.map(m => <p className="small" key={m}>{m}</p>)}</article>)}</section>
          </>}
        </main>
      </div>}
    </> : <div className="welcome"><div className="welcome-glyph" aria-hidden="true">↗</div><h2>A little clarity before you enroll.</h2><p>Search a PCC course and semester to compare the professors teaching it.</p><div className="welcome-features"><span>Published sections</span><span>Original student reviews</span><span>AI that stays on your PC</span></div></div>}
    <footer><span>One simple search.</span><span>PCC + Rate My Professors · AI summaries are experimental</span></footer>
    <dialog ref={dialogRef} className="chooser" onCancel={e => { e.preventDefault(); if (p) void command({ kind: 'dismiss', professorId: p.id }) }} aria-labelledby="chooser-title"><h2 id="chooser-title">Choose the correct profile</h2><p className="muted">Confirm which PCC profile belongs to {p?.name}. Profiles are kept separate.</p>{p?.issue && <p className="notice">{p.issue}</p>}{!p?.candidates.length && <p>No eligible profiles are available yet. Retry discovery or check RMP.</p>}{p?.candidates.map(candidate => <div className="candidate card" key={candidate.id}><div><strong>{candidate.firstName} {candidate.lastName}</strong><p>{candidate.department || 'Department unavailable'}</p><p className="muted small">{candidate.school} · Profile {candidate.id}</p><button className="text-button" onClick={() => void command({ kind: 'source', target: 'rmp', professorId: p.id, candidateId: candidate.id })}>View source profile ↗</button></div><button className="primary" onClick={() => void command({ kind: 'select', professorId: p.id, profileId: candidate.id })}>Use this profile</button></div>)}<div className="actions"><button onClick={() => p && void command({ kind: 'discover', professorId: p.id })}>Retry discovery</button><button onClick={() => p && void command({ kind: 'dismiss', professorId: p.id })}>Cancel</button></div></dialog>
  </div>
  function searchWithSuggestion(text: string) { const term = terms.find(t => t.termCode === termCode); if (term) { setSearching(false); setSuggestions([]); void command({ kind: 'search', query: text, term }) } }
}
createRoot(document.getElementById('root')!).render(<App />)
