import { useEffect, useRef, useState } from 'react'
import type { Suggestion, Term } from '../../../shared/types'
import { displayTitle } from '../../../../vendor/bye-shared/core/domain'
import { useTypedHint } from '../../../../vendor/bye-shared/ui'
import { shortcut } from './types'

const EXAMPLES = ['MATH 5A', 'ENGL 1A', 'ETH 014']
const greeting = () => { const h = new Date().getHours(); return h < 12 ? 'Morning' : h < 18 ? 'Hey' : 'Evening' }

// Home is the search: greeting, one big course field with suggestions as you type, the semester, and Find professors.
export function Home(props: { name: string; terms: Term[]; termLoading: boolean; termCode: string; setTermCode: (code: string) => void; query: string; setQuery: (q: string) => void
  pending: boolean; progress: string; error: string; search: (text?: string) => void; cancel: () => void; retryTerms: () => void; focusKey: number }) {
  const { terms, termLoading, termCode, setTermCode, query, setQuery, pending, error, search } = props
  const [focused, setFocused] = useState(false), [items, setItems] = useState<Suggestion[]>([]), [index, setIndex] = useState(-1)
  const [suggesting, setSuggesting] = useState(true), [resultContext, setResultContext] = useState('')
  const sequence = useRef(0), input = useRef<HTMLInputElement>(null)
  const hint = useTypedHint(EXAMPLES, !focused && !query)
  const context = JSON.stringify([termCode, query])
  const dismissSuggestions = () => { sequence.current++; setSuggesting(false); setItems([]); setIndex(-1) }
  useEffect(() => { input.current?.focus() }, [props.focusKey])
  useEffect(() => {
    const id = ++sequence.current
    setItems([]); setIndex(-1)
    if (!termCode || !query.trim() || !focused || !suggesting) return
    const timer = setTimeout(() => {
      window.bye.command({ kind: 'suggest', term: termCode, query }).then(result => { if (sequence.current === id) { setItems(result as Suggestion[]); setResultContext(context); setIndex(-1) } }).catch(() => { if (sequence.current === id) setItems([]) })
    }, 180)
    return () => { clearTimeout(timer); sequence.current++ }
  }, [query, termCode, focused, suggesting])
  // Exact codes remain visible while typing; only explicit dismissal closes the list.
  const open = focused && suggesting && resultContext === context && items.length > 0
  const choose = (s: Suggestion) => { dismissSuggestions(); setQuery(s.course.display); input.current?.focus() }
  const term = terms.find(t => t.termCode === termCode)
  return <div className="home">
    {term && <span className="sticker sticker-term" aria-hidden="true">{term.termName}</span>}
    <h1 className="greeting">{greeting()}{props.name ? <>, <span className="swipe">{props.name}</span></> : ''}.</h1>
    <p className="lead">What are you taking next term?</p>
    <form className="home-search" onSubmit={e => { e.preventDefault(); if (open && index >= 0 && items[index]) choose(items[index]); else if (!pending) { dismissSuggestions(); search() } }}>
      <div className="command-field">
        <svg className="glyph" viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7" /><path d="m20 20-3.6-3.6" /></svg>
        <label htmlFor="course" className="sr-only">Class</label>
        <input ref={input} id="course" role="combobox" aria-autocomplete="list" aria-expanded={open} aria-controls="course-options" aria-activedescendant={open && index >= 0 ? `suggestion-${index}` : undefined}
          aria-description="For example, ETH 014 or POLS C1000" placeholder={hint ?? 'MATH 5A'} value={query} autoComplete="off" spellCheck={false}
          onFocus={() => { setFocused(true); setSuggesting(true) }} onBlur={() => { setFocused(false); dismissSuggestions() }} onChange={e => { sequence.current++; setItems([]); setIndex(-1); setSuggesting(true); setQuery(e.target.value) }} onKeyDown={e => {
            if (e.key === 'ArrowDown' && open) { e.preventDefault(); setIndex(i => Math.min(i + 1, items.length - 1)) }
            if (e.key === 'ArrowUp' && open) { e.preventDefault(); setIndex(i => Math.max(i - 1, 0)) }
            if (e.key === 'Escape') { e.preventDefault(); dismissSuggestions() }
          }} />
        <span className="kbd" aria-hidden="true">↵</span>
        {open && <ul className="suggestions" id="course-options" role="listbox" aria-label="Matching PCC courses">{items.map((s, i) =>
          <li id={`suggestion-${i}`} key={s.course.key} role="option" aria-selected={index === i} className={index === i ? 'active' : ''} onMouseDown={e => { e.preventDefault(); choose(s) }}>
            <span className="mono">{s.course.display}</span><span className="muted">{displayTitle(s.title)}</span>
          </li>)}</ul>}
      </div>
      <div className="home-row">
        <label htmlFor="term" className="field-label">Semester</label>
        <select id="term" value={termCode} disabled={termLoading || !terms.length} onChange={e => setTermCode(e.target.value)}>
          {!terms.length && <option value="">{termLoading ? 'Loading semesters…' : 'Select semester'}</option>}
          {terms.map(t => <option key={t.termCode} value={t.termCode}>{t.termName}</option>)}
        </select>
        <button className="pill primary" type="submit" disabled={pending || !terms.length || !query.trim()}>Find professors <span aria-hidden="true">→</span></button>
      </div>
      {pending && <div className="row start" role="status"><span className="spinner" aria-hidden="true" /><span className="muted small">{props.progress}</span><button type="button" className="text-link" onClick={props.cancel}>Cancel</button></div>}
      {error && <div role="alert" className="notice"><p className="muted">{error}</p>{!terms.length && !termLoading && <button type="button" className="text-link" onClick={props.retryTerms}>Retry semesters</button>}</div>}
    </form>
    <div className="try"><span className="muted small">Try</span>{EXAMPLES.map(x => <button key={x} type="button" className="pill mono" disabled={pending || !terms.length} onClick={() => { setQuery(x); search(x) }}>{x}</button>)}</div>
    <p className="hints muted small"><span className="kbd">{shortcut}</span> anywhere · <span className="kbd">↑</span> <span className="kbd">↓</span> to move · <span className="kbd">↵</span> to open</p>
    <span className="sticker sticker-promise" aria-hidden="true">BYE never ranks professors. Promise.</span>
  </div>
}
