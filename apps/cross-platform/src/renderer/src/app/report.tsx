import { useEffect, useRef, useState } from 'react'
import type { Course, Professor, Section, Snapshot } from '../../../shared/types'
import { REVIEW_SORTS, dateLabel, excerpt, filterFinished, filterReviews, formatLabel, fullyOnline, orderReviews, preferredFilter, requestLabel, sameCourse, scheduleNotAnnounced } from '../../../../vendor/bye-shared/core/domain'
import { Avatar, Bar, Num, useFlip } from '../../../../vendor/bye-shared/ui'
import { AI_SUMMARIES_ENABLED, AI_SUMMARIES_UNAVAILABLE_NOTE } from '../../../shared/features'
import type { Run } from './types'

// Windows professor row, page and chooser. They follow the Mac app (Sources/Classwise/Views): row actions, review filters,
// "Find more" and the AI policy note. The look is the shared v3 design (vendor/bye-shared/ui/styles.css + app.css).
export const score = (n?: number) => n === undefined ? '—' : n.toFixed(1)
export const plural = (n: number, word: string) => `${n} ${n === 1 ? word : word + 's'}`
export const DISCLAIMER = 'Ratings reflect student feedback across reviewed courses. They don’t guarantee a grade.'

/** One professor in the list: the shared row look, plus Mac-style actions under it. */
export function ProfessorRow({ p, selected, open, run }: { p: Professor; selected: boolean; open: () => void; run: Run }) {
  const sections = plural(p.sections.length, 'section'), profile = p.profile
  return <div className={`professor-card${selected ? ' selected' : ''}`}>
    <button className={`prof-card${selected ? ' selected' : ''}`} aria-pressed={selected} onClick={open}>
      <Avatar name={p.name} />
      <span className="prof-main">
        <b className="name">{p.name}</b>
        {profile ? <>
          <small>Difficulty {score(profile.difficulty)} · {profile.wouldTakeAgain === undefined ? 'take-again rate unavailable' : `${Math.round(profile.wouldTakeAgain)}% would take again`}</small>
          <small>{profile.ratingCount === undefined ? 'Rating count unavailable' : `${profile.ratingCount} ratings`} · {sections}</small>
          <Bar value={profile.rating} label="Rating" />
        </> : <>
          <small>{p.state === 'choose' ? (p.candidates.length > 1 ? 'Two or more RMP profiles · Choose profile' : 'Profile needs confirmation · Choose profile') : p.state === 'unavailable' ? 'Cannot retrieve RMP info' : p.state === 'loading' ? 'Checking RMP…' : 'Not checked yet'}</small>
          <small>{sections}</small>
        </>}
      </span>
      <span className={`big${profile ? '' : ' muted'}`}>{profile ? <Num value={profile.rating} /> : '—'}</span>
    </button>
    {(p.state === 'choose' || p.state === 'unavailable' || p.state === 'pending') && <div className="row-actions">
      {p.state === 'choose' && <button className="text-link" onClick={() => run({ kind: 'discover', professorId: p.id })}>Choose profile</button>}
      {(p.state === 'unavailable' || p.state === 'pending') && <button className="text-link" onClick={() => run({ kind: 'retry', professorId: p.id })}>Try again</button>}
      {p.state === 'unavailable' && <button className="text-link muted" onClick={() => run({ kind: 'source', target: 'rmp', professorId: p.id })}>Check on RMP ↗</button>}
    </div>}
  </div>
}

