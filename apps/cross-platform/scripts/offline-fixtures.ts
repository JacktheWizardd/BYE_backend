import { setTimeout as delay } from 'node:timers/promises'
import type { Engine } from '../src/main/engine'
import type { Profile, Row, Term } from '../src/shared/types'
import { suggestions, sameCourse, course } from '../src/shared/domain'
export const term: Term = { termCode: '202650', termName: 'Summer 2026', termDisplayControl: 'Y' }
export function fixtureServices(saved: Row[]) {
  // Preserve saved schedule fields, substituting fictional instructor identities.
  const rows = saved.slice(0, 3).map(row => ({ ...row, pfaName: row.pfaName === saved[0].pfaName ? 'Alex Example' : 'Blair Sample' }))
  const controls = { ambiguous: false, holdPages: false, scheduleDelay: 0 }
  const calls = { terms: 0, schedule: 0, candidates: 0, pages: 0, aborted: 0 }
  const profiles: Profile[] = ['Alex Example', 'Blair Sample', 'Alex Example'].map((name, i) => ({
    id: String(1001 + i), firstName: name.split(' ')[0], lastName: name.split(' ')[1], school: 'Pasadena City College', schoolID: 2649,
    department: i === 2 ? 'Fictional alternate department' : 'Fictional studies', rating: 4.2 - i / 10, difficulty: 2.5, ratingCount: 30, wouldTakeAgain: 80,
    courseCounts: [{ label: 'ETH014', count: 20 }, { label: 'HIST001', count: 10 }], coverage: {},
    reviews: Array.from({ length: 30 }, (_, n) => ({ id: `fictional-${i}-${n}`, course: n % 3 === 0 ? 'HIST001' : 'ETH014', date: `2026-09-${String(30 - n).padStart(2, '0')}`, rating: n % 5 + 1, difficulty: (n + 2) % 5 + 1, text: `Fictional review ${n + 1}: ${n % 2 ? 'The practice examples helped me understand the material.' : 'The assignments took time and feedback explained the mistakes.'}` }))
  }))
  const pcc: Engine['pcc'] = {
    async terms() { calls.terms++; return [term] },
    async schedule(code) { if (code !== term.termCode) throw new Error('Unexpected fixture semester.'); calls.schedule++; await delay(controls.scheduleDelay); return structuredClone(rows) },
    async suggest(code, query) { return suggestions(query, await this.schedule(code)) }
  }
  const rmp: Engine['rmp'] = {
    async candidates(name, signal) { signal.throwIfAborted(); calls.candidates++; return structuredClone(profiles.filter((p, i) => `${p.firstName} ${p.lastName}` === name && (i !== 2 || controls.ambiguous))).map(p => ({ ...p, reviews: [] })) },
    async page(id, count, signal, cursor, filter) {
      calls.pages++
      try { await delay(controls.holdPages ? 5000 : 15, undefined, { signal }) } catch (error) { calls.aborted++; throw error }
      const source = profiles.find(p => p.id === id); if (!source) throw new Error('Unexpected fixture profile.')
      const reviews = source.reviews.filter(r => !filter || sameCourse(course(filter), r.course)), start = Number(cursor ?? 0), selected = reviews.slice(start, start + count)
      const next = start + selected.length
      return { profile: { ...structuredClone(source), reviews: structuredClone(selected) }, ids: selected.map(r => r.id), hasNextPage: next < reviews.length, nextCursor: next < reviews.length ? String(next) : undefined }
    }
  }
  return { pcc, rmp, controls, calls }
}
