import { mkdir, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { performance } from 'node:perf_hooks'
import { PCC, RMP } from '../src/main/network'
import { professors, resolve } from '../src/shared/domain'
const pcc = new PCC(), rmp = new RMP(), signal = AbortSignal.timeout(180000)
const terms = await pcc.terms(), term = terms.find(t => /Winter 2027/i.test(t.termName)) ?? terms[0]
if (!term) throw new Error('No published PCC semester.')
const start = performance.now(), rows = await pcc.schedule(term.termCode), c = resolve('math5a', rows), list = professors(rows, c)
const results: any[] = []
for (const professor of list.slice(0, 3)) {
  const started = performance.now()
  try {
    const candidates = await rmp.candidates(professor.name, signal)
    const preview = candidates.length === 1 ? await rmp.page(candidates[0].id, 3, signal) : undefined
    results.push({ name: professor.name, candidates: candidates.map(p => ({ id: p.id, name: p.firstName + ' ' + p.lastName, school: p.school, department: p.department })), previewReviewCount: preview?.profile.reviews.length, seconds: (performance.now() - started) / 1000 })
  } catch (e) { results.push({ name: professor.name, error: e instanceof Error ? e.message : String(e) }) }
}
const report = { date: new Date().toISOString(), term, course: c, sections: list.reduce((n, p) => n + p.sections.length, 0), professors: list.length, elapsedSeconds: (performance.now() - start) / 1000, results }
console.log(JSON.stringify(report, null, 2))
await mkdir(path.resolve(import.meta.dirname, '../test-results'), { recursive: true })
await writeFile(path.resolve(import.meta.dirname, '../test-results/live-verification.json'), JSON.stringify(report, null, 2))
if (!list.length || !results.some(r => r.previewReviewCount !== undefined || r.candidates?.length > 1)) process.exitCode = 1
