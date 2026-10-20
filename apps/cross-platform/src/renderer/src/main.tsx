import { useEffect, useLayoutEffect, useRef, useState } from 'react'
import { createRoot } from 'react-dom/client'
import type { Snapshot, Term, Weekday } from '../../shared/types'
import type { AppSettings } from '../../shared/app'
import { WEEKDAYS, displayTitle, filterSections, orderProfessors } from '../../../vendor/bye-shared/core/domain'
import { SurfaceProvider } from '../../../vendor/bye-shared/ui'
import { AI_SUMMARIES_ENABLED } from '../../shared/features'
import { CommandMenu, type Action } from './app/command-menu'
import { confetti } from './app/confetti'
import { Home } from './app/home'
import { Onboarding } from './app/onboarding'
import { Results } from './app/results'
import { SettingsSheet, type SettingsTab } from './app/settings-sheet'
import { isMac, shortcut, type Run } from './app/types'
import '../../../vendor/bye-shared/ui/styles.css'
import './app/app.css'

// The Windows app follows the approved v3 design (docs/APP_REDESIGN_PLAN.md in the website repository) and the Mac app's
// behavior (Sources/Classwise/Views). Shared screens and tokens come from vendor/bye-shared (synced from the website).
const empty: Snapshot = { operationId: '', professors: [], loading: false, previewPending: 0 }
const RECENT_LIMIT = 5

