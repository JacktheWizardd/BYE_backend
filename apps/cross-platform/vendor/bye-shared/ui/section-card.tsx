import { useEffect, useState } from 'react'
import type { Section } from '../core/types'
import { formatLabel, fullyOnline, scheduleNotAnnounced } from '../core/domain'
import { useSurface } from './context'
import { day } from './format'
import { availabilityDeadline, staleSource } from '../core/freshness'

// `matches` is whether the section fits the picked class days; sections that don't are tagged "Other days".
export function SectionCard({ s, matches }: { s: Section; matches: boolean }) {
  const { demo } = useSurface()
  const [clock, setClock] = useState(Date.now)
  useEffect(() => {
    if (!s.source || demo) return
    setClock(Date.now())
    const timer = setTimeout(() => setClock(Date.now()), Math.max(0, availabilityDeadline(s.source) - Date.now()))
    return () => clearTimeout(timer)
  }, [s.source?.retrievedAt, s.source?.expiresAt, s.source?.stale])
  // Stale schedules hide seats and waitlists.
  const stale = staleSource(s.source, Math.max(clock, Date.now()))
  const seats = stale ? undefined : s.details, full = seats?.seatsOpen === 0, other = !matches
  return <article className={`section-card${other ? ' other-days' : ''}`}>
    <div>
      <div className="tags"><span className="chip">CRN {s.crn}</span><span className="tag">{formatLabel(s)}</span>{other && <span className="tag outline">Other days</span>}</div>
      {s.meetings.length ? s.meetings.map(m => <p className="when" key={m}>{m}</p>) : <p className="when">{fullyOnline(s) ? 'No scheduled meetings' : 'Meeting schedule not announced'}</p>}
      {s.meetings.length > 0 && scheduleNotAnnounced(s) && !s.meetings.some(m => m.includes('TBA') || m.includes('no set')) && <p className="muted small">Some meetings not announced</p>}
      <p className="muted small">{s.start && s.end ? `${day(s.start)} – ${day(s.end)}` : 'Dates not announced'}</p>
      {s.details && <p className="muted small">{[s.details.termPart, fullyOnline(s) ? '' : s.details.campus, s.details.units && (s.details.units === '1' ? '1 unit' : `${s.details.units} units`)].filter(Boolean).join(' · ')}</p>}
      {s.source && <p className="muted small">PCC checked {s.source.retrievedAt > 0 ? new Date(s.source.retrievedAt).toLocaleString() : 'time unavailable'}{stale ? ' · Older schedule · seat counts hidden' : ''}</p>}
      {!demo && seats?.seatsOpen === undefined && !stale && <p className="muted small">Seat availability not published.</p>}
    </div>
    {seats?.seatsOpen !== undefined && <div className={`seats${full ? ' full' : ''}`}>
      <div className="seats-label"><b>{seats.seatsOpen}</b> of {seats.capacity ?? '—'} seats open</div>
      <div className="seats-bar"><i style={{ width: `${(seats.capacity ? Math.min(1, seats.seatsOpen / seats.capacity) : 0) * 100}%` }} /></div>
      <div className="seats-wait">{full ? `Full · waitlist ${seats.waitlistCount ?? '—'} of ${seats.waitlistCapacity ?? '—'}` : `Waitlist ${seats.waitlistCount ?? '—'} of ${seats.waitlistCapacity ?? '—'}`}</div>
    </div>}
  </article>
}