/** Before a professor is opened: neutral facts about the class. It never names, ranks or recommends anyone. */
export function CourseOverview({ course, title, summary, professors }: { course?: Course; title: string; summary: string; professors: Professor[] }) {
  const seen = new Set<string>(), sections = professors.flatMap(p => p.sections).filter(s => !seen.has(s.crn) && !!seen.add(s.crn))
  const known = sections.map(s => s.details?.seatsOpen).filter((n): n is number => n !== undefined)
  const breakdown = (labels: string[]) => [...labels.reduce((m, l) => m.set(l, (m.get(l) ?? 0) + 1), new Map<string, number>())].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).map(([l, n]) => `${l} ${n}`).join(' · ')
  const formats = breakdown(sections.map(formatLabel)), terms = breakdown(sections.map(s => s.details?.termPart ?? '').filter(Boolean))
  return <div className="empty-detail overview" aria-label="Course overview">
    <svg className="drawn-arrow" viewBox="0 0 78 44" aria-hidden="true"><path d="M74 10 C 52 2, 24 6, 9 30" /><path d="M5 17 L9 31 L22 27" /></svg>
    <h2>Pick a professor.</h2>
    <p className="muted">We line them up, you decide. BYE won't choose for you.</p>
    <p className="muted small">{course?.display}{title ? ` · ${title}` : ''}{summary ? ` · ${summary}` : ''}</p>
    <div className="empty-stats">
      <div className="stat"><b>{sections.length}</b><span>{sections.length === 1 ? 'section' : 'sections'}</span></div>
      <div className="stat"><b>{professors.length}</b><span>{professors.length === 1 ? 'professor' : 'professors'}</span></div>
      <div className="stat"><b>{known.length ? known.reduce((a, b) => a + b, 0) : '—'}</b><span>seats open</span></div>
    </div>
    {(formats || terms) && <dl className="facts">{formats && <><dt>Format</dt><dd className="muted">{formats}</dd></>}{terms && <><dt>Term</dt><dd className="muted">{terms}</dd></>}</dl>}
    <p className="muted small">Choose a professor on the left to see their sections, ratings and student reviews.</p>
    <p className="muted small">{DISCLAIMER}</p>
  </div>
}

/** Open seats with a capacity bar and the waitlist, from PCC's schedule. */
function SeatMeter({ s }: { s: Section }) {
  const d = s.details, open = d?.seatsOpen
  if (open === undefined) return <div className="seat-meter"><span className="muted small">Seats unavailable</span></div>
  const full = open === 0, count = d?.waitlistCount, capacity = d?.waitlistCapacity
  const wait = count === undefined ? '' : capacity === undefined ? `Waitlist ${count}` : `Waitlist ${count} of ${capacity}`
  const waitlist = full ? (wait ? 'Full · ' + wait.toLowerCase() : 'Full') : wait
  // The bar fills as seats are taken: ink while plentiful, yellow at 10 or fewer, red at 5 or fewer (same thresholds as the Mac).
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
      <div className="tags"><span className="chip">CRN {s.crn}</span><span className="tag">{formatLabel(s)}</span>{d?.termPart && <span className="tag term">{d.termPart}</span>}</div>
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
  return <div className="stat score-card" role="group" aria-label={`${title}: ${value === undefined ? 'not available' : `${value.toFixed(1)} out of 5`}. ${helper}`}>
    <b>{value === undefined ? '—' : <Num value={value} />}{value !== undefined && <small>/5</small>}</b>
    <strong>{title}</strong>
    <span>{value === undefined ? 'Not available' : helper}</span>
    {value !== undefined && <Bar value={value} label={title} />}
  </div>
}

