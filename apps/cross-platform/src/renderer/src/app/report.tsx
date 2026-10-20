import { useEffect, useRef } from 'react'
import type { Course, Professor } from '../../../shared/types'
import type { Run } from './types'

// The Windows-only parts of the professor screens. The row, the professor page and the course overview are the shared
// screens in vendor/bye-shared/ui (ProfessorRow, Report, EmptyDetail) with the Mac app’s extras turned on in results.tsx.
export const DISCLAIMER = 'Ratings reflect student feedback across reviewed courses. They don’t guarantee a grade.'

// Retained for builds with the AI policy enabled; the current Windows policy keeps it off.
export function Summary({ p, course, run }: { p: Professor; course: Course; run: Run }) {
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
