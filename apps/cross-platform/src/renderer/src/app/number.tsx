import { useEffect, useRef, useState } from 'react'
import type { ByeNumber } from '../../../shared/app'

/** "BYE-0042"; widens past 9999. Without a number the card shows BYE-····, as on the Mac. */
export const numberLabel = (n?: ByeNumber) => n ? 'BYE-' + String(n.number).padStart(4, '0') : 'BYE-····'
const SCHOOL = /^[a-z0-9._-]+@go\.pasadena\.edu$/

// Getting a BYE number, like the Mac's ByeNumberForm: school email → emailed code → number.
// The email lives only in this form's state; main keeps just the number once the website confirms it.
export function ByeNumberForm({ onNumber }: { onNumber: (n: ByeNumber) => void }) {
  const [email, setEmail] = useState(''), [code, setCode] = useState(''), [sentTo, setSentTo] = useState('')
  const [busy, setBusy] = useState<'' | 'sending' | 'checking'>(''), [error, setError] = useState('')
  const emailField = useRef<HTMLInputElement>(null), codeField = useRef<HTMLInputElement>(null)
  useEffect(() => { (sentTo ? codeField : emailField).current?.focus() }, [sentTo])
  async function send(address: string) {
    const value = address.trim().toLowerCase()
    if (!SCHOOL.test(value)) { setError('Use your PCC school email, ending in @go.pasadena.edu.'); return }
    setBusy('sending'); setError('')
    try {
      const result = await window.byeApp.sendNumberCode(value)
      if (result.ok) { setSentTo(value); setCode('') } else setError(result.message)
    } catch { setError('The code could not be sent. Try again shortly.') }
    finally { setBusy('') }
  }
  async function verify() {
    if (!/^\d{6,10}$/.test(code.trim())) { setError('Enter the complete numeric code from your email.'); return }
    setBusy('checking'); setError('')
    try {
      const result = await window.byeApp.verifyNumberCode(sentTo, code.trim())
      if (result.ok) onNumber(result.number); else setError(result.message)
    } catch { setError('The code could not be confirmed. Try again shortly.') }
    finally { setBusy('') }
  }
  return <div className="number-form">
    {sentTo ? <>
      <p className="muted small">We sent a code to {sentTo}. It can take a minute to arrive.</p>
      <form className="row start" onSubmit={e => { e.preventDefault(); void verify() }}>
        <label className="sr-only" htmlFor="number-code">Code from your email</label>
        <input ref={codeField} id="number-code" className="field" inputMode="numeric" autoComplete="one-time-code" maxLength={10} placeholder="Code from your email"
          value={code} disabled={!!busy} aria-invalid={!!error} aria-describedby="number-error" onChange={e => { setCode(e.target.value); setError('') }} />
        <button className="pill primary" type="submit" disabled={!!busy}>{busy === 'checking' ? 'Checking…' : 'Get my number →'}</button>
      </form>
      <div className="row start">
        <button className="text-link" type="button" disabled={!!busy} onClick={() => void send(sentTo)}>Send a new code</button>
        <button className="text-link" type="button" disabled={!!busy} onClick={() => { setSentTo(''); setCode(''); setError('') }}>Use a different email</button>
      </div>
    </> : <form className="row start" onSubmit={e => { e.preventDefault(); void send(email) }}>
      <label className="sr-only" htmlFor="number-email">Your PCC school email</label>
      <input ref={emailField} id="number-email" className="field" type="email" autoComplete="email" maxLength={254} placeholder="you@go.pasadena.edu"
        value={email} disabled={!!busy} aria-invalid={!!error} aria-describedby="number-error" onChange={e => { setEmail(e.target.value); setError('') }} />
      <button className="pill primary" type="submit" disabled={!!busy}>{busy === 'sending' ? 'Sending…' : 'Send my code →'}</button>
    </form>}
    <p id="number-error" className="field-error" role="alert">{error}</p>
  </div>
}
