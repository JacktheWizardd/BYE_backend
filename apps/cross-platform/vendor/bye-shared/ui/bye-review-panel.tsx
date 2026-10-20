import type { ByeReviewState } from '../core/types'

/** Read-only shared presentation. The host owns requests; no credentials or network code here. */
export function ByeReviewPanel({ state, load, write }: { state?: ByeReviewState; load: (filter: string, sort: string, more?: boolean) => void; write: () => void }) {
  const s = state, score = (v: number | null | undefined) => v == null ? '—' : v.toFixed(1)
  const filter = s?.filter ?? 'this', sort = s?.sort ?? 'recent'
  return <section className="block bye-reviews" aria-label="BYE student reviews">
    <div className="row"><h3>BYE student reviews</h3><button className="pill" onClick={write}>Write a review ↗</button></div>
    <p className="muted small">PCC students’ feedback submitted to BYE. Separate from Rate My Professors ratings and reviews below.</p>
    {(!s || s.loading) && <p role="status">Loading BYE reviews…</p>}
    {s?.resolution && !s.resolution.professor && <p className="notice">{s.resolution.match === 'ambiguous' ? 'More than one BYE professor matches. Reviews have not been attached automatically.' : 'No exact professor match in the BYE catalog yet.'}</p>}
    {s?.profile && <><div className="stats"><div className="stat"><b>{score(s.profile.quality)}<small>/5</small></b><span>BYE quality</span></div><div className="stat"><b>{score(s.profile.difficulty)}<small>/5</small></b><span>BYE difficulty</span></div></div>
      <p className="muted small">{s.profile.count} BYE {s.profile.count === 1 ? 'review' : 'reviews'} across all courses · Checked {new Date(s.profile.retrievedAt).toLocaleString()}</p></>}
    {s?.ratingIssue && <p role="status" className="notice">{s.ratingIssue}</p>}
    {s?.resolution?.professor && <>
      <div className="row"><label>BYE review course <select aria-label="BYE review course" className="bare-select" value={filter} disabled={s.loading} onChange={e => load(e.target.value, sort)}><option value="this">This class</option><option value="all">All courses</option>{s.profile?.courses.filter(c => c.id !== s.resolution?.course?.id).map(c => <option key={c.id} value={c.id}>{c.code} · {c.count}</option>)}</select></label>
        <label>Sort BYE reviews <select aria-label="Sort BYE reviews" className="bare-select" value={sort} disabled={s.loading} onChange={e => load(filter, e.target.value)}><option value="recent">Newest</option><option value="oldest">Oldest</option><option value="highest">Highest quality</option><option value="lowest">Lowest quality</option><option value="difficulty">Lowest difficulty</option><option value="highestDifficulty">Highest difficulty</option></select></label></div>
      {filter === 'this' && !s.resolution.course && <p className="notice">This class could not be matched uniquely. Choose All courses to read this professor’s reviews.</p>}
      {!s.loading && !s.issue && !s.reviews.length && (filter !== 'this' || s.resolution.course) && <p className="muted">No BYE reviews for this selection yet.</p>}
      {s.reviews.map(r => <article className="review-card" key={r.id}><div className="row"><span className="chip">{r.course || 'Course unspecified'}</span><span className="muted small">{new Date(r.date).toLocaleDateString()}</span></div><p>{r.body || 'No written comment.'}</p><p className="muted small">BYE quality {r.quality}/5 · Difficulty {r.difficulty}/5</p></article>)}
      {s.nextOffset !== null && <button className="pill wide" disabled={s.loading} onClick={() => load(filter, sort, true)}>Show more BYE reviews</button>}
    </>}
    {s?.issue && <p role="alert" className="notice">{s.issue}</p>}
    <button className="text-link" disabled={s?.loading} onClick={() => load(filter, sort)}>Refresh BYE reviews</button>
  </section>
}
