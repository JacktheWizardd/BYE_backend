import type { Professor, Snapshot, Weekday } from '../../../shared/types'
import { fits } from '../../../../vendor/bye-shared/core/domain'
import { DayBubbles, EmptyDetail, LoadingRows, ProfessorList, ProfessorRow, Report, Segmented, plural, type ReportState } from '../../../../vendor/bye-shared/ui'
import { AI_SUMMARIES_ENABLED, AI_SUMMARIES_UNAVAILABLE_NOTE } from '../../../shared/features'
import { Chooser, DISCLAIMER, Summary } from './report'
import type { Run } from './types'

const SORTS = [['rating', 'Rating'], ['difficulty', 'Difficulty'], ['reviews', 'Reviews']] as const

// Results: course header, filters and the professor list on the left, the professor page (or the neutral overview) on the right.
// The row, page and overview are the shared screens with the Mac app's extras turned on (see vendor/bye-shared/ui/report.tsx).
export function Results(props: {
  state: Snapshot; title: string; summary: string; filtered: Professor[]; displayed: Professor[]; showAll: boolean; setShowAll: (v: boolean) => void
  days: Weekday[]; setDays: (d: Weekday[]) => void; onlineOnly: boolean; setOnlineOnly: (v: boolean) => void; sort: string; setSort: (s: string) => void
  selected: string; select: (id: string) => void; run: Run
  reportState: (professorId: string) => ReportState | undefined; saveReport: (professorId: string, value: ReportState) => void; refresh: () => void; changeSearch: () => void; stop: () => void; error: string
}) {
  const { state, filtered, displayed, days, onlineOnly, run } = props, course = state.course
  const p = filtered.find(x => x.id === props.selected), chooser = state.professors.find(x => x.choosing)
  const checked = state.professors.filter(x => x.state !== 'pending' && x.state !== 'loading').length
  const sections = filtered.flatMap(x => x.sections), sectionCount = new Set(sections.map(s => s.crn)).size
  // Open seats across the listed sections, when PCC published them.
  const seats = [...new Map(sections.map(s => [s.crn, s])).values()].map(s => s.details?.seatsOpen).filter((n): n is number => n !== undefined)
  return <div className="results">
    <header className="results-top">
      {course && <span className="chip ink">{course.display}</span>}
      <strong className="truncate results-title">{props.title}</strong>
      <span className="muted truncate small">{props.summary}</span>
      <span className="spacer" />
      <button className="pill" disabled={state.loading} onClick={props.refresh}>Refresh</button>
      <button className="pill" onClick={props.changeSearch}>Change search</button>
    </header>
    <div className="panes">
      <aside className="sidebar-list" aria-label="Professor results">
        <div className="list-head"><h2>Professors</h2><span className="muted small">{plural(sectionCount, 'section')} · {plural(filtered.length, 'professor')}</span></div>
        <div className="results-filters">
          <DayBubbles days={days} onChange={props.setDays} disabled={onlineOnly} />
          <button type="button" className="pill online-toggle" aria-pressed={onlineOnly} onClick={() => props.setOnlineOnly(!onlineOnly)}>Online only</button>
        </div>
        <Segmented label="Sort professors" value={props.sort} onChange={props.setSort} options={SORTS} />
        {state.loading && !state.professors.length && <LoadingRows />}
        {state.loading && state.professors.length > 0 && <p className="muted small">Ratings appear as each professor is checked. Pending results are not ranked yet.</p>}
        <ProfessorList list={displayed} selectedId={p?.id} onOpen={x => props.select(x.id)} openOnArrow
          renderRow={(x, selected, open) => <ProfessorRow p={x} selected={selected} onOpen={open} command={run} />} />
        {!props.showAll && filtered.length > 5 && <button className="pill wide" onClick={() => props.setShowAll(true)}>View all {filtered.length} professors</button>}
        {props.showAll && filtered.length > 5 && <div><button className="pill" onClick={() => props.setShowAll(false)}>Show top five</button></div>}
        <p className="muted small">{DISCLAIMER}</p>
      </aside>
      <div className="detail">
        {p && course ? <Report p={p} course={course} matches={s => fits(s, days)} command={run} reviewFilter="select" findMore writeReview reviewPage={[3, 5]}
            checking={state.loading || state.previewPending > 0} initial={props.reportState(p.id)} onChange={value => props.saveReport(p.id, value)}
            summary={AI_SUMMARIES_ENABLED ? <Summary p={p} course={course} run={run} /> : <p className="panel small muted" role="status">{AI_SUMMARIES_UNAVAILABLE_NOTE}</p>} />
          : !filtered.length ? !state.loading && <div className="empty-detail">
            <h2>No matching classes</h2>
            <p className="muted">{days.length ? (onlineOnly ? 'Try changing or clearing your days, or turning off Online only.' : 'Nobody teaches this on all of those days. Try unticking a day.') : onlineOnly ? 'Try turning off Online only.' : state.issue ?? 'PCC may not offer this course in the selected semester.'}</p>
            <div className="row start">{days.length > 0 && <button className="pill primary" onClick={() => props.setDays([])}>Clear days</button>}{onlineOnly && <button className={`pill${days.length ? '' : ' primary'}`} onClick={() => props.setOnlineOnly(false)}>Show all formats</button>}</div>
            <button className="text-link plain" onClick={() => run({ kind: 'source', target: 'pcc' })}>Check PCC’s schedule ↗</button>
          </div>
          : <EmptyDetail professors={filtered.length} sections={sections} openSeats={seats.length ? seats.reduce((a, b) => a + b, 0) : undefined}
              caption={[course?.display, props.title, props.summary].filter(Boolean).join(' · ')}>
            <p className="muted small">Choose a professor on the left to see their sections, ratings and student reviews.</p>
            <p className="muted small">{DISCLAIMER}</p>
          </EmptyDetail>}
      </div>
    </div>
    <footer className="results-foot">
      {state.loading ? <><span className="progress-meter" role="progressbar" aria-label="Progress" aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(state.professors.length ? checked / state.professors.length * 100 : 0)}><i style={{ width: `${Math.max(6, (state.professors.length ? checked / state.professors.length : 0) * 100)}%` }} /></span>
        <span>{state.professors.length ? `Checking ratings · ${checked} of ${state.professors.length}` : 'Finding classes at PCC…'}</span><button className="text-link" onClick={props.stop}>Cancel</button></>
        : p?.detailLoading || p?.summaryLoading ? <><span className="spinner" aria-hidden="true" /><span>Loading this professor’s report…</span><button className="text-link" onClick={props.stop}>Stop loading</button></>
        : <><span className="dot" aria-hidden="true" /><span className="muted">{AI_SUMMARIES_ENABLED ? 'PCC schedule · Rate My Professors · AI summaries run on your PC' : 'PCC schedule · Rate My Professors'}</span></>}
      <span className="spacer" />
      {(props.error || state.issue) && <span className="muted" role="status">{props.error || state.issue}</span>}
    </footer>
    <Chooser p={chooser} run={run} />
  </div>
}
