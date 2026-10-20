import React, { useEffect, useRef, useState } from 'react'
import type { Command, Course, Professor, Section } from '../core/types'
import { excerpt, filterFinished, filterReviews, orderReviews, preferredFilter, requestLabel, sameCourse } from '../core/domain'
import { SampleTag, useSurface } from './context'
import { courseLabel, monthYear, plural, score, unnamed } from './format'
import { useFlip } from './motion'
import { Avatar, Bar, Num } from './primitives'
import { SectionCard } from './section-card'

/** What the student chose on one professor's page, so a host can bring that professor back the same way. */
export interface ReportState { filter: string; chosen: boolean; sort: string; limit: number }

// One professor's page: scores, sections and reviews. BYE never picks a professor; this only opens when the student does.
// The page stays mounted while the student switches professors, so it updates in place: nothing flashes, bars glide and the
// scores count up again for the new professor (`restartKey`).
// `matches` applies the class-days rule; `byeReviews` is the host's BYE student-reviews block (live web app only for now).
// The other optional props are the Mac app's extras (the Windows app uses them all):
// - `back`: the phone header with "← Professors" (web). Without it the page has no header bar.
// - `reviewFilter`: "chips" (web) or a "Review course" select with RMP counts for every course label (Mac, Windows).
// - `findMore`: an explicit "Find more for this class" button. Without it, choosing a filter requests its reviews (web live).
// - `checking`: ratings are still being checked, so on-demand review requests wait.
// - `writeReview`: "Write a review ↗", which opens the BYE review form through `command`.
// - `summary`: the AI summary block or its policy note, shown above the reviews.
// - `reviewPage`: reviews shown first and added per "View more reviews" (the Mac uses 3 and 5).
// - `initial`, `onChange`: restore and save the student's filter, sort and page for each professor.
export function Report({ p, course, matches, command, back, byeReviews, reviewFilter = 'chips', findMore = false, checking = false, writeReview = false, summary, reviewPage = [4, 6], initial, onChange }: {
  p: Professor; course: Course; matches: (s: Section) => boolean; command: (c: Command) => void; back?: () => void; byeReviews?: React.ReactNode
  reviewFilter?: 'chips' | 'select'; findMore?: boolean; checking?: boolean; writeReview?: boolean; summary?: React.ReactNode
  reviewPage?: readonly [number, number]; initial?: ReportState; onChange?: (value: ReportState) => void
}) {
  const { demo } = useSurface()
  const profile = p.profile, [first, more] = reviewPage
  const [filter, setFilter] = useState(() => initial?.filter ?? preferredFilter(profile, course)), [chosen, setChosen] = useState(initial?.chosen ?? false)
  const [sort, setSort] = useState(initial?.sort ?? 'recent'), [visible, setVisible] = useState(initial?.limit ?? first)
  const root = useRef<HTMLElement>(null), mounted = useRef(false)
  useEffect(() => {
    if (!mounted.current) { mounted.current = true; return }
    setFilter(initial?.filter ?? preferredFilter(profile, course)); setChosen(initial?.chosen ?? false); setSort(initial?.sort ?? 'recent'); setVisible(initial?.limit ?? first)
    root.current?.parentElement?.scrollTo?.(0, 0)
  }, [p.id, profile?.id, course.key])
  useEffect(() => { onChange?.({ filter, chosen, sort, limit: visible }) }, [filter, chosen, sort, visible])
  // Until the student picks a filter, the page follows the reviews as they arrive: this class when any mention it, else all.
  useEffect(() => { if (!chosen) setFilter(preferredFilter(profile, course)) }, [profile?.reviews.length])
  const choose = (value: string) => { setFilter(value); setChosen(true); setVisible(first); if (!demo && !findMore) command({ kind: 'details', professorId: p.id, filter: value }) }
  const reviews = profile ? orderReviews(filterReviews(profile, course, filter), sort) : []
  // Changing the sort glides each review to its new place.
  const reviewBox = useRef<HTMLDivElement>(null)
  useFlip(reviewBox, reviews.slice(0, visible).map(r => r.id).join('|'))
  const counts = profile?.courseCounts.filter(x => x.label) ?? []
  const thisCount = counts.find(x => sameCourse(course, x.label))?.count
  const chips = [{ value: 'this', label: `This class${thisCount === undefined ? '' : ` · ${thisCount}`}` }, { value: 'all', label: 'All' },
    ...counts.filter(x => !sameCourse(course, x.label)).map(x => ({ value: x.label, label: `${courseLabel(x.label)}${x.count === undefined ? '' : ` · ${x.count}`}` }))]
  // The select lists every RMP course label with its source count, plus labels seen only on downloaded reviews.
  const options = new Map<string, number | undefined>(counts.map(x => [x.label, x.count]))
  for (const r of profile?.reviews ?? []) if (r.course && !options.has(r.course)) options.set(r.course, undefined)
  const labels = [...options].sort((a, b) => a[0].localeCompare(b[0], 'en', { numeric: true }))
  // Review cards name courses the way the filter control does: spaced on chips, RMP's own label in the select.
  const label = (value: string) => reviewFilter === 'select' ? value : courseLabel(value)
  const exact = profile?.reviews.filter(r => sameCourse(course, r.course)).length ?? 0
  const all = profile?.coverage.all, complete = !!all && (!all.hasNextPage || all.reviewIDs.length >= 50)
  // Web hosts request a filter by name ("this", "all", a label); Find more hosts request RMP's course label.
  const asked = requestLabel(course, filter), retry = findMore ? asked : filter, busy = checking || !!p.detailLoading
  const name = (profile && `${profile.firstName} ${profile.lastName}`.trim()) || p.name
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

      {(p.state === 'loading' || p.state === 'pending') && <p className="placeholder" role="status">Checking RMP for {p.name}…</p>}
      {p.state === 'choose' && <div className="callout"><p><b>{p.candidates.length > 1 ? `${p.candidates.length} RMP profiles match ${p.name}.` : `Confirm the RMP profile for ${p.name}.`}</b> Pick the one that teaches {course.display}. BYE keeps them separate and never guesses.</p>
        <button className="button primary wide" onClick={() => command({ kind: 'discover', professorId: p.id })}>Choose profile <span aria-hidden="true">→</span></button></div>}
      {p.state === 'unavailable' && (unnamed(p)
        ? <div className="callout"><p><b>No instructor named yet.</b> PCC hasn't announced who teaches this section. Check back closer to the start of the semester.</p></div>
        : <div className="callout card" role="status"><p><b className="signal">{p.issue?.includes('access is pending') ? 'RMP access pending.' : 'Cannot retrieve RMP info.'}</b> {p.issue?.includes('access is pending') ? 'PCC sections and BYE reviews are available in this preview.' : <>{p.issue} The PCC sections below remain available; check their retrieval times.</>}</p>
          {!p.issue?.includes('access is pending') && <button className="button secondary wide" onClick={() => command({ kind: 'retry', professorId: p.id })}>Try again</button>}</div>)}

      {profile && <section aria-label="Rate My Professors scores" className="block">
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

      {!demo && !unnamed(p) && byeReviews}
      {profile && summary}
      {profile && <section className="block" aria-label="Student reviews">
        <div className="row"><h3>{demo ? 'Sample reviews' : 'Rate My Professors reviews'}</h3>
          <select className="bare-select" aria-label="Sort reviews" value={sort} onChange={e => { setSort(e.target.value); setVisible(first) }}>
            <option value="recent">Newest</option><option value="oldest">Oldest</option><option value="highest">Highest rating</option><option value="lowest">Lowest rating</option><option value="difficulty">Lowest difficulty</option><option value="highestDifficulty">Highest difficulty</option>
          </select></div>
        {reviewFilter === 'select'
          ? <select className="review-filter" aria-label="Review course" value={filter} onChange={e => choose(e.target.value)}>
            <option value="this">This course · {course.display}</option>
            <option value="all">All courses</option>
            {labels.map(([value, count]) => <option key={value} value={value}>{count === undefined ? `${value} (source count unavailable)` : `${value} (${count} on RMP)`}</option>)}
          </select>
          : <div className="chip-row" role="group" aria-label="Review course">{chips.map(c =>
            <button key={c.value} type="button" className="pill" aria-pressed={filter === c.value} onClick={() => choose(c.value)}>{c.label}</button>)}</div>}
        {findMore && !complete && !p.reviewIssue && <p className="muted small" role="status">{checking ? 'Quick preview · Up to three reviews. More feedback loads after everyone’s ratings are checked.' : p.detailLoading ? 'Quick preview · Loading more reviews for this professor…' : 'Quick preview · More feedback loads when you open this report.'}</p>}
        {!findMore && p.detailLoading && <p className="muted small" role="status">Loading more reviews…</p>}
        {filter === 'all' && !chosen && exact === 0 && profile.reviews.length > 0 && <p className="muted small">No reviews mention {course.display} yet, so all courses are shown.
          {findMore && <> <button className="text-link" disabled={busy} onClick={() => { choose('this'); command({ kind: 'details', professorId: p.id, filter: course.key }) }}>Find {course.display} reviews</button></>}</p>}
        {findMore && asked !== undefined && (filterFinished(profile, course, filter)
          ? <p className="muted small">Finished this filter’s retrieval, or reached the 50-rating limit. Source totals may include reviews without text.</p>
          : <div className="find-more">
            <button className="pill" disabled={busy} onClick={() => command({ kind: 'details', professorId: p.id, filter: asked })}>{p.detailLoading ? 'Loading reviews…' : 'Find more for this class'}</button>
            <p className="muted small">{filter === 'this' ? 'Requests this course label from RMP, as listed by PCC.' : 'Requests this class label from RMP. Reviews for other classes and overall scores stay separate.'}</p>
          </div>)}
        <div ref={reviewBox} className="review-list">{reviews.slice(0, visible).map(r => <article className="review-card review" key={r.id} data-flip={r.id}>
          <div className="row review-heading"><strong className="chip">{r.course ? label(r.course) : 'Course unspecified'}</strong><span className="muted small">Posted {monthYear(r.date)}</span></div>
          <p>{excerpt(r)}</p>
          <div className="row"><span className="muted small">Rating {score(r.rating)}/5 · Difficulty {score(r.difficulty)}/5</span>
            {!demo && <button className="text-link plain" onClick={() => command({ kind: 'source', target: 'rmp', professorId: p.id })}>Original on RMP ↗</button>}</div>
        </article>)}</div>
        {p.reviewIssue && <div className="notice" role="status"><p>{p.reviewIssue}</p><button className="text-link" disabled={busy} onClick={() => command({ kind: 'details', professorId: p.id, filter: retry })}>Try reviews again</button></div>}
        {!demo && !p.detailLoading && <p className="muted small">Showing {reviews.length} retrieved reviews, up to 50 per filter.{findMore ? ' Changing the filter uses saved reviews.' : ''} {profile.source && `RMP checked ${new Date(profile.source.retrievedAt).toLocaleString()}.`}</p>}
        {!reviews.length && !p.detailLoading && <p className="muted">{findMore && filter === 'this' ? `No downloaded reviews exactly match ${course.display}. More may be available on RMP under this or another course label.` : 'No reviews match this filter. Try All.'}</p>}
        {visible < reviews.length && <button className="button secondary wide" onClick={() => setVisible(n => n + more)}>View more reviews</button>}
        {!demo && <p className="muted small">Excerpts from accessible reviews, not the complete RMP review history.</p>}
        <p className="muted small center">{demo ? 'These reviews are made up for the demo. ' : ''}Ratings reflect student feedback. They don't guarantee a grade.</p>
      </section>}
      {!demo && <div className="source-links"><button className="text-link" onClick={() => command({ kind: 'source', target: 'pcc' })}>PCC schedule ↗</button>
        {profile && <button className="text-link" onClick={() => command({ kind: 'source', target: 'rmp', professorId: p.id })}>Rate My Professors ↗</button>}
        {writeReview && !unnamed(p) && <button className="text-link" onClick={() => command({ kind: 'source', target: 'review', professorId: p.id })}>Write a review ↗</button>}</div>}
    </div>
  </article>
}