function App() {
  const [settings, setSettings] = useState<AppSettings | null>(null), [version, setVersion] = useState('')
  const [onboarding, setOnboarding] = useState(false)
  const [state, setState] = useState(empty), [terms, setTerms] = useState<Term[]>([]), [termCode, setTermCode] = useState(''), [termLoading, setTermLoading] = useState(true)
  const [query, setQuery] = useState(''), [view, setView] = useState<'home' | 'results'>('home'), [pending, setPending] = useState(false), [error, setError] = useState('')
  const [days, setDays] = useState<Weekday[]>([]), [onlineOnly, setOnlineOnly] = useState(false), [sort, setSort] = useState('rating'), [showAll, setShowAll] = useState(false), [selected, setSelected] = useState('')
  const [menu, setMenu] = useState(false), [sheet, setSheet] = useState(false), [tab, setTab] = useState<SettingsTab>('general'), [homeFocus, setHomeFocus] = useState(0)
  const started = useRef(''), lastOperation = useRef(''), reportOpened = useRef(''), summarized = useRef('')
  const run: Run = command => { window.bye.command(command).catch(e => setError(e instanceof Error ? e.message : 'This action failed. Try again.')) }
  const save = async (update: Partial<AppSettings>) => { const next = await window.byeApp.setSettings(update); setSettings(next); return next }

  async function loadTerms() {
    setTermLoading(true); setError('')
    try { const result = await window.bye.command({ kind: 'terms' }) as Term[]; setTerms(result); setTermCode(old => result.some(t => t.termCode === old) ? old : result[0]?.termCode ?? ''); if (!result.length) setError('PCC has no published semesters right now.') }
    catch (e) { setError(e instanceof Error ? e.message : 'PCC semesters are unavailable. Try again.') }
    finally { setTermLoading(false) }
  }
  useEffect(() => {
    const unsubscribe = window.bye.subscribe(setState); void loadTerms()
    window.byeApp.getSettings().then(s => { setSettings(s); setOnboarding(!s.onboarded) }).catch(() => setSettings({ name: '', onboarded: true, recent: [] }))
    window.byeApp.info().then(i => setVersion(i.version)).catch(() => {})
    return unsubscribe
  }, [])
  // Ctrl K / ⌘K opens the command menu from anywhere (not during first-run setup).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if ((isMac ? e.metaKey : e.ctrlKey) && e.key.toLowerCase() === 'k' && !onboarding) { e.preventDefault(); setSheet(false); setMenu(true) } }
    addEventListener('keydown', onKey); return () => removeEventListener('keydown', onKey)
  }, [onboarding])
  // A new search opens on the course overview; no professor opens automatically.
  useEffect(() => { if (state.operationId !== lastOperation.current) { lastOperation.current = state.operationId; setSelected(''); setShowAll(false); reportOpened.current = ''; summarized.current = '' } }, [state.operationId])
  useEffect(() => {
    if (!pending || state.operationId === started.current) return
    if (state.course) {
      setPending(false); setView('results'); setQuery(state.course.display)
      // Remember the class on this PC for the sidebar and command menu.
      const display = state.course.display
      if (settings && settings.recent[0] !== display) void save({ recent: [display, ...settings.recent.filter(x => x !== display)].slice(0, RECENT_LIMIT) }).catch(() => {})
    } else if (!state.loading) { setPending(false); if (state.issue) setError(state.issue) }
  }, [pending, state])

  const course = state.course
  const filtered = course ? orderProfessors(filterSections(state.professors, days, onlineOnly), sort, course) : []
  const displayed = showAll ? filtered : filtered.slice(0, 5)
  const p = filtered.find(x => x.id === selected)
  // Incoming ratings may reorder the top five. Keep the report the student opened; if filters hide it, return to the course overview.
  useEffect(() => { if (selected && course && !filtered.some(x => x.id === selected)) setSelected('') })
  useEffect(() => {
    if (!p?.profile || p.state !== 'ready' || state.previewPending || state.loading) return
    const key = `${state.operationId}|${p.id}|${p.profile.id}`
    if (reportOpened.current !== key) { reportOpened.current = key; run({ kind: 'details', professorId: p.id }) }
  }, [p?.id, p?.profile?.id, p?.state, state.previewPending, state.loading])
  useEffect(() => {
    if (!AI_SUMMARIES_ENABLED || !p?.profile || p.detailLoading || p.state !== 'ready' || state.loading || state.previewPending) return
    const key = `${state.operationId}|${p.id}|${p.profile.id}|${JSON.stringify(p.profile.reviews)}`
    if (summarized.current !== key) { summarized.current = key; run({ kind: 'summary', professorId: p.id }) }
  }, [p?.id, p?.profile, p?.detailLoading, p?.state, state.loading, state.previewPending])

  function search(refresh = false, text = query) {
    const term = refresh ? state.term : terms.find(t => t.termCode === termCode)
    if (!term || !text.trim()) return
    setError(''); started.current = state.operationId
    if (!refresh) setPending(true)
    run({ kind: 'search', query: text, term, refresh })
  }
  const stop = () => { setPending(false); run({ kind: 'stop' }) }
  const goHome = () => { stop(); setError(''); setView('home'); setHomeFocus(n => n + 1) }
  const openClass = (display: string) => { setQuery(display); if (view === 'results') { stop(); setView('home') } search(false, display) }
  function action(a: Action) {
    if (a === 'home') goHome()
    if (a === 'settings' || a === 'name') { setTab('general'); setSheet(true) }
    if (a === 'updates') { setTab('updates'); setSheet(true) }
    if (a === 'welcome') { setSheet(false); setOnboarding(true) }
  }
  const checked = state.professors.filter(x => x.state !== 'pending' && x.state !== 'loading').length
  const title = displayTitle(state.professors[0]?.sections[0]?.title ?? '')
  const summary = [state.term?.termName ?? '', WEEKDAYS.filter(d => days.includes(d.key)).map(d => d.key).join(', '), onlineOnly ? 'Fully online' : ''].filter(Boolean).join(' · ')
  const termName = terms.find(t => t.termCode === termCode)?.termName ?? ''

  if (!settings) return <div className="app-loading" aria-busy="true" />
  if (onboarding) return <Onboarding initialName={settings.name} term={termName} onDone={async name => {
    await save({ name, onboarded: true }); setOnboarding(false); setView('home'); setHomeFocus(n => n + 1); confetti()
  }} />
  const active = view === 'home' ? 'home' : course?.display ?? ''
  return <SurfaceProvider demo={false}><div className="app-frame">
    <Sidebar name={settings.name} recent={settings.recent} active={active} onHome={goHome} onClass={openClass} onMenu={() => setMenu(true)}
      onRemove={display => void save({ recent: settings.recent.filter(x => x !== display) })} onSettings={() => { setTab('general'); setSheet(true) }} />
    <main className="panel">
      {view === 'home'
        ? <Home name={settings.name} terms={terms} termLoading={termLoading} termCode={termCode} setTermCode={setTermCode} query={query} setQuery={setQuery} focusKey={homeFocus}
            pending={pending} progress={state.professors.length ? `Checking ratings · ${checked} of ${state.professors.length}` : 'Finding classes at PCC…'} error={error} search={text => search(false, text)} cancel={stop} retryTerms={() => void loadTerms()} />
        : <Results state={state} title={title} summary={summary} filtered={filtered} displayed={displayed} showAll={showAll} setShowAll={setShowAll}
            days={days} setDays={setDays} onlineOnly={onlineOnly} setOnlineOnly={setOnlineOnly} sort={sort} setSort={setSort}
            selected={selected} select={id => { setSelected(id); setError('') }} run={run} refresh={() => course && search(true, course.display)} changeSearch={goHome} stop={stop} error={error} />}
    </main>
    <CommandMenu open={menu} termCode={termCode} recent={settings.recent} onClose={() => setMenu(false)} onClass={openClass} onAction={action} />
    <SettingsSheet open={sheet} tab={tab} setTab={setTab} name={settings.name} version={version} onClose={() => setSheet(false)}
      onSaveName={async name => { await save({ name }) }} onWelcome={() => action('welcome')} />
  </div></SurfaceProvider>
}

