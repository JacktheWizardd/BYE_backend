import { useEffect, useRef, useState } from 'react'
import type { Suggestion } from '../../../shared/types'
import { displayTitle } from '../../../../vendor/bye-shared/core/domain'

export type Action = 'home' | 'settings' | 'updates' | 'name' | 'welcome'
const ACTIONS: [Action, string][] = [['home', 'Go home'], ['settings', 'Open settings'], ['updates', 'Check for updates'], ['name', 'Change your name'], ['welcome', 'Show welcome again']]
type Item = { kind: 'class'; display: string; title: string } | { kind: 'action'; action: Action; label: string }

// Ctrl K / ⌘K from anywhere: jump to a class (PCC suggestions for the chosen semester, or your recent classes) or run an action.
export function CommandMenu({ open, termCode, recent, onClose, onClass, onAction }: { open: boolean; termCode: string; recent: string[]; onClose: () => void; onClass: (display: string) => void; onAction: (a: Action) => void }) {
  const dialog = useRef<HTMLDialogElement>(null), input = useRef<HTMLInputElement>(null)
  const [query, setQuery] = useState(''), [found, setFound] = useState<Suggestion[]>([]), [index, setIndex] = useState(0)
  const sequence = useRef(0)
  useEffect(() => {
    const d = dialog.current
    if (open && d && !d.open) { setQuery(''); setFound([]); setIndex(0); d.showModal(); input.current?.focus() }
    if (!open && d?.open) d.close()
  }, [open])
  useEffect(() => {
    const id = ++sequence.current
    if (!open || !termCode || !query.trim()) { setFound([]); return }
    const timer = setTimeout(() => { window.bye.command({ kind: 'suggest', term: termCode, query }).then(r => { if (sequence.current === id) setFound(r as Suggestion[]) }).catch(() => { if (sequence.current === id) setFound([]) }) }, 120)
    return () => clearTimeout(timer)
  }, [query, termCode, open])
  const needle = query.trim().toLowerCase()
  const classes: Item[] = needle ? found.slice(0, 4).map(s => ({ kind: 'class', display: s.course.display, title: displayTitle(s.title) }))
    : recent.slice(0, 3).map(display => ({ kind: 'class', display, title: 'Recent' }))
  const actions: Item[] = ACTIONS.filter(([, label]) => !needle || label.toLowerCase().includes(needle)).map(([action, label]) => ({ kind: 'action', action, label }))
  const items = [...classes, ...actions], active = Math.min(index, Math.max(0, items.length - 1))
  const run = (item: Item) => { onClose(); if (item.kind === 'class') onClass(item.display); else onAction(item.action) }
  let n = -1
  const option = (item: Item) => { n++; const i = n
    return <li key={item.kind === 'class' ? 'c' + item.display : 'a' + item.action} id={`command-${i}`} role="option" aria-selected={i === active} className={i === active ? 'active' : ''}
      onMouseMove={() => setIndex(i)} onMouseDown={e => { e.preventDefault(); run(item) }}>
      {item.kind === 'class' ? <><span className="mono">{item.display}</span><span className="muted">{item.title}</span></> : <span>{item.label}</span>}
      <span className="kbd ret" aria-hidden="true">↵</span>
    </li> }
  return <dialog ref={dialog} className="command-menu" aria-label="Command menu" onCancel={e => { e.preventDefault(); onClose() }} onClick={e => { if (e.target === dialog.current) onClose() }}>
    <div className="command-input">
      <input ref={input} role="combobox" aria-expanded="true" aria-controls="command-options" aria-activedescendant={items.length ? `command-${active}` : undefined}
        aria-label="Type a command or a class" placeholder="Type a command or a class…" value={query} autoComplete="off" spellCheck={false}
        onChange={e => { setQuery(e.target.value); setIndex(0) }} onKeyDown={e => {
          if (e.key === 'ArrowDown') { e.preventDefault(); setIndex(Math.min(active + 1, items.length - 1)) }
          if (e.key === 'ArrowUp') { e.preventDefault(); setIndex(Math.max(active - 1, 0)) }
          if (e.key === 'Enter' && items[active]) { e.preventDefault(); run(items[active]) }
        }} />
      <span className="kbd" aria-hidden="true">Esc</span>
    </div>
    <ul id="command-options" role="listbox" aria-label="Commands and classes">
      {classes.length > 0 && <li role="presentation" className="group-label">{needle ? 'Classes' : 'Your classes'}</li>}
      {classes.map(option)}
      {actions.length > 0 && <li role="presentation" className="group-label">Actions</li>}
      {actions.map(option)}
      {!items.length && <li role="presentation" className="muted small empty-note">Nothing matches. Try a class code like MATH 5A.</li>}
    </ul>
  </dialog>
}
