import React, { useEffect, useRef, useState } from 'react'
import type { Command, Course, Professor, Section } from '../core/types'
import { filterReviews, orderReviews, sameCourse } from '../core/domain'
import { SampleTag, useSurface } from './context'
import { courseLabel, monthYear, plural, unnamed } from './format'
import { useFlip } from './motion'
import { Avatar, Bar, Num } from './primitives'
import { SectionCard } from './section-card'

// One professor's page: scores, sections and reviews. BYE never picks a professor; this only opens when the student does.
// `matches` applies the class-days rule; `byeReviews` is the host's BYE student-reviews block (live web app only for now).
export function Report({ p, course, matches, back, command, byeReviews }: {
  p: Professor; course: Course; matches: (s: Section) => boolean; back: () => void; command: (c: Command) => void; byeReviews?: React.ReactNode
}) {
  const { demo } = useSurface()
  const [filter, setFilter] = useState('this'), [sort, setSort] = useState('recent'), [visible, setVisible] = useState(4)
  useEffect(() => { setFilter('this'); setVisible(4) }, [p.id, p.profile?.id])
  const profile = p.profile
  const reviews = profile ? orderReviews(filterReviews(profile, course, filter), sort) : []
  // Changing the sort glides each review to its new place.
  const reviewBox = useRef<HTMLDivElement>(null)
  useFlip(reviewBox, reviews.slice(0, visible).map(r => r.id).join('|'))
  const counts = profile?.courseCounts.filter(x => x.label) ?? []
  const thisCount = counts.find(x => sameCourse(course, x.label))?.count
  const chips = [{ value: 'this', label: `This class${thisCount === undefined ? '' : ` · ${thisCount}`}` }, { value: 'all', label: 'All' },
    ...counts.filter(x => !sameCourse(course, x.label)).map(x => ({ value: x.label, label: `${courseLabel(x.label)}${x.count === undefined ? '' : ` · ${x.count}`}` }))]
  return <article key={p.id} className="report report-in" aria-label={`Report for ${p.name}`}>
    <header className="report-bar">
      <button className="back" onClick={back}><span aria-hidden="true">←</span> Professors</button>
      <span className="row"><SampleTag>Sample data</SampleTag><span className="chip">{course.display}</span></span>
    </header>
    <div className="report-body">
      <div className="report-head">
        <Avatar name={p.name} accent size="lg" />
        <h2 className="report-name">{p.name}</h2>
        <SampleTag>Sample professor · not a real PCC instructor</SampleTag>
        <p className="meta">{profile?.department ? `${profile.department} · ` : ''}Pasadena City College
          {profile && (!demo || p.candidates.length > 1) && <button className="text-link" onClick={() => command({ kind: 'discover', professorId: p.id })}>Change profile</button>}</p>
      </div>

      {(p.state === 'loading' || p.state === 'pending') && <p className="placeholder" role="status">Checking RMP for {p.name}…</p>}
      {p.state === 'choose' && <div className="callout"><p><b>{p.candidates.length} RMP profiles match {p.name}.</b> Pick the one that teaches {course.display}. BYE keeps them separate and never guesses.</p>
        <button className="button primary wide" onClick={() => command({ kind: 'discover', professorId: p.id })}>Choose profile <span aria-hidden="true">→</span></button></div>}
      {p.state === 'unavailable' && (unnamed(p)
        ? <div className="callout"><p><b>No instructor named yet.</b> PCC hasn't announced who teaches this section. Check back closer to the start of the semester.</p></div>
        : <div className="callout card" role="status"><p><b className="signal">{p.issue?.includes('access is pending') ? 'RMP access pending.' : 'Cannot retrieve RMP info.'}</b> {p.issue?.includes('access is pending') ? 'PCC sections and BYE reviews are available in this preview.' : <>{p.issue} The PCC sections below remain available; check their retrieval times.</>}</p>
          {!p.issue?.includes('access is pending') && <button className="button secondary wide" onClick={() => command({ kind: 'retry', professorId: p.id })}>Try again</button>}</div>)}

      {profile && <section aria-label="Rate My Professors scores" className="block">
        <div className="stats">
          <div className="stat"><b><Num value={profile.rating} /><small>/5</small></b><span>{demo ? 'Rating · sample' : 'RMP rating'}</span><Bar value={profile.rating} label="Rating" /></div>
          <div className="stat"><b><Num value={profile.difficulty} /><small>/5</small></b><span>Difficulty</span><Bar value={profile.difficulty} label="Difficulty" /></div>
          <div className="stat"><b><Num value={profile.wouldTakeAgain === undefined ? undefined : Math.round(profile.wouldTakeAgain)} digits={0} suffix="%" /></b><span>Would take again</span></div>
        </div>
        <p className="muted small">{profile.ratingCount === undefined ? 'Rating count unavailable' : plural(profile.ratingCount, 'rating')} across all courses · lower difficulty means easier {demo ? ' · sample data' : ''}</p>
      </section>}

      <section className="block">
        <h3>Sections <span className="muted">· {p.sections.length}</span></h3>
        <div className="section-list">{p.sections.map(s => <SectionCard key={s.crn} s={s} matches={matches(s)} />)}</div>
      </section>

      {!demo && !unnamed(p) && byeReviews}
      {profile && <section className="block">
        <div className="row"><h3>{demo ? 'Sample reviews' : 'Rate My Professors reviews'}</h3>
          <select className="bare-select" aria-label="Sort reviews" value={sort} onChange={e => setSort(e.target.value)}>
            <option value="recent">Newest</option><option value="oldest">Oldest</option><option value="highest">Highest rating</option><option value="lowest">Lowest rating</option><option value="difficulty">Lowest difficulty</option><option value="highestDifficulty">Highest difficulty</option>
          </select></div>
        <div className="chip-row" role="group" aria-label="Review course">{chips.map(c =>
          <button key={c.value} type="button" className="pill" aria-pressed={filter === c.value} onClick={() => { setFilter(c.value); setVisible(4); if (!demo) command({ kind: 'details', professorId: p.id, filter: c.value }) }}>{c.label}</button>)}</div>
        {p.detailLoading && <p className="muted small" role="status">Loading more reviews…</p>}
        <div ref={reviewBox} className="review-list">{reviews.slice(0, visible).map(r => <article className="review-card" key={r.id} data-flip={r.id}>
          <div className="row"><span className="chip">{courseLabel(r.course) || 'Course unspecified'}</span><span className="muted small">Posted {monthYear(r.date)}</span></div>
          <p>{r.text}</p>
          <p className="muted small">Rating {r.rating ?? '—'} · Difficulty {r.difficulty ?? '—'}</p>
        </article>)}</div>
        {p.reviewIssue && <div className="notice" role="status"><p>{p.reviewIssue}</p><button className="text-link" onClick={() => command({ kind: 'details', professorId: p.id, filter })}>Try reviews again</button></div>}
        {!demo && profile && !p.detailLoading && <p className="muted small">Showing {reviews.length} retrieved reviews, up to 50 per filter. {profile.source && `RMP checked ${new Date(profile.source.retrievedAt).toLocaleString()}.`}</p>}
        {!reviews.length && !p.detailLoading && <p className="muted">No reviews match this filter. Try All.</p>}
        {visible < reviews.length && <button className="button secondary wide" onClick={() => setVisible(n => n + 6)}>Show more reviews</button>}
        <p className="muted small center">{demo ? 'These reviews are made up for the demo. ' : ''}Ratings reflect student feedback. They don't guarantee a grade.</p>
      </section>}
      {!demo && <div className="source-links"><button className="text-link" onClick={() => command({ kind: 'source', target: 'pcc' })}>PCC schedule ↗</button>{profile && <button className="text-link" onClick={() => command({ kind: 'source', target: 'rmp', professorId: p.id })}>Rate My Professors ↗</button>}</div>}
    </div>
  </article>
}
