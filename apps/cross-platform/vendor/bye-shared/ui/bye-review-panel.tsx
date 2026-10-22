import React, { useId } from 'react'
import type { ByeReviewState } from '../core/types'
import type { ByeWrittenReview } from '../core/reviews'
import { stampTier, type StampTier } from '../core/domain'
import { monthYear } from './format'

/** Read-only shared presentation. The host owns requests; no credentials or network code here. */

/** The small source tag at the end of an RMP review's score line: a plain outline. BYE reviews carry a stamp instead. */
export function SourceTag({ source }: { source: 'bye' | 'rmp' }) {
  return <span className={`source-tag ${source}`} title={source === 'bye' ? 'From BYE students' : 'From Rate My Professors'}>{source === 'bye' ? 'BYE' : 'RMP'}</span>
}

// A 40×50 postage stamp: a perforated frame (an SVG mask punches the holes), a panel and "BYE". The tier only changes the
// look, never what the review says; it comes from the review ID (see stampTier), so the same review keeps the same stamp.
const W = 40, H = 50, HOLE = 1.8, STEP = 5
const HOLES: [number, number][] = []
for (let x = STEP / 2; x < W; x += STEP) HOLES.push([x, 0], [x, H])
for (let y = STEP / 2; y < H; y += STEP) HOLES.push([0, y], [W, y])
const WAVES = 'M19 35q3-2 6 0t6 0t6 0t6 0M19 39q3-2 6 0t6 0t6 0t6 0M19 43q3-2 6 0t6 0t6 0t6 0'

/** A BYE review's collectible stamp. Colors come from tokens in styles.css (.bye-stamp.{tier}). */
export function ByeStamp({ tier }: { tier: StampTier }) {
  const mask = 'stamp' + useId().replace(/:/g, ''), label = `From BYE students · ${tier} stamp`
  return <span className={`source-tag bye bye-stamp ${tier}`} role="img" aria-label={label} title={label}>
    <svg viewBox={`0 0 ${W} ${H}`} aria-hidden="true">
      <defs><mask id={mask}><rect width={W} height={H} fill="#fff" />{HOLES.map(([x, y]) => <circle key={x + '-' + y} cx={x} cy={y} r={HOLE} fill="#000" />)}</mask></defs>
      <g mask={`url(#${mask})`}><rect className="stamp-frame" width={W} height={H} />{tier === 'uncommon' && <rect className="stamp-edge" x="0.6" y="0.6" width={W - 1.2} height={H - 1.2} />}</g>
      <rect className="stamp-panel" x="4.5" y="4.5" width={W - 9} height={H - 9} rx="1" />
      {tier === 'legendary' && <rect className="stamp-rule" x="6.3" y="6.3" width={W - 12.6} height={H - 12.6} rx="0.6" />}
      {tier === 'uncommon' && <rect className="stamp-swipe" x="7" y="27.5" width="26" height="4" rx="1.5" />}
      <text className="stamp-word" x={W / 2} y="29.5" textAnchor="middle" textLength="23" lengthAdjust="spacingAndGlyphs">BYE</text>
      {(tier === 'epic' || tier === 'legendary') && <g className="stamp-postmark"><circle cx="31" cy="38" r="7" /><path d={WAVES} /></g>}
    </svg>
  </span>
}

/** BYE's own score row. It sits above the RMP row and is never blended with it. */
export function ByeScores({ state }: { state?: ByeReviewState }) {
  const s = state, score = (v: number | null | undefined) => v == null ? '—' : v.toFixed(1)
  return <section className="block bye-scores" aria-label="BYE student ratings">
    <p className="score-source"><ByeStamp tier="common" /> BYE student ratings</p>
    {(!s || (s.loading && !s.resolution)) && <p className="muted small" role="status">Finding BYE ratings…</p>}
    {s?.resolution && !s.resolution.professor && <p className="muted small">{s.resolution.match === 'ambiguous' ? 'More than one BYE professor matches this name, so no BYE ratings are attached.' : 'No BYE ratings for this professor yet.'}</p>}
    {s?.profile && <><div className="stats"><div className="stat"><b>{score(s.profile.quality)}<small>/5</small></b><span>BYE quality</span></div><div className="stat"><b>{score(s.profile.difficulty)}<small>/5</small></b><span>BYE difficulty</span></div></div>
      <p className="muted small">{s.profile.count} BYE {s.profile.count === 1 ? 'review' : 'reviews'} across all courses · Checked {new Date(s.profile.retrievedAt).toLocaleString()}</p></>}
    {s?.ratingIssue && <p role="status" className="notice">{s.ratingIssue}</p>}
  </section>
}

/** One BYE review in the merged list. `actions` is the host's extra row (the web's "Report review"). */
export function ByeReviewCard({ r, actions }: { r: ByeWrittenReview; actions?: React.ReactNode }) {
  return <article className="review-card review" data-flip={'bye-' + r.id}>
    <div className="row review-heading"><strong className="chip">{r.course || 'Course unspecified'}</strong><span className="muted small">Posted {monthYear(r.date)}</span></div>
    <p className="bye-comment">{r.body || 'No written comment.'}</p>
    <div className="row review-foot"><span className="muted small">Quality {r.quality}/5 · Difficulty {r.difficulty}/5</span><ByeStamp tier={stampTier(r.id)} /></div>
    {actions}
  </article>
}