export function Report({ p, course, state, run }: { p: Professor; course: Course; state: Snapshot; run: Run }) {
  const profile = p.profile
  const [filter, setFilterValue] = useState(() => preferredFilter(profile, course)), [chosen, setChosen] = useState(false)
  const [sort, setSort] = useState('recent'), [limit, setLimit] = useState(3)
  const root = useRef<HTMLElement>(null), list = useRef<HTMLDivElement>(null)
  useEffect(() => { setFilterValue(preferredFilter(profile, course)); setChosen(false); setSort('recent'); setLimit(3); root.current?.scrollTo(0, 0) }, [p.id, profile?.id, course.key])
  useEffect(() => { if (!chosen) setFilterValue(preferredFilter(profile, course)) }, [profile?.reviews.length])
  const setFilter = (value: string) => { setFilterValue(value); setChosen(true); setLimit(3) }
  const reviews = profile ? orderReviews(filterReviews(profile, course, filter), sort) : []
  useFlip(list, reviews.slice(0, limit).map(r => r.id).join('|'))
  const exact = profile?.reviews.filter(r => sameCourse(course, r.course)).length ?? 0
  const counts = new Map((profile?.courseCounts ?? []).filter(x => x.label).map(x => [x.label, x.count]))
  for (const review of profile?.reviews ?? []) if (review.course && !counts.has(review.course)) counts.set(review.course, undefined)
  const choices = [...counts].sort((a, b) => a[0].localeCompare(b[0], 'en', { numeric: true }))
  const all = profile?.coverage.all, complete = !!all && (!all.hasNextPage || all.reviewIDs.length >= 50)
  const checking = state.loading || state.previewPending > 0, label = requestLabel(course, filter)
  const name = profile ? `${profile.firstName} ${profile.lastName}` : p.name
  return <main className="report report-in" ref={root} aria-label="Professor report">
    <header className="report-head">
      <Avatar name={name} accent size="lg" />
      <h2 className="report-name">{name}</h2>
      {profile ? <div className="meta">
        <span className="muted">{[profile.department, profile.school].filter(Boolean).join(' · ')}</span>
        <button className="text-link" disabled={p.state === 'loading'} onClick={() => run({ kind: 'discover', professorId: p.id })}>Change profile</button>
        {p.issue && <span className="muted small">{p.issue}</span>}
        {name !== p.name && <span className="muted small">Listed at PCC as {p.name}</span>}
      </div> : <span className="muted">Teaching {course.display} at Pasadena City College</span>}
    </header>
    {profile && <>
      <div className="score-row">
        <ScoreCard value={profile.rating} title="Student rating" helper="Higher means better rated" />
        <ScoreCard value={profile.difficulty} title="Difficulty" helper="Lower means easier" />
        <div className="stat"><b>{profile.wouldTakeAgain === undefined ? '—' : <Num value={Math.round(profile.wouldTakeAgain)} digits={0} suffix="%" />}</b><strong>Would take again</strong><span>{profile.ratingCount === undefined ? 'Rating count unavailable' : `${profile.ratingCount} RMP ratings`}</span></div>
      </div>
      <p className="muted small">{profile.ratingCount === undefined ? 'Overall rating count unavailable' : `Based on ${profile.ratingCount} RMP ratings across courses`}</p>
    </>}
    <section className="stack" aria-label="PCC class sections">
      <h3>Class sections <span className="muted">· {p.sections.length}</span></h3>
      {p.sections.map(s => <ClassCard key={s.crn} s={s} />)}
      <div><button className="pill" onClick={() => run({ kind: 'source', target: 'pcc' })}>PCC schedule ↗</button></div>
    </section>
    {profile ? <>
      {AI_SUMMARIES_ENABLED ? <Summary p={p} course={course} run={run} /> : <p className="panel small muted" role="status">{AI_SUMMARIES_UNAVAILABLE_NOTE}</p>}
      <section className="stack" aria-label="Student reviews">
        <h3>What students say</h3>
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
        <div className="review-list" ref={list}>{reviews.slice(0, limit).map(r => <article className="review" key={r.id} data-flip={r.id}>
          <div className="review-heading">{r.course ? <strong className="chip">{r.course}</strong> : <strong>Course not specified</strong>}<span className="muted small">Rating {score(r.rating)}/5 · Difficulty {score(r.difficulty)}/5</span></div>
          <p className="review-text">{excerpt(r)}</p>
          <div className="row small"><span className="muted">{r.date ? `Posted ${r.date.slice(0, 10)}` : 'Posted date unavailable'}</span><button className="text-link plain" onClick={() => run({ kind: 'source', target: 'rmp', professorId: p.id })}>Original on RMP ↗</button></div>
        </article>)}</div>
        {reviews.length > limit && <button className="pill wide" onClick={() => setLimit(n => n + 5)}>View more reviews</button>}
        <p className="muted small">Excerpts from accessible reviews, not the complete RMP review history. Dates indicate when reviews were posted.</p>
      </section>
    </> : <div className="panel stack">
      <h3>{p.state === 'choose' ? 'Choose profile' : p.state === 'unavailable' ? 'Cannot retrieve RMP info' : p.state === 'loading' ? 'Finding student feedback…' : 'Student feedback hasn’t been checked yet.'}</h3>
      <p className="muted">{p.issue ?? 'PCC sections are available above. Ratings and reviews will appear here when retrieved.'}</p>
      {p.state === 'unavailable' && <div><span className="tag signal">Unavailable</span></div>}
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
    <div className="row"><h3>AI review summary</h3><span className="tag signal">Experimental</span></div>
    {summary ? <>
      <p className="summary-text">{summary.overview}</p>
      <p className="muted small">Local AI · on your PC · Analyzed {summary.analyzedCount} complete reviews of {p.profile?.reviews.length ?? 0} downloaded · {summary.exactCourseCount} for {course.display}</p>
      {([['Common positives', summary.positives], ['Common concerns', summary.concerns]] as const).map(([title, points]) => <div key={title}><strong className="small">{title}</strong>
        {points.length ? points.map(point => <p className="small" key={point.text}>• {point.text}</p>) : <p className="muted small">No verified recurring theme in this sample.</p>}</div>)}
    </> : <p className="muted" role="status">{p.summaryIssue ?? (p.summaryLoading ? 'Preparing a summary on your PC…' : 'A summary will be prepared when this report opens. Ratings and original reviews are already available below.')}</p>}
    {p.summaryIssue && <div><button className="pill" disabled={p.summaryLoading} onClick={() => run({ kind: 'summary', professorId: p.id })}>Retry summary</button></div>}
  </section>
}

/** Explicit RMP profile choice. Profiles stay separate; closing leaves the professor unresolved. */
export function Chooser({ p, run }: { p?: Professor; run: Run }) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => {
    const dialog = ref.current
    if (p?.choosing && dialog && !dialog.open) dialog.showModal()
    if (!p?.choosing && dialog?.open) dialog.close()
  }, [p?.choosing, p?.id])
  const close = () => { if (p) run({ kind: 'dismiss', professorId: p.id }) }
  return <dialog ref={ref} className="sheet chooser" aria-labelledby="chooser-title" onCancel={e => { e.preventDefault(); close() }}>
    <h2 id="chooser-title">Choose RMP profile</h2>
    {p && <>
      <strong>{p.name}</strong>
      <span className="muted">{[p.subject, p.subjectDescription].filter(Boolean).join(' · ')}</span>
      <p className="muted">Profiles stay separate. Choose the profile you want to use for this PCC instructor and subject.</p>
      {p.issue && <div className="stack tight"><p className="muted">{p.issue}</p><div><button className="pill" onClick={() => run({ kind: 'discover', professorId: p.id })}>Try again</button></div></div>}
      {p.discoveryLoading && <p className="muted" role="status">Finding matching profiles…</p>}
      <div className="candidates">{p.candidates.map(c => <div className="panel candidate" key={c.id}>
        <strong>{c.firstName} {c.lastName}</strong>
        <span>Department: {c.department || 'Unavailable'}</span>
        <span className="muted">{c.school}</span>
        <div className="row">
          <button className="text-link plain" onClick={() => run({ kind: 'source', target: 'rmp', professorId: p.id, candidateId: c.id })}>View on RMP ↗</button>
          <button className="pill primary" disabled={p.discoveryLoading} aria-label="Use this profile" aria-description={`${c.firstName} ${c.lastName}, ${c.department || 'department unavailable'}, profile ${c.id}`} onClick={() => run({ kind: 'select', professorId: p.id, profileId: c.id })}>Use this profile</button>
        </div>
      </div>)}</div>
      {!p.discoveryLoading && !p.candidates.length && !p.issue && <div className="stack tight"><p className="muted">No eligible profile is available. Retry this professor or check the source.</p><div className="row"><button className="pill" onClick={() => run({ kind: 'discover', professorId: p.id })}>Try again</button><button className="text-link" onClick={() => run({ kind: 'source', target: 'rmp', professorId: p.id })}>Check on RMP ↗</button></div></div>}
    </>}
    <div className="row end"><button className="pill" onClick={close}>Close</button></div>
  </dialog>
}
