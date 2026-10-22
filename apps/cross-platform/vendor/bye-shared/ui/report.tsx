import React, { useEffect, useRef, useState } from 'react'
import type { ByeReviewState, Command, Course, Professor, Section } from '../core/types'
import type { ByeWrittenReview } from '../core/reviews'
import { byeFilter, excerpt, filterReviews, orderReviews, preferredFilter, requestLabel, sameCourse, type ReviewSource } from '../core/domain'
import { ByeReviewCard, ByeScores, SourceTag } from './bye-review-panel'
import { SampleTag, useSurface } from './context'
import { courseLabel, monthYear, plural, score, unnamed } from './format'
import { useFlip } from './motion'
import { Avatar, Bar, Num } from './primitives'
import { Segmented } from './results'
import { SectionCard } from './section-card'

/** What the student chose on one professor's page, so a host can bring that professor back the same way. */
export interface ReportState { filter: string; chosen: boolean; sort: string; limit: number; source?: ReviewSource }

/** The host's BYE student reviews. The host owns requests; `load` asks for a BYE filter ("this", "all" or a BYE course ID). */
export interface ByeReviews {
  state?: ByeReviewState
  load: (filter: string, sort: string, more?: boolean) => void
  write: () => void
  /** The form opens outside the app (Windows), so the button shows ↗ instead of →. */
  external?: boolean
  actions?: (r: ByeWrittenReview) => React.ReactNode
}

