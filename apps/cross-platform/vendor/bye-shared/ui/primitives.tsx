import { useCountUp } from './motion'

export function Wordmark() { return <span className="wordmark"><b>BYE</b></span> }
export function Bar({ value, label, max = 5 }: { value?: number; label: string; max?: number }) {
  return <span className="bar" role="img" aria-label={`${label} ${value === undefined ? 'unknown' : value} out of ${max}`}><i style={{ width: `${((value ?? 0) / max) * 100}%` }} /></span>
}
// Initials in a circle. `accent` (yellow) is a playful accent for the open professor's page only.
export function Avatar({ name, accent = false, size = 'md' }: { name: string; accent?: boolean; size?: 'md' | 'lg' }) {
  const initials = name.split(/\s+/).filter(Boolean).map(w => w[0]).filter(c => /\p{L}/u.test(c)).slice(0, 2).join('').toUpperCase()
  return <span className={`avatar ${size}${accent ? ' accent' : ''}`} aria-hidden="true">{initials || '?'}</span>
}
// Scores count up when they appear (off for reduced motion). Screen readers get the final value. The final value also sits
// invisibly underneath to fix the width, so a number gaining digits (8% → 80%) never shifts the layout.
// Changing `restartKey` (for example the professor) counts up from zero again; otherwise new values glide from the old one.
export function Num({ value, digits = 1, suffix = '', restartKey }: { value?: number; digits?: number; suffix?: string; restartKey?: string }) {
  const shown = useCountUp(value, 900, restartKey)
  if (value === undefined) return <>—</>
  const final = value.toFixed(digits) + suffix
  return <span className="num" aria-label={final}><span className="num-size" aria-hidden="true">{final}</span><span className="num-live" aria-hidden="true">{(shown ?? value).toFixed(digits)}{suffix}</span></span>
}
