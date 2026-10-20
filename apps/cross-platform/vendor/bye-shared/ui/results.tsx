import React, { useEffect, useLayoutEffect, useRef, useState } from 'react'
import type { Professor, Section, Weekday } from '../core/types'
import { WEEKDAYS, formatLabel } from '../core/domain'
import { useSurface } from './context'
import { plural } from './format'
import { reducedMotion, useFlip } from './motion'
import { ProfessorCard } from './professor-card'

// "I'm free" day bubbles. Results filter as soon as a day is toggled (the class-days rule lives in packages/core).
export function DayBubbles({ days, onChange, disabled = false, label = "I'm free" }: { days: Weekday[]; onChange: (days: Weekday[]) => void; disabled?: boolean; label?: string }) {
  const [popped, setPopped] = useState<Weekday | null>(null)
  const toggle = (d: Weekday) => {
    onChange(days.includes(d) ? days.filter(x => x !== d) : WEEKDAYS.map(w => w.key).filter(k => k === d || days.includes(k)))
    setPopped(null); requestAnimationFrame(() => setPopped(d))
  }
  return <div className="day-bubbles" role="group" aria-label={`${label} (class days)`}>
    <span className="day-bubbles-label" aria-hidden="true">{label}</span>
    <span className="day-bubbles-row">{WEEKDAYS.map(d =>
      <button key={d.key} type="button" className={`day-bubble${popped === d.key ? ' pop' : ''}`} aria-pressed={days.includes(d.key)} aria-label={d.label} disabled={disabled}
        onClick={() => toggle(d.key)} onAnimationEnd={() => setPopped(null)}>{d.short}</button>)}</span>
  </div>
}

// A segmented control with a highlight that slides to the chosen option.
export function Segmented<T extends string>({ label, options, value, onChange }: { label: string; options: readonly (readonly [T, string])[]; value: T; onChange: (value: T) => void }) {
  const box = useRef<HTMLDivElement>(null), [thumb, setThumb] = useState<{ left: number; width: number } | null>(null)
  useLayoutEffect(() => {
    const measure = () => { const on = box.current?.querySelector<HTMLElement>('[aria-pressed="true"]'); if (on) setThumb({ left: on.offsetLeft, width: on.offsetWidth }) }
    measure()
    // A control that starts hidden (inside a closed dialog) measures zero; measure again once it is shown or resized.
    if (typeof ResizeObserver !== 'function' || !box.current) return
    const observer = new ResizeObserver(measure); observer.observe(box.current)
    return () => observer.disconnect()
  }, [value, options.map(o => o[1]).join('|')])
  return <div ref={box} className="segmented" role="group" aria-label={label}>
    {thumb && <span className="segmented-thumb" aria-hidden="true" style={{ transform: `translateX(${thumb.left}px)`, width: thumb.width }} />}
    {options.map(([key, text]) => <button key={key} type="button" aria-pressed={value === key} onClick={() => onChange(key)}>{text}</button>)}
  </div>
}

// The professor list. The open professor gets an outlined highlight that slides between rows; re-sorting and filtering
// glide rows into place. ↑ and ↓ move between professors (and open them when `openOnArrow`, as on desktop).
// `renderRow` lets a host draw its own row (the Windows app adds Mac-style row actions); its main button must have class `prof-card`.
export function ProfessorList({ list, selectedId, onOpen, openOnArrow = false, renderRow }: {
  list: Professor[]; selectedId?: string; onOpen: (p: Professor) => void; openOnArrow?: boolean
  renderRow?: (p: Professor, selected: boolean, open: () => void) => React.ReactNode
}) {
  const box = useRef<HTMLDivElement>(null), [mark, setMark] = useState<{ top: number; height: number } | null>(null)
  const order = list.map(p => p.id).join('|')
  useFlip(box, order)
  useLayoutEffect(() => {
    const row = selectedId ? box.current?.querySelector<HTMLElement>(`[data-flip="${CSS.escape(selectedId)}"]`) : null
    setMark(row ? { top: row.offsetTop, height: row.offsetHeight } : null)
  }, [selectedId, order, list])
  const onKeyDown = (e: React.KeyboardEvent) => {
    if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return
    const rows = Array.from(box.current?.querySelectorAll<HTMLButtonElement>('.prof-card') ?? []), at = rows.indexOf(document.activeElement as HTMLButtonElement)
    if (at < 0) return
    e.preventDefault()
    const next = Math.max(0, Math.min(rows.length - 1, at + (e.key === 'ArrowDown' ? 1 : -1)))
    rows[next].focus()
    if (openOnArrow && next !== at) onOpen(list[next])
  }
  return <div ref={box} className="prof-list" onKeyDown={onKeyDown}>
    <span className={`prof-mark${mark ? ' on' : ''}`} aria-hidden="true" style={mark ? { transform: `translateY(${mark.top}px)`, height: mark.height } : undefined} />
    {list.map((p, i) => <div key={p.id} data-flip={p.id} className="prof-slot" style={{ '--n': i } as React.CSSProperties}>
      {renderRow ? renderRow(p, p.id === selectedId, () => onOpen(p)) : <ProfessorCard p={p} selected={p.id === selectedId} onOpen={() => onOpen(p)} />}
    </div>)}
  </div>
}

