import type { Course, Point, Review, Summary } from '../shared/types'
import { orderReviews, sameCourse } from '../shared/domain'
export function selectEvidence(reviews: Review[], c: Course) {
  const ordered = orderReviews(reviews), exact = ordered.filter(r => sameCourse(c, r.course))
  return (exact.length >= 2 ? exact : [...exact, ...ordered.filter(r => !sameCourse(c, r.course))]).slice(0, 50)
}
const variants: Record<string, string> = { exams: 'exam', tests: 'exam', test: 'exam', hw: 'homework', lectures: 'lecture', explanations: 'explanation', explains: 'explanation', explaining: 'explanation', clearly: 'clear', clarity: 'clear', heavily: 'heavy', grades: 'grade', grading: 'grade', weighted: 'weight', weights: 'weight', weighting: 'weight', caring: 'care', cares: 'care', never: 'not', no: 'not' }
const words = (text: string) => text.toLowerCase().replace(/’/g, "'").replace(/n't/g, ' not').split(/[^\p{L}\p{N}]+/u).filter(Boolean).map(w => variants[w] ?? w)
const stop = new Set('a an the this that these those it its is are was were be been being of to for in on at by from with as and or but she he they i me my we our their professor teacher instructor student students reported report reports very really'.split(' '))
const bad = new Set('heavy difficult excessive unclear confusing unfair biased bias strict hard expensive costly unhelpful poor bad inconsistent late stressful challenging high'.split(' '))
const good = new Set('clear helpful fair kind good great engaging organized responsive easy'.split(' '))
export function corroborated(point: Point, reviews: Review[], concern: boolean): boolean {
  const anchors = new Set(words(point.text).filter(w => !stop.has(w))), negated = anchors.has('not')
  if (anchors.size < 2 || new Set(point.reviewIDs).size !== 2) return false
  const unfavorable = [...anchors].some(w => bad.has(w))
  if (concern && (!unfavorable || negated)) return false
  if (!concern && unfavorable && !negated) return false
  if (!concern && negated && [...anchors].some(w => good.has(w))) return false
  const sources = reviews.filter(r => point.reviewIDs.includes(r.id)); if (sources.length !== 2) return false
  return sources.every(r => {
    const tokens = words(r.text), set = new Set(tokens)
    return [...anchors].every(w => set.has(w)) && (negated || !tokens.some((w, i) => anchors.has(w) && tokens.slice(Math.max(0, i - 3), i).includes('not')))
  })
}
export function validatePoint(raw: unknown, reviews: Review[], concern: boolean): Point | undefined {
  const p = raw as Point
  if (!p || typeof p.text !== 'string' || !Array.isArray(p.reviewIDs) || p.reviewIDs.length !== 2 || p.reviewIDs.some(id => typeof id !== 'string') || p.text.length > 96 || !p.text.trim() || p.text.trim().split(/\s+/).length > 14) return undefined
  const point = { text: p.text.trim(), reviewIDs: p.reviewIDs }
  if (corroborated(point, reviews, concern)) return point
  const tokens = point.text.split(/\s+/), unfinished = new Set('and or but with of to for the a an not no never'.split(' '))
  for (let count = tokens.length - 1; count >= 2; count--) {
    if (unfinished.has(tokens[count - 1].toLowerCase().replace(/\W/g, ''))) continue
    const candidate = { ...point, text: tokens.slice(0, count).join(' ') }
    if (corroborated(candidate, reviews, concern)) return candidate
  }
  return undefined
}
export function buildSummary(raw: any, evidence: Review[], c: Course, providerIdentity: string): Summary {
  if (!Array.isArray(raw?.positives) || !Array.isArray(raw?.concerns)) throw new Error('Local AI returned an incomplete summary. Retry summary.')
  const positives = raw.positives.map((p: unknown) => validatePoint(p, evidence, false)).filter(Boolean).slice(0, 1) as Point[]
  // The model can put a supported unfavorable observation in the favorable list.
  // Recover it only when BOTH original reviews pass the stricter concern gate.
  const concerns = [...raw.concerns, ...raw.positives].map((p: unknown) => validatePoint(p, evidence, true)).filter(Boolean).slice(0, 1) as Point[]
  const overview = [positives[0] && 'Common positive: ' + positives[0].text, concerns[0] && 'Common concern: ' + concerns[0].text].filter(Boolean).join('\n') || 'Local AI could not verify a recurring theme in this sample.'
  return { positives, concerns, overview, evidence, analyzedCount: evidence.length, exactCourseCount: evidence.filter(r => sameCourse(c, r.course)).length, generatedAt: Date.now(), providerIdentity }
}
