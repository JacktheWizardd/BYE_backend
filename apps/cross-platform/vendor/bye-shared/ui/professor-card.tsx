import type { Command, Professor } from '../core/types'
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

/** The Mac app's row (desktop, real data): scores and counts, plus actions under it to choose a profile, retry or check RMP.
 *  Use it as `ProfessorList`'s `renderRow`. Opening the row never chooses a profile; only the student's tap on an action does. */
export function ProfessorRow({ p, selected, onOpen, command }: { p: Professor; selected: boolean; onOpen: () => void; command: (c: Command) => void }) {
  const sections = plural(p.sections.length, 'section'), profile = p.profile
  return <div className={`professor-card${selected ? ' selected' : ''}`}>
    <button className={`prof-card${selected ? ' selected' : ''}`} aria-pressed={selected} onClick={onOpen}>
      <Avatar name={p.name} />
      <span className="prof-main">
        <b className="name">{p.name}</b>
        {profile ? <>
          <small>Difficulty {score(profile.difficulty)} · {profile.wouldTakeAgain === undefined ? 'take-again rate unavailable' : `${Math.round(profile.wouldTakeAgain)}% would take again`}</small>
          <small>{profile.ratingCount === undefined ? 'Rating count unavailable' : plural(profile.ratingCount, 'rating')} · {sections}</small>
          <Bar value={profile.rating} label="Rating" />
        </> : <>
          <small>{p.state === 'choose' ? (p.candidates.length > 1 ? 'Two or more RMP profiles · Choose profile' : 'Profile needs confirmation · Choose profile') : p.state === 'unavailable' ? (unnamed(p) ? "PCC hasn't named an instructor yet" : 'Cannot retrieve RMP info') : p.state === 'loading' ? 'Checking RMP…' : 'Not checked yet'}</small>
          <small>{sections}</small>
        </>}
      </span>
      <span className={`big${profile ? '' : ' muted'}`}>{profile ? <Num value={profile.rating} /> : '—'}</span>
    </button>
    {(p.state === 'choose' || p.state === 'pending' || (p.state === 'unavailable' && !unnamed(p))) && <div className="row-actions">
      {p.state === 'choose' && <button className="text-link" onClick={() => command({ kind: 'discover', professorId: p.id })}>Choose profile</button>}
      {p.state !== 'choose' && <button className="text-link" onClick={() => command({ kind: 'retry', professorId: p.id })}>Try again</button>}
      {p.state === 'unavailable' && <button className="text-link muted" onClick={() => command({ kind: 'source', target: 'rmp', professorId: p.id })}>Check on RMP ↗</button>}
    </div>}
  </div>
}