const LOADING = ['Asking around…', 'Reading the PCC schedule…', 'Counting open seats…']
// Skeleton rows while the schedule loads, with a little rotating copy.
export function LoadingRows() {
  const [i, setI] = useState(0)
  useEffect(() => {
    if (reducedMotion()) return
    const id = setInterval(() => setI(n => (n + 1) % LOADING.length), 1200)
    return () => clearInterval(id)
  }, [])
  return <div className="loading-rows">
    <p className="loading-copy" role="status">{LOADING[i]}</p>
    {[0, 1, 2].map(n => <div key={n} className="skeleton-row" aria-hidden="true"><span className="skeleton-dot" /><span className="skeleton-lines"><i /><i /></span></div>)}
  </div>
}

// Counts per label, most common first: "In person 3 · Online · async 1".
const breakdown = (labels: string[]) => [...labels.reduce((m, l) => m.set(l, (m.get(l) ?? 0) + 1), new Map<string, number>())]
  .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).map(([l, n]) => `${l} ${n}`).join(' · ')

// The detail pane before the student opens anyone: neutral facts about the class. BYE never picks a professor.
// With `sections` (the listed sections) it also counts them and breaks them down by format and term part, like the Mac.
// `caption` is a one-line course summary; `children` are extra notes under the facts.
export function EmptyDetail({ professors, openSeats, sections, caption, children }: { professors: number; openSeats?: number; sections?: Section[]; caption?: string; children?: React.ReactNode }) {
  const { demo } = useSurface()
  if (!professors) return <div className="empty-detail">
    <h2>No sections to show</h2>
    <p className="muted">Nobody teaches this on all of those days. Try unticking a day, or search another class.</p>
  </div>
  const unique = sections && [...new Map(sections.map(s => [s.crn, s])).values()]
  const formats = unique ? breakdown(unique.map(formatLabel)) : '', terms = unique ? breakdown(unique.map(s => s.details?.termPart ?? '').filter(Boolean)) : ''
  const sample = demo ? ' · sample' : ''
  return <section className="empty-detail" aria-label="Course overview">
    <svg className="drawn-arrow" viewBox="0 0 78 44" aria-hidden="true"><path d="M74 10 C 52 2, 24 6, 9 30" /><path d="M5 17 L9 31 L22 27" /></svg>
    <h2>Pick a professor.</h2>
    <p className="muted">We line them up, you decide. BYE won't choose for you.</p>
    {caption && <p className="muted small">{caption}</p>}
    <div className="empty-stats">
      {unique && <div className="stat"><b>{unique.length}</b><span>{plural(unique.length, 'section').replace(/^\d+ /, '')}{sample}</span></div>}
      <div className="stat"><b>{professors}</b><span>{plural(professors, 'professor').replace(/^\d+ /, '')}{sample}</span></div>
      {openSeats !== undefined && <div className="stat"><b>{openSeats}</b><span>open seats{sample}</span></div>}
    </div>
    {(formats || terms) && <dl className="facts">{formats && <><dt>Format</dt><dd className="muted">{formats}</dd></>}{terms && <><dt>Term</dt><dd className="muted">{terms}</dd></>}</dl>}
    {children}
  </section>
}
