import type { ByeRatingProfile, ByeResolution, ByeReviewPage } from '../../vendor/bye-shared/core/reviews'
import { ReadAPI, ReadError } from './read-api'
import { normalizedName, course as parseCourse, sameCourse } from '../../vendor/bye-shared/core/domain'

export const REVIEWS_URL = 'https://bye-before-you-enroll.pages.dev/api/reviews/'
export interface ByeReviewProvider {
  resolve(name: string, course: string, signal: AbortSignal): Promise<ByeResolution>
  profile(id: string, signal: AbortSignal): Promise<ByeRatingProfile>
  list(id: string, courseId: string | undefined, sort: string, offset: number, signal: AbortSignal): Promise<ByeReviewPage>
}
export const BYE_SORTS = ['recent','oldest','highest','lowest','difficulty','highestDifficulty']
const id = (v: unknown): v is string => typeof v === 'string' && /^[1-9]\d{0,18}$/.test(v)
const text = (v: unknown): v is string => typeof v === 'string' && v.length <= 10000
const score = (v: unknown) => typeof v === 'number' && Number.isFinite(v) && v >= 1 && v <= 5
const invalid = () => new ReadError('INVALID_RESPONSE','BYE returned an unsupported review response.')
const validCourse = (c: any) => c && id(c.id) && text(c.code) && text(c.title)
export class ByeReviewsAPI implements ByeReviewProvider {
  private api: ReadAPI
  constructor(request: typeof fetch = fetch) { this.api = new ReadAPI(REVIEWS_URL,'',request) }
  async resolve(name: string, course: string, signal: AbortSignal): Promise<ByeResolution> {
    const {body} = await this.api.get('resolve?' + new URLSearchParams({instructor:name,course}),signal), r = body.data
    if (!r || !['matched','missing','ambiguous'].includes(r.match) || (r.professor !== null && (!id(r.professor?.id) || !text(r.professor.first_name) || !text(r.professor.last_name))) || (r.course !== null && !validCourse(r.course)) || (r.match !== 'matched' && r.professor !== null)) throw invalid()
    if (r.professor && normalizedName(r.professor.first_name + ' ' + r.professor.last_name) !== normalizedName(name)) throw invalid()
    if (r.course && !sameCourse(parseCourse(course),r.course.code)) throw invalid()
    return { match:r.match, professor:r.professor ? {id:r.professor.id,first_name:r.professor.first_name,last_name:r.professor.last_name} : null, course:r.course ? {id:r.course.id,code:r.course.code,title:r.course.title} : null }
  }
  async profile(professorId: string, signal: AbortSignal): Promise<ByeRatingProfile> {
    if (!id(professorId)) throw invalid()
    const {body} = await this.api.get('profile?' + new URLSearchParams({professorId}),signal), p = body.data
    if (!p || p.professorId !== professorId || !Number.isSafeInteger(p.count) || p.count < 0 || (p.quality !== null && !score(p.quality)) || (p.difficulty !== null && !score(p.difficulty)) || !text(p.retrievedAt) || !Number.isFinite(Date.parse(p.retrievedAt)) || !Array.isArray(p.courses) || p.courses.length > 10000 || p.courses.some((c: any) => !validCourse(c) || !Number.isSafeInteger(c.count) || c.count < 0)) throw invalid()
    return { professorId, count:p.count, quality:p.quality, difficulty:p.difficulty, retrievedAt:p.retrievedAt, courses:p.courses.map((c: any) => ({id:c.id,code:c.code,title:c.title,count:c.count})) }
  }
  async list(professorId: string, courseId: string | undefined, sort: string, offset: number, signal: AbortSignal): Promise<ByeReviewPage> {
    if (!id(professorId) || (courseId !== undefined && !id(courseId)) || !BYE_SORTS.includes(sort) || !Number.isSafeInteger(offset) || offset < 0 || offset > 100000) throw invalid()
    const params = new URLSearchParams({professorId,sort,offset:String(offset),...(courseId ? {courseId} : {})})
    const {body} = await this.api.get('list?' + params,signal), p = body.data
    if (!p || !Array.isArray(p.reviews) || p.reviews.length > 20 || (p.nextOffset !== null && (p.nextOffset !== offset + 20 || p.reviews.length !== 20))) throw invalid()
    for (const r of p.reviews) if (!r || !text(r.id) || !score(r.quality) || !score(r.difficulty) || (r.body !== null && !text(r.body)) || !text(r.date) || !Number.isFinite(Date.parse(r.date)) || !id(r.courseId) || (courseId && r.courseId !== courseId) || !text(r.course)) throw invalid()
    return { reviews:p.reviews.map((r: any) => ({id:r.id,quality:r.quality,difficulty:r.difficulty,body:r.body,date:r.date,courseId:r.courseId,course:r.course})), nextOffset:p.nextOffset }
  }
}
