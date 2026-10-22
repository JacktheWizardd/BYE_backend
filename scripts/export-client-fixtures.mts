/** Intentional fictional response export, never a runtime checkout dependency. */
import { writeFile } from 'node:fs/promises'
import { setup } from '../services/web-api/tests/fixtures'
import { FALL } from '../services/web-api/tests/source-data'
const output = process.argv[2]
if (!output) throw new Error('Pass an explicit test JSON destination')
const { service } = setup(), responses: Record<string, unknown> = {}
const key = (kind: string, p: URLSearchParams) => JSON.stringify([kind, (p.get('course') ?? p.get('query') ?? '').toUpperCase(), p.get('instructor') ?? '', p.get('id') ?? '', p.get('filter') ?? '', p.get('cursor') ?? ''])
async function record(kind: string, values: Record<string, string>) {
 const p = new URLSearchParams({ term: FALL.termCode, ...values })
 const result = await service.operation(kind as any, p, 'fixture-export-' + (values.instructor ?? kind))
 responses[key(kind,p)] = result; return result.data as any
}
await record('terms', {})
for (const query of ['MATH5A', 'ETH014']) {
 const sections = await record('sections', { query })
 for (const professor of sections.professors.filter((p: any) => !p.name.includes('announced'))) {
  const candidates = await record('candidates', { course: query, instructor: professor.name })
  for (const candidate of candidates) {
   await record('profile', { course: query, instructor: professor.name, id: candidate.id })
   for (const filter of ['', ...candidate.courseCounts.map((c: any) => c.label)])
    for (const cursor of ['', '3', '20', '40']) {
     const p = new URLSearchParams({ term: FALL.termCode, course: query, instructor: professor.name, id: candidate.id, ...(filter ? { filter } : {}), ...(cursor ? { cursor } : {}) })
     responses[key('reviews', p)] = await service.operation('reviews', p, 'fixture-export-' + candidate.id)
    }
  }
 }
}
await writeFile(output, JSON.stringify(responses, null, 2) + '\n')
console.log('Exported fictional HTTP response snapshots only.')