// Sidebar: search, Home, the classes you've opened (kept on this PC), and you. A highlight springs to the current item.
function Sidebar({ name, recent, active, onHome, onClass, onMenu, onRemove, onSettings }: { name: string; recent: string[]; active: string
  onHome: () => void; onClass: (display: string) => void; onMenu: () => void; onRemove: (display: string) => void; onSettings: () => void }) {
  const nav = useRef<HTMLElement>(null), [mark, setMark] = useState<{ top: number; height: number } | null>(null)
  useLayoutEffect(() => {
    const item = nav.current?.querySelector<HTMLElement>(`[data-nav="${CSS.escape(active)}"]`)
    setMark(item ? { top: item.offsetTop, height: item.offsetHeight } : null)
  }, [active, recent.join('|')])
  return <aside className="sidebar" aria-label="BYE">
    <div className="sidebar-brand"><span className="swipe">BYE</span></div>
    <button className="sidebar-search" onClick={onMenu}><svg className="glyph" viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7" /><path d="m20 20-3.6-3.6" /></svg>Search<span className="kbd">{shortcut}</span></button>
    <nav ref={nav} className="sidebar-nav" aria-label="Places">
      <span className={`nav-mark${mark ? ' on' : ''}`} aria-hidden="true" style={mark ? { transform: `translateY(${mark.top}px)`, height: mark.height } : undefined} />
      <button className="nav-item" data-nav="home" aria-current={active === 'home' ? 'page' : undefined} onClick={onHome}>Home</button>
      {recent.length > 0 && <p className="nav-label">Your classes</p>}
      {recent.map(display => <div className="nav-row" data-nav={display} key={display}>
        <button className="nav-item mono" aria-current={active === display ? 'page' : undefined} onClick={() => onClass(display)}>{display}</button>
        <button className="nav-remove" aria-label={`Remove ${display} from your classes`} onClick={() => onRemove(display)}>×</button>
      </div>)}
    </nav>
    <span className="spacer" />
    <button className="sidebar-me" onClick={onSettings} aria-label="Your name and settings">
      <span className="avatar ink">{name ? [...name][0].toUpperCase() : '?'}</span><span className="truncate">{name || 'Guest'}</span><span className="muted" aria-hidden="true">⚙</span>
    </button>
  </aside>
}

createRoot(document.getElementById('root')!).render(<App />)
