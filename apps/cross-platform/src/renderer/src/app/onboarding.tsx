import { useEffect, useRef, useState } from 'react'
import { NAME_LIMIT, validName } from './types'

// First launch: a welcome, then "What should we call you?" next to a student ID card that fills in as you type.
// The name stays on this PC. Skip is always available.
export function Onboarding({ initialName, term, onDone }: { initialName: string; term: string; onDone: (name: string) => Promise<void> }) {
  const [step, setStep] = useState<0 | 1>(0), [name, setName] = useState(initialName), [error, setError] = useState(''), [saving, setSaving] = useState(false)
  const [wobble, setWobble] = useState(0)
  const go = useRef<HTMLButtonElement>(null), field = useRef<HTMLInputElement>(null)
  useEffect(() => { (step === 0 ? go : field).current?.focus() }, [step])
  const initial = name.trim() ? [...name.trim()][0].toUpperCase() : '?'
  useEffect(() => { setWobble(n => n + 1) }, [initial])
  async function finish(value: string) {
    if (saving) return
    setSaving(true)
    try { await onDone(value) } catch { setError('That name couldn’t be saved. Use letters, spaces, hyphens or apostrophes.'); setSaving(false) }
  }
  function submit() {
    const value = name.trim()
    if (!value) { setError('Type a name, or skip for now.'); return }
    if (!validName(value)) { setError('Use letters, spaces, hyphens or apostrophes.'); return }
    void finish(value)
  }
  if (step === 0) return <div className="onboarding" role="dialog" aria-modal="true" aria-labelledby="welcome-title">
    <div className="welcome slide-in">
      <div className="welcome-mark"><span className="swipe">BYE</span></div>
      <p className="welcome-sub">Before You Enroll</p>
      <h1 id="welcome-title">Find the class that fits your week.</h1>
      <p className="lead">Every PCC section, seat and professor review in one spot. Made by a PCC student, for PCC students.</p>
      <button ref={go} className="pill primary large" onClick={() => setStep(1)}>Let’s go →</button>
    </div>
  </div>
  return <div className="onboarding" role="dialog" aria-modal="true" aria-labelledby="name-title">
    <form className="name-step slide-in" onSubmit={e => { e.preventDefault(); submit() }}>
      <div className="name-copy">
        <h1 id="name-title">First things first. What should we call you?</h1>
        <p className="muted small">It stays on this computer. Promise.</p>
        <label className="sr-only" htmlFor="your-name">Your name</label>
        <input ref={field} id="your-name" className="field" maxLength={NAME_LIMIT} placeholder="Your first name" autoComplete="given-name" value={name}
          aria-invalid={!!error} aria-describedby="name-error" onChange={e => { setName(e.target.value); setError('') }} />
        <p id="name-error" className="field-error" role="alert">{error}</p>
        <div className="row start">
          <button className="pill primary" type="submit" disabled={saving}>That’s me →</button>
          <button className="pill ghost" type="button" disabled={saving} onClick={() => void finish('')}>Skip</button>
        </div>
      </div>
      <div className="id-card" aria-hidden="true">
        <div className="id-top"><b>BYE</b><span>Student</span></div>
        <div className="id-body">
          <div className="id-person"><span key={wobble} className="avatar lg accent wobble">{initial}</span>
            <div><div className="id-name">{name.trim() || 'Your name'}</div><div className="id-school">Pasadena City College</div></div></div>
          <div className="id-foot"><span>Term · {term || 'Fall 2026'}</span><span className="mono">BYE-0001</span></div>
          <div className="id-barcode">{Array.from({ length: 34 }, (_, i) => <i key={i} style={{ width: [1, 2, 1, 3, 1, 2][i % 6], marginRight: i % 4 }} />)}</div>
        </div>
      </div>
    </form>
  </div>
}
