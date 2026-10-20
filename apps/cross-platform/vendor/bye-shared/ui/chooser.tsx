import { useEffect, useRef } from 'react'
import type { Command, Course, Professor } from '../core/types'
import { plural } from './format'

// Explicit profile choice when several RMP profiles share a name. BYE never guesses; dismissing leaves the professor unresolved.
export function Chooser({ p, course, command, onSelect }: { p?: Professor; course?: Course; command: (c: Command) => void; onSelect: (profileId: string) => void }) {
  const ref = useRef<HTMLDialogElement>(null)
  useEffect(() => {
    const dialog = ref.current
    if (p?.choosing && dialog && !dialog.open) dialog.showModal()
    if (!p?.choosing && dialog?.open) dialog.close()
  }, [p?.choosing, p?.id])
  const close = () => { if (p) command({ kind: 'dismiss', professorId: p.id }) }
  return <dialog ref={ref} className="sheet" aria-labelledby="chooser-title" onCancel={e => { e.preventDefault(); close() }} onClick={e => { if (e.target === ref.current) close() }}>
    <span className="grabber" aria-hidden="true" />
    <h2 id="chooser-title">Which {p?.name} teaches {course?.display ?? 'this class'}?</h2>
    <p className="muted">{p && p.candidates.length > 1 ? `${p.candidates.length} Rate My Professors profiles share this name.` : 'Confirm the Rate My Professors profile.'} Pick one and BYE will remember it for {course?.subject ?? 'this subject'} classes.</p>
    {p?.issue && <p role="status" className="notice">{p.issue}<button className="text-link" onClick={() => command({ kind: 'discover', professorId: p.id })}>Try again</button></p>}
    {!p?.candidates.length && !p?.issue && <p className="muted" role="status">Looking for profiles…</p>}
    {p?.candidates.map(c => <div className="candidate" key={c.id}>
      <b>{c.firstName} {c.lastName}</b>
      <span>{c.department || 'Department unavailable'}</span>
      <span className="muted small">Pasadena City College · {c.ratingCount === undefined ? 'Rating count unavailable' : plural(c.ratingCount, 'rating')}</span>
      <button className="button secondary wide" onClick={() => onSelect(c.id)}>Use this profile</button>
    </div>)}
    <button className="button ghost wide" onClick={close}>Not now</button>
  </dialog>
}
