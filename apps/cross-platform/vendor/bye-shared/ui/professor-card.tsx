import type { Professor } from '../core/types'
import { formatLabel } from '../core/domain'
import { useSurface } from './context'
import { plural, score, unnamed } from './format'
import { Avatar, Bar, Num } from './primitives'

export function ProfessorCard({ p, selected, onOpen }: { p: Professor; selected: boolean; onOpen: () => void }) {
  const { demo } = useSurface()
  const formats = [...new Set(p.sections.map(formatLabel))].join(', ')
  const where = `${plural(p.sections.length, 'section')} · ${formats}`
  const className = `prof-card${selected ? ' selected' : ''}${unnamed(p) ? ' dashed' : ''}`
  if (p.profile) return <button className={className} aria-pressed={selected} onClick={onOpen}>
    <Avatar name={p.name} /><span className="prof-main"><b className="name">{p.name}</b>
    <small>{demo ? 'Sample · ' : 'RMP · '}Difficulty {score(p.profile.difficulty)}{p.profile.wouldTakeAgain === undefined ? '' : ` · ${Math.round(p.profile.wouldTakeAgain)}% would take again`}</small>
    <small>{where}</small>
    <Bar value={p.profile.rating} label="Rating" /></span><span className="big"><Num value={p.profile.rating} /></span>
  </button>
  if (p.state === 'choose') return <button className={className} aria-pressed={selected} onClick={onOpen}>
    <Avatar name={p.name} /><span className="prof-main"><b className="name">{p.name}</b>
    <small className="ink">{p.candidates.length > 1 ? `${p.candidates.length} RMP profiles match` : 'Choose an RMP profile'}</small><small>{where}</small></span><span className="side-action">Choose →</span>
  </button>
  if (p.state === 'unavailable') return <button className={className} aria-pressed={selected} onClick={onOpen}>
    <Avatar name={p.name} /><span className="prof-main"><b className="name">{p.name}</b>
    <small>{unnamed(p) ? "PCC hasn't named an instructor yet" : <><span className="signal">{p.issue?.includes('access is pending') ? 'RMP access pending.' : 'Cannot retrieve RMP info.'}</span> {demo ? 'Tap to view sections.' : 'Open sections and BYE reviews.'}</>}</small><small>{where}</small></span>{!unnamed(p) && <span className="big muted">—</span>}
  </button>
  return <button className={className} aria-pressed={selected} aria-busy="true" onClick={onOpen}>
    <Avatar name={p.name} /><span className="prof-main"><b className="name">{p.name}</b><small>Checking RMP…</small><small>{where}</small></span><span className="big muted">—</span>
  </button>
}
