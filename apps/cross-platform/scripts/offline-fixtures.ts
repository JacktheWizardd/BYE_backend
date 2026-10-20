import { setTimeout as delay } from 'node:timers/promises'
import type { Engine } from '../src/main/engine'
import type { Profile, Row, Term } from '../src/shared/types'
import { suggestions, sameCourse, course, resolve, professors } from '../src/shared/domain'
import type { ScheduleProvider } from '../src/main/schedule-api'
import type { ByeReviewProvider } from '../src/main/bye-reviews'
import mathRows from '../tests/fixtures/math-courses.json'
export const term: Term = { termCode: '202650', termName: 'Summer 2026', termDisplayControl: 'Y' }
const otherTerm: Term = { termCode: '202670', termName: 'Fall 2026', termDisplayControl: 'Y' }
export function fixtureServices(saved: Row[]) {
  // Preserve saved schedule fields, substituting fictional instructor identities.
  // Fictional seats and waitlists, so the seat meter shows in offline checks and the test window (one section is full).
  const seats = (i: number) => ({ seatsAvail: [15, 4, 0, 22, 9][i % 5], maxEnrl: 35, waitCount: [0, 2, 6, 0, 1][i % 5], waitCapacity: 10 })
  const rows: Row[] = [...saved.slice(0, 3).map((row, i) => ({ ...row, ...seats(i), pfaName: row.pfaName === saved[0].pfaName ? 'Alex Example' : 'Blair Sample' })), ...mathRows.map((r,i) => ({...r,...seats(i + 3),crn:String(91001+i)}))]
  const controls = { ambiguous: false, holdPages: false, scheduleDelay: 0, scheduleFailure:false, candidateDelay: 0, candidateFailure: false, candidateEmpty: false, suggestDelay: 0, suggestFailure: false, byeFailure:false, byeAmbiguous:false, byeDelay:0 }
  const calls = { terms: 0, schedule: 0, candidates: 0, pages: 0, aborted: 0, suggestions: 0, byeResolve:0, byePages:0 }
  const profiles: Profile[] = ['Alex Example', 'Blair Sample', 'Alex Example'].map((name, i) => ({
    id: String(1001 + i), firstName: name.split(' ')[0], lastName: name.split(' ')[1], school: 'Pasadena City College', schoolID: 2649,
    department: i === 2 ? 'Fictional alternate department' : 'Fictional studies', rating: 4.2 - i / 10, difficulty: 2.5, ratingCount: 30, wouldTakeAgain: 80,
    courseCounts: [{ label: 'ETH014', count: 20 }, { label: 'HIST001', count: 10 }], coverage: {},
    reviews: Array.from({ length: 30 }, (_, n) => ({ id: `fictional-${i}-${n}`, course: n % 3 === 0 ? 'HIST001' : 'ETH014', date: `2026-09-${String(30 - n).padStart(2, '0')}`, rating: n % 5 + 1, difficulty: (n + 2) % 5 + 1, text: `Fictional review ${n + 1}: ${n % 2 ? 'The practice examples helped me understand the material.' : 'The assignments took time and feedback explained the mistakes.'}` }))
  }))
  profiles.push({ ...profiles[1], id: '1004', department: 'Fictional alternate department' })
  profiles.push({ ...profiles[0], id: '1005', firstName: 'Dana', lastName: 'Identity' })
  const pcc = fixtureSchedule({
    async terms() { calls.terms++; return [term, otherTerm] },
    async schedule(code) { if (![term.termCode, otherTerm.termCode].includes(code)) throw new Error('Unexpected fixture semester.'); calls.schedule++; await delay(controls.scheduleDelay); if (controls.scheduleFailure) throw new Error('Fixture schedule refresh failed.'); return structuredClone(code === term.termCode ? rows : rows.filter(r => r.courseNumbDisplay === '005B')) },
    async suggest(code, query) { calls.suggestions++; const wait = controls.suggestDelay, fail = controls.suggestFailure; const rows = await this.schedule(code); await delay(wait); if (fail) throw new Error('Fixture suggestions unavailable.'); return suggestions(query, rows) }
  })
  const rmp: Engine['rmp'] = {
    async candidates(name, signal) { signal.throwIfAborted(); calls.candidates++; await delay(controls.candidateDelay, undefined, { signal }); if (controls.candidateFailure) throw new Error('Fixture profile discovery unavailable.'); if (controls.candidateEmpty) return []; return structuredClone(profiles.filter((p, i) => `${p.firstName} ${p.lastName}` === name && (![2, 3].includes(i) || controls.ambiguous))).map(p => ({ ...p, reviews: [] })) },
    async page(id, count, signal, cursor, filter) {
      calls.pages++
      try { await delay(controls.holdPages ? 5000 : 15, undefined, { signal }) } catch (error) { calls.aborted++; throw error }
      const source = profiles.find(p => p.id === id); if (!source) throw new Error('Unexpected fixture profile.')
      const reviews = source.reviews.filter(r => !filter || sameCourse(course(filter), r.course)), start = Number(cursor ?? 0), selected = reviews.slice(start, start + count)
      const next = start + selected.length
      return { profile: { ...structuredClone(source), firstName: id === '1005' ? 'Wrong' : source.firstName, reviews: structuredClone(selected) }, ids: selected.map(r => r.id), hasNextPage: next < reviews.length, nextCursor: next < reviews.length ? String(next) : undefined }
    }
  }
  const bye: ByeReviewProvider = {
    async resolve(name,label,signal) { calls.byeResolve++; await delay(controls.byeDelay,undefined,{signal}); if (controls.byeFailure) throw new Error('Fixture BYE reviews unavailable.'); return {match:controls.byeAmbiguous ? 'ambiguous':'matched',professor:controls.byeAmbiguous ? null : {id:name === 'Alex Example' ? '51':'52',first_name:name.split(' ')[0],last_name:name.split(' ').slice(1).join(' ')},course:{id:'61',code:label,title:'Fictional course'}} },
    async profile(professorId,signal) { signal.throwIfAborted(); if (controls.byeFailure) throw new Error('Fixture BYE reviews unavailable.'); return {professorId,count:25,quality:4,difficulty:2,courses:[{id:'61',code:'ETH 014',title:'Fictional course',count:25}],retrievedAt:new Date().toISOString()} },
    async list(professorId,courseId,sort,offset,signal) { signal.throwIfAborted(); calls.byePages++; if (controls.byeFailure) throw new Error('Fixture BYE reviews unavailable.'); return {reviews:Array.from({length:Math.min(20,25-offset)},(_,i) => ({id:`bye-${professorId}-${offset+i}`,quality:4,difficulty:2,body:offset+i === 0 ? '<img data-bye-unsafe src=x onerror=alert(1)>':'Fictional BYE student review '+(offset+i),date:'2026-10-01T00:00:00Z',courseId:courseId ?? '61',course:'ETH 014'})),nextOffset:offset+20 < 25 ? offset+20:null} },
  }
  return { pcc, rmp, bye, controls, calls }
}

/** Saved-row adapter exists only in verification; the production engine consumes structured schedules. */
export function fixtureSchedule(source: { terms: () => Promise<Term[]>; schedule: (term: string, refresh?: boolean) => Promise<Row[]>; suggest?: (term: string, query: string) => Promise<import('../src/shared/types').Suggestion[]> }): ScheduleProvider & { schedule: typeof source.schedule } {
  return { ...source,
    async suggest(term,query) { return source.suggest ? source.suggest(term,query) : suggestions(query,await this.schedule(term)) },
    async search(term,query,refresh,signal) { const rows = await this.schedule(term,refresh); signal.throwIfAborted(); const c = resolve(query,rows); return { course:c,professors:professors(rows,c) } },
  }
}
