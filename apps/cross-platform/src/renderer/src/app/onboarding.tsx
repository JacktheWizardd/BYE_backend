import { useEffect, useRef, useState } from 'react'
import type { ByeNumber } from '../../../shared/app'
import { ByeNumberForm, numberLabel } from './number'
import { NAME_LIMIT, validName } from './types'

// First launch, like the Mac: a welcome, "What should we call you?" next to a student ID card that fills in as you
// type, then the optional BYE number. The name stays on this PC. Skip is always available, and skipping the name
// still asks about the number.
export function Onboarding({ initialName, term, number, onName, onNumber, onDone }: {
  initialName: string; term: string; number?: ByeNumber
  onName: (name: string) => Promise<void>; onNumber: (n: ByeNumber) => void; onDone: (celebrate: boolean) => void
}) {
  const [step, setStep] = useState<0 | 1 | 2>(0), [name, setName] = useState(initialName), [error, setError] = useState(''), [saving, setSaving] = useState(false)
  const [wobble, setWobble] = useState(0)
  const go = useRef<HTMLButtonElement>(null), field = useRef<HTMLInputElement>(null), start = useRef<HTMLButtonElement>(null)
  useEffect(() => { if (step === 0) go.current?.focus(); if (step === 1) field.current?.focus() }, [step])
  useEffect(() => { if (step === 2 && number) start.current?.focus() }, [step, number])
  const initial = name.trim() ? [...name.trim()][0].toUpperCase() : '?'
  useEffect(() => { setWobble(n => n + 1) }, [initial])
  async function next(value: string) {
    if (saving) return
    setSaving(true)
    try { await onName(value); setStep(2) } catch { setError('That name couldn’t be saved. Use letters, spaces, hyphens or apostrophes.') }
    finally { setSaving(false) }
  }
  function submit() {
    const value = name.trim()
    if (!value) { setError('Type a name, or skip for now.'); return }
    if (!validName(value)) { setError('Use letters, spaces, hyphens or apostrophes.'); return }
    void next(value)
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
  const card = <IdCard name={name} initial={initial} wobble={wobble} term={term} number={number} />
  if (step === 1) return <div className="onboarding" role="dialog" aria-modal="true" aria-labelledby="name-title">
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
          <button className="pill ghost" type="button" disabled={saving} onClick={() => { setName(''); void next('') }}>Skip</button>
        </div>
      </div>
      {card}
    </form>
  </div>
  return <div className="onboarding" role="dialog" aria-modal="true" aria-labelledby="number-title">
    <div className="name-step slide-in">
      <div className="name-copy">
        {number ? <>
          <h1 id="number-title">You’re {numberLabel(number)}.</h1>
          <p className="body-copy">Student {number.number} of {number.total}. It’s linked to your school email, so it stays yours on any computer.</p>
          <div className="row start"><button ref={start} className="pill primary" onClick={() => onDone(false)}>Start searching →</button></div>
        </> : <>
          <h1 id="number-title">Want your own BYE number?</h1>
          <p className="body-copy">Verify your PCC school email and BYE gives you a student number, like BYE-0042. It’s yours on any computer and makes your card a little more you. It’s optional.</p>
          <ByeNumberForm onNumber={onNumber} />
          <div className="row start"><button className="pill ghost" onClick={() => onDone(true)}>Skip for now</button></div>
          <p className="muted tiny">BYE keeps your school email and number. Your name and classes stay on this PC.</p>
        </>}
      </div>
      {card}
    </div>
  </div>
}

// The student ID card: name, school, term and BYE number (BYE-···· until there is one).
function IdCard({ name, initial, wobble, term, number }: { name: string; initial: string; wobble: number; term: string; number?: ByeNumber }) {
  return <div className="id-card" aria-hidden="true">
    <div className="id-top"><b>BYE</b><span>Student</span></div>
    <div className="id-body">
      <div className="id-person"><span key={wobble} className="avatar lg accent wobble">{initial}</span>
        <div><div className="id-name">{name.trim() || 'Your name'}</div><div className="id-school">Pasadena City College</div></div></div>
      <div className="id-foot"><span>Term · {term || 'Fall 2026'}</span>
        <span className="id-number"><span key={number?.number ?? 0} className={`mono${number ? ' pop' : ''}`}>{numberLabel(number)}</span>{number && <span>Student {number.number} of {number.total}</span>}</span></div>
      <div className="id-barcode">{Array.from({ length: 34 }, (_, i) => <i key={i} style={{ width: [1, 2, 1, 3, 1, 2][i % 6], marginRight: i % 4 }} />)}</div>
    </div>
  </div>
}
