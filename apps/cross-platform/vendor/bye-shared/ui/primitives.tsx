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
// Scores count up when they appear (off for reduced motion). Screen readers get the final value.
export function Num({ value, digits = 1, suffix = '' }: { value?: number; digits?: number; suffix?: string }) {
  const shown = useCountUp(value)
  if (value === undefined) return <>—</>
  return <span aria-label={value.toFixed(digits) + suffix}><span aria-hidden="true">{(shown ?? value).toFixed(digits)}{suffix}</span></span>
}