// One professor's page: scores, sections and reviews. BYE never picks a professor; this only opens when the student does.
// The page stays mounted while the student switches professors, so it updates in place: nothing flashes, bars glide and the
// scores count up again for the new professor (`restartKey`).
// `matches` applies the class-days rule. `bye` adds BYE student reviews (not in the demo): its score row sits above RMP's,
// and one "Reviews" list shows BYE reviews first, then RMP, each tagged, with a Both · BYE · RMP toggle.
// The other optional props are the Mac app's extras (the Windows app uses them all):
// - `back`: the phone header with "← Professors" (web). Without it the page has no header bar.
// - `reviewFilter`: "chips" (web) or a "Review course" select with RMP counts for every course label (Mac, Windows).
// - `preloaded`: the host loads RMP reviews when the page opens, so changing the filter uses saved reviews. Without it,
//   choosing a filter requests its reviews (web live).
// - `checking`: ratings are still being checked, so review retries wait.
// - `writeReview`: "Write a review ↗" among the source links, for hosts without `bye`.
// - `summary`: the AI summary block or its policy note, shown above the reviews.
// - `reviewPage`: reviews shown first and added per "View more reviews" (the Mac uses 3 and 5).
// - `initial`, `onChange`: restore and save the student's filter, sort, page and source for each professor.
export function Report({ p, course, matches, command, back, bye, reviewFilter = 'chips', preloaded = false, checking = false, writeReview = false, summary, reviewPage = [4, 6], initial, onChange }: {
  p: Professor; course: Course; matches: (s: Section) => boolean; command: (c: Command) => void; back?: () => void; bye?: ByeReviews
  reviewFilter?: 'chips' | 'select'; preloaded?: boolean; checking?: boolean; writeReview?: boolean; summary?: React.ReactNode
  reviewPage?: readonly [number, number]; initial?: ReportState; onChange?: (value: ReportState) => void
}) {
  const { demo } = useSurface()
  const profile = p.profile, [first, more] = reviewPage
  const [filter, setFilter] = useState(() => initial?.filter ?? preferredFilter(profile, course)), [chosen, setChosen] = useState(initial?.chosen ?? false)
  const [sort, setSort] = useState(initial?.sort ?? 'recent'), [visible, setVisible] = useState(initial?.limit ?? first)
  const [source, setSource] = useState<ReviewSource>(initial?.source ?? 'both')
  const root = useRef<HTMLElement>(null), mounted = useRef(false)
  useEffect(() => {
    if (!mounted.current) { mounted.current = true; return }
    setFilter(initial?.filter ?? preferredFilter(profile, course)); setChosen(initial?.chosen ?? false); setSort(initial?.sort ?? 'recent'); setVisible(initial?.limit ?? first); setSource(initial?.source ?? 'both')
    root.current?.parentElement?.scrollTo?.(0, 0)
  }, [p.id, profile?.id, course.key])
  useEffect(() => { onChange?.({ filter, chosen, sort, limit: visible, source }) }, [filter, chosen, sort, visible, source])
  // Until the student picks a filter, the page follows the reviews as they arrive: this class when any mention it, else all.
  useEffect(() => { if (!chosen) setFilter(preferredFilter(profile, course)) }, [profile?.reviews.length])

  // BYE: shown outside the demo for a named instructor. Its filter follows the page's one course filter.
  const byeOn = !!bye && !demo && !unnamed(p), b = byeOn ? bye!.state : undefined
  const byeCourses = b?.profile?.courses ?? []
  const byeWant = byeFilter(filter, byeCourses), byeMatched = !!b?.resolution?.professor
  const byeNoClass = byeWant === 'this' && byeMatched && !b?.resolution?.course
  useEffect(() => {
    // Ask the host for this filter and sort once the professor is matched and nothing is loading.
    if (!byeOn || !b?.resolution?.professor || b.loading || byeWant === null || byeNoClass) return
    if (b.filter !== byeWant || b.sort !== sort) bye!.load(byeWant, sort)
  }, [byeOn, b?.resolution?.professor?.id, b?.loading, b?.filter, b?.sort, byeWant, byeNoClass, sort])

  const rmpLabels = new Set(profile?.courseCounts.map(x => x.label) ?? [])
  const choose = (value: string) => {
    setFilter(value); setChosen(true); setVisible(first)
    if (!demo && !preloaded && profile && (value === 'this' || value === 'all' || rmpLabels.has(value))) command({ kind: 'details', professorId: p.id, filter: value })
  }
  const reviews = profile ? orderReviews(filterReviews(profile, course, filter), sort) : []
  const showBye = byeOn && source !== 'rmp', showRmp = !!profile && (!byeOn || source !== 'bye')
  const byeReady = !!b && byeMatched && byeWant !== null && b.filter === byeWant && b.sort === sort
  const byeList = showBye && byeReady ? b!.reviews : []
  const byeBusy = showBye && !!b && (b.loading || (byeMatched && byeWant !== null && !byeNoClass && !byeReady))
  const byeMore = showBye && byeReady && b!.nextOffset !== null
  // In Both, RMP reviews wait until every BYE review is in, so RMP cards never appear and then get pushed down.
  const rmpList = showRmp && !(showBye && (byeBusy || byeMore)) ? reviews : []
  // BYE reviews come first, then RMP's, each in the chosen sort.
  const items: { key: string; bye?: ByeWrittenReview; rmp?: (typeof reviews)[number] }[] = [...byeList.map(r => ({ key: 'bye-' + r.id, bye: r })), ...rmpList.map(r => ({ key: 'rmp-' + r.id, rmp: r }))]
  const shown = items.slice(0, visible)
  const viewMore = () => { setVisible(n => n + more); if (byeMore && byeList.length < visible + more) bye!.load(byeWant!, sort, true) }
  // Changing the sort glides each review to its new place.
  const reviewBox = useRef<HTMLDivElement>(null)
  useFlip(reviewBox, shown.map(x => x.key).join('|'))

  // The course filter lists RMP's labels plus any course only BYE has, with the counts for the sources shown.
  const byeCount = (value: string) => {
    if (!showBye || !b?.profile) return 0
    const id = value === 'all' ? undefined : value === 'this' ? b.resolution?.course?.id : byeFilter(value, byeCourses)
    return value === 'all' ? b.profile.count : byeCourses.find(c => c.id === id)?.count ?? 0
  }
  const counts = profile?.courseCounts.filter(x => x.label) ?? []
  const rmpCount = (label: string) => showRmp ? counts.find(x => x.label === label)?.count : 0
  const total = (rmp: number | undefined, value: string) => rmp === undefined && !(showBye && b?.profile) ? undefined : (rmp ?? 0) + byeCount(value)
  const thisCount = total(showRmp ? counts.find(x => sameCourse(course, x.label))?.count : 0, 'this')
  const byeOnly = byeCourses.filter(c => !sameCourse(course, c.code) && ![...rmpLabels].some(l => byeFilter(l, [c]) !== null)).map(c => ({ label: c.code, count: undefined as number | undefined }))
  const others = [...counts.filter(x => !sameCourse(course, x.label)), ...(showBye ? byeOnly : [])]
  const chips = [{ value: 'this', label: `This class${thisCount === undefined ? '' : ` · ${thisCount}`}` }, { value: 'all', label: 'All' },
    ...others.map(x => { const n = total(rmpCount(x.label), x.label); return { value: x.label, label: `${courseLabel(x.label)}${n === undefined ? '' : ` · ${n}`}` } })]
  // The select lists every RMP course label with its source count, plus labels seen only on downloaded reviews or only on BYE.
  const options = new Map<string, number | undefined>(counts.map(x => [x.label, x.count]))
  for (const r of profile?.reviews ?? []) if (r.course && !options.has(r.course)) options.set(r.course, undefined)
  const labels = [...options].sort((a, b) => a[0].localeCompare(b[0], 'en', { numeric: true }))
  const byeLabels = showBye ? byeOnly.map(x => x.label) : []
  // Review cards name courses the way the filter control does: spaced on chips, RMP's own label in the select.
  const label = (value: string) => reviewFilter === 'select' ? value : courseLabel(value)
  const exact = profile?.reviews.filter(r => sameCourse(course, r.course)).length ?? 0
  // Web hosts request a filter by name ("this", "all", a label); preloaded hosts request RMP's course label.
  const retry = preloaded ? requestLabel(course, filter) : filter, busy = checking || !!p.detailLoading
  const name = (profile && `${profile.firstName} ${profile.lastName}`.trim()) || p.name
  const rmpTag = byeOn && <SourceTag source="rmp" />
  return <article ref={root} className="report report-in" aria-label={`Report for ${name}`}>
    {back && <header className="report-bar">
      <button className="back" onClick={back}><span aria-hidden="true">←</span> Professors</button>
      <span className="row"><SampleTag>Sample data</SampleTag><span className="chip">{course.display}</span></span>
    </header>}
    <div className="report-body">
      <div className="report-head">
        <Avatar name={name} accent size="lg" />
        <h2 className="report-name">{name}</h2>
        <SampleTag>Sample professor · not a real PCC instructor</SampleTag>
        <p className="meta">{profile?.department ? `${profile.department} · ` : ''}Pasadena City College
          {profile && (!demo || p.candidates.length > 1) && <button className="text-link" disabled={p.state === 'loading'} onClick={() => command({ kind: 'discover', professorId: p.id })}>Change profile</button>}</p>
        {name !== p.name && <p className="muted small">Listed at PCC as {p.name}</p>}
        {profile && p.issue && <p className="muted small" role="status">{p.issue}</p>}
      </div>

      {byeOn && <ByeScores state={b} />}
      {(p.state === 'loading' || p.state === 'pending') && <p className="placeholder" role="status">Checking RMP for {p.name}…</p>}
      {p.state === 'choose' && <div className="callout"><p><b>{p.candidates.length > 1 ? `${p.candidates.length} RMP profiles match ${p.name}.` : `Confirm the RMP profile for ${p.name}.`}</b> Pick the one that teaches {course.display}. BYE keeps them separate and never guesses.</p>
        <button className="button primary wide" onClick={() => command({ kind: 'discover', professorId: p.id })}>Choose profile <span aria-hidden="true">→</span></button></div>}
      {p.state === 'unavailable' && (unnamed(p)
        ? <div className="callout"><p><b>No instructor named yet.</b> PCC hasn't announced who teaches this section. Check back closer to the start of the semester.</p></div>
        : <div className="callout card" role="status"><p><b className="signal">{p.issue?.includes('access is pending') ? 'RMP access pending.' : 'Cannot retrieve RMP info.'}</b> {p.issue?.includes('access is pending') ? 'PCC sections and BYE reviews are available in this preview.' : <>{p.issue} The PCC sections below remain available; check their retrieval times.</>}</p>
          {!p.issue?.includes('access is pending') && <button className="button secondary wide" onClick={() => command({ kind: 'retry', professorId: p.id })}>Try again</button>}</div>)}

      {profile && <section aria-label="Rate My Professors scores" className="block">
        {byeOn && <p className="score-source">{rmpTag} Rate My Professors</p>}
        <div className="stats">
          <div className="stat"><b><Num value={profile.rating} restartKey={p.id} /><small>/5</small></b><span>{demo ? 'Rating · sample' : 'RMP rating'}</span><Bar value={profile.rating} label="Rating" /></div>
          <div className="stat"><b><Num value={profile.difficulty} restartKey={p.id} /><small>/5</small></b><span>Difficulty</span><Bar value={profile.difficulty} label="Difficulty" /></div>
          <div className="stat"><b><Num value={profile.wouldTakeAgain === undefined ? undefined : Math.round(profile.wouldTakeAgain)} digits={0} suffix="%" restartKey={p.id} /></b><span>Would take again</span></div>
        </div>
        <p className="muted small">{profile.ratingCount === undefined ? 'Rating count unavailable' : plural(profile.ratingCount, 'rating')} across all courses · lower difficulty means easier {demo ? ' · sample data' : ''}</p>
      </section>}

      <section className="block">
        <h3>Sections <span className="muted">· {p.sections.length}</span></h3>
        <div className="section-list">{p.sections.map(s => <SectionCard key={s.crn} s={s} matches={matches(s)} />)}</div>
      </section>

      {profile && summary}
      {(profile || byeOn) && <section className="block" aria-label={byeOn ? 'Reviews' : 'Student reviews'}>
        <div className="row"><h3>{demo ? 'Sample reviews' : byeOn ? 'Reviews' : 'Rate My Professors reviews'}</h3>
          {byeOn && <button className="pill" onClick={bye!.write}>Write a review <span aria-hidden="true">{bye!.external ? '↗' : '→'}</span></button>}</div>
        {byeOn && <Segmented label="Review source" value={source} onChange={value => { setSource(value); setVisible(first) }}
          options={[['both', 'Both'], ['bye', 'BYE'], ['rmp', 'RMP']] as const} />}
        <div className="row review-controls">
          {reviewFilter === 'select'
            ? <select className="review-filter" aria-label="Review course" value={filter} onChange={e => choose(e.target.value)}>
              <option value="this">This course · {course.display}</option>
              <option value="all">All courses</option>
              {labels.map(([value, count]) => <option key={value} value={value}>{count === undefined ? `${value} (source count unavailable)` : `${value} (${count} on RMP)`}</option>)}
              {byeLabels.map(value => <option key={'bye-' + value} value={value}>{value} (BYE only)</option>)}
            </select>
            : <div className="chip-row" role="group" aria-label="Review course">{chips.map(c =>
              <button key={c.value} type="button" className="pill" aria-pressed={filter === c.value} onClick={() => choose(c.value)}>{c.label}</button>)}</div>}
          <select className="bare-select" aria-label="Sort reviews" value={sort} onChange={e => { setSort(e.target.value); setVisible(first) }}>
            <option value="recent">Newest</option><option value="oldest">Oldest</option><option value="highest">Highest rating</option><option value="lowest">Lowest rating</option><option value="difficulty">Lowest difficulty</option><option value="highestDifficulty">Highest difficulty</option>
          </select>
        </div>
        {showRmp && p.detailLoading && <p className="muted small" role="status">Loading more RMP reviews…</p>}
        {showBye && byeBusy && <p className="muted small" role="status">Loading BYE reviews…</p>}
        {showRmp && filter === 'all' && !chosen && exact === 0 && profile!.reviews.length > 0 && <p className="muted small">No reviews mention {course.display} yet, so all courses are shown.</p>}
        {showBye && byeNoClass && <p className="notice">This class could not be matched to BYE’s course list. Choose All to read this professor’s BYE reviews.</p>}
        {showBye && byeMatched && !byeBusy && !byeNoClass && !b?.issue && !byeList.length && <p className="muted">No BYE reviews for {filter === 'all' ? 'this professor' : filter === 'this' ? course.display : label(filter)} yet.</p>}
        {showBye && b?.issue && <div className="notice" role="alert"><p>{b.issue}</p><button className="text-link" disabled={b.loading} onClick={() => bye!.load(byeWant ?? 'all', sort)}>Try BYE reviews again</button></div>}
        <div ref={reviewBox} className="review-list">{shown.map(x => x.bye
          ? <ByeReviewCard key={x.key} r={x.bye} actions={bye!.actions?.(x.bye)} />
          : <article className="review-card review" key={x.key} data-flip={x.key}>
            <div className="row review-heading"><strong className="chip">{x.rmp!.course ? label(x.rmp!.course) : 'Course unspecified'}</strong><span className="muted small">Posted {monthYear(x.rmp!.date)}</span></div>
            <p>{excerpt(x.rmp!)}</p>
            <div className="row review-foot"><span className="muted small">Rating {score(x.rmp!.rating)}/5 · Difficulty {score(x.rmp!.difficulty)}/5</span>
              <span className="review-foot-end">{!demo && <button className="text-link plain" onClick={() => command({ kind: 'source', target: 'rmp', professorId: p.id })}>Original on RMP ↗</button>}{rmpTag}</span></div>
          </article>)}</div>
        {showRmp && p.reviewIssue && <div className="notice" role="status"><p>{p.reviewIssue}</p><button className="text-link" disabled={busy} onClick={() => command({ kind: 'details', professorId: p.id, filter: retry })}>Try reviews again</button></div>}
        {showRmp && !reviews.length && !p.detailLoading && <p className="muted">{byeOn ? 'No RMP reviews match this filter.' : 'No reviews match this filter. Try All.'}</p>}
        {(visible < items.length || byeMore) && <button className="button secondary wide" disabled={byeBusy && visible >= items.length} onClick={viewMore}>View more reviews</button>}
        {showRmp && !demo && !p.detailLoading && <p className="muted small">Showing {reviews.length} retrieved RMP reviews, up to 50 per filter.{preloaded ? ' Changing the filter uses saved reviews.' : ''} {profile!.source && `RMP checked ${new Date(profile!.source.retrievedAt).toLocaleString()}.`}</p>}
        {showRmp && !demo && <p className="muted small">RMP reviews are excerpts from accessible reviews, not the complete RMP review history.</p>}
        <p className="muted small center">{demo ? 'These reviews are made up for the demo. ' : ''}Ratings reflect student feedback. They don't guarantee a grade.</p>
      </section>}
      {!demo && <div className="source-links"><button className="text-link" onClick={() => command({ kind: 'source', target: 'pcc' })}>PCC schedule ↗</button>
        {profile && <button className="text-link" onClick={() => command({ kind: 'source', target: 'rmp', professorId: p.id })}>Rate My Professors ↗</button>}
        {writeReview && !byeOn && !unnamed(p) && <button className="text-link" onClick={() => command({ kind: 'source', target: 'review', professorId: p.id })}>Write a review ↗</button>}</div>}
    </div>
  </article>
}
