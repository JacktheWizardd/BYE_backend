import { useEffect, useState } from 'react'
import type { Section } from '../core/types'
import { formatLabel } from '../core/domain'
import { useSurface } from './context'
import { day } from './format'

// `matches` is whether the section fits the picked class days; sections that don't are tagged "Other days".
export function SectionCard({ s, matches }: { s: Section; matches: boolean }) {
  const { demo } = useSurface()
  const [clock, setClock] = useState(Date.now)
  useEffect(() => {
    if (!s.source || demo) return
    const timer = setTimeout(() => setClock(Date.now()), Math.max(0, 300_000 - (Date.now() - s.source.retrievedAt)))
    return () => clearTimeout(timer)
  }, [s.source?.retrievedAt])
  // Stale schedules hide seats and waitlists.
  const stale = s.source?.stale || (!!s.source && clock - s.source.retrievedAt >= 300_000)
  const seats = stale ? undefined : s.details, full = seats?.seatsOpen === 0, other = !matches
  return <article className={`section-card${other ? ' other-days' : ''}`}>
    <div>
      <div className="tags"><span className="chip">CRN {s.crn}</span><span className="tag">{formatLabel(s)}</span>{other && <span className="tag outline">Other days</span>}</div>
      {s.meetings.length ? s.meetings.map(m => <p className="when" key={m}>{m}</p>) : <p className="when">{formatLabel(s) === 'Online · async' ? 'No scheduled meetings' : 'Meeting schedule not announced'}</p>}
      <p className="muted small">{s.start && s.end ? `${day(s.start)} – ${day(s.end)}` : 'Dates not announced'}</p>
      {s.details && <p className="muted small">{[s.details.termPart, s.details.campus, s.details.units && `${s.details.units} units`].filter(Boolean).join(' · ')}</p>}
      {s.source && <p className="muted small">PCC checked {new Date(s.source.retrievedAt).toLocaleString()}{stale ? ' · Older schedule · seat counts hidden' : ''}</p>}
      {!demo && seats?.seatsOpen === undefined && !stale && <p className="muted small">Seat availability not published.</p>}
    </div>
    {seats?.seatsOpen !== undefined && <div className={`seats${full ? ' full' : ''}`}>
      <div className="seats-label"><b>{seats.seatsOpen}</b> of {seats.capacity ?? '—'} seats open</div>
      <div className="seats-bar"><i style={{ width: `${(seats.capacity ? Math.min(1, seats.seatsOpen / seats.capacity) : 0) * 100}%` }} /></div>
      <div className="seats-wait">{full ? `Full · waitlist ${seats.waitlistCount ?? '—'} of ${seats.waitlistCapacity ?? '—'}` : `Waitlist ${seats.waitlistCount ?? '—'} of ${seats.waitlistCapacity ?? '—'}`}</div>
    </div>}
  </article>
}
