import type { SupabaseClient } from '@supabase/supabase-js'
import { course, normalizedName, sameCourse } from '@bye/source-domain'
import { ReviewError } from './reviews'
const invalid = () => new ReviewError(400, 'INVALID_INPUT', 'Choose a valid professor, course or review page.')
const unavailable = () => new ReviewError(503, 'BYE_UNAVAILABLE', 'BYE reviews could not be loaded. Try again shortly.')
export function catalogId(value: unknown): string {
  if (typeof value !== 'string' || !/^[1-9]\d{0,18}$/.test(value) || BigInt(value) > 9223372036854775807n) throw invalid()
  return value
}
const safeProfessor = (r: any) => ({ id:String(r.id), first_name:r.first_name, last_name:r.last_name })
const safeCourse = (r: any) => ({ id:String(r.id), code:r.code, title:r.title })
export async function selection(db: SupabaseClient, params: URLSearchParams) {
  const pid=catalogId(params.get('professorId')), cid=catalogId(params.get('courseId'))
  const [p,c]=await Promise.all([db.from('professors').select('id,first_name,last_name').eq('id',pid).maybeSingle(),db.from('courses').select('id,code,title').eq('id',cid).maybeSingle()])
  if(p.error||c.error)throw unavailable()
  if(!p.data||!c.data)throw new ReviewError(404,'CATALOG_NOT_FOUND','This professor or course is no longer available. Choose from the lists.')
  return {professor:safeProfessor(p.data),course:safeCourse(c.data)}
}
export async function resolveCatalog(db: SupabaseClient, params: URLSearchParams) {
  const name=params.get('instructor')??'', label=params.get('course')??''
  if(name.length>160 || !/^[\p{L} .'-]+$/u.test(name) || normalizedName(name).split(' ').length<2)throw invalid()
  let parsed;try{parsed=course(label)}catch{throw invalid()}
  // Narrow on the first full token; only an exact normalized full-name match is accepted.
  // A capped query is treated as ambiguous, never as evidence of uniqueness.
  const first=name.trim().split(/\s+/)[0]
  const [ps,cs]=await Promise.all([
    db.from('professors').select('id,first_name,last_name').ilike('first_name',first+'%').order('id').limit(200),
    db.from('courses').select('id,code,title').like('code',parsed.subject+' %').order('id').limit(1000),
  ])
  if(ps.error||cs.error)throw unavailable()
  const p=(ps.data??[]).filter(r=>normalizedName(r.first_name+' '+r.last_name)===normalizedName(name))
  const c=(cs.data??[]).filter(r=>sameCourse(parsed,r.code))
  const professor=ps.data?.length===200 || p.length!==1 ? null:safeProfessor(p[0])
  const chosenCourse=cs.data?.length===1000 || c.length!==1 ? null:safeCourse(c[0])
  return {professor,course:chosenCourse,match:professor?'matched':p.length>1 || ps.data?.length===200?'ambiguous':'missing'}
}
export async function byeProfile(db: SupabaseClient, params: URLSearchParams) {
  const pid=catalogId(params.get('professorId'))
  // Bounded batches avoid PostgREST's default 1000-row truncation. Never return a partial average.
  let total=0,quality=0,difficulty=0
  const courses=new Map<string,{id:string;code:string;title:string;count:number}>()
  for(let offset=0;offset<=10000;offset+=1000){
    const {data,error}=await db.from('reviews').select('id,quality,difficulty,course_id,courses(code,title)').eq('professor_id',pid).eq('is_hidden',false).order('id').range(offset,offset+999)
    if(error||!data)throw unavailable()
    if(offset===10000 && data.length)throw new ReviewError(503,'AGGREGATION_LIMIT','BYE ratings are temporarily unavailable. Review browsing remains available.')
    for(const r of data){
      total++;quality+=Number(r.quality);difficulty+=Number(r.difficulty)
      const c=r.courses as unknown as {code:string;title:string}|null
      if(c){const id=String(r.course_id),old=courses.get(id);courses.set(id,{id,code:c.code,title:c.title,count:(old?.count??0)+1})}
    }
    if(data.length<1000)break
  }
  return {professorId:pid,count:total,quality:total?quality/total:null,difficulty:total?difficulty/total:null,courses:[...courses.values()].sort((a,b)=>a.code.localeCompare(b.code)),retrievedAt:new Date().toISOString()}
}
export async function byePage(db: SupabaseClient, params: URLSearchParams) {
  const pid=catalogId(params.get('professorId')), cid=params.get('courseId')
  const sort=params.get('sort')??'recent', offsetRaw=params.get('offset')??'0'
  if(!['recent','oldest','highest','lowest','difficulty','highestDifficulty'].includes(sort)||!/^\d{1,6}$/.test(offsetRaw)||Number(offsetRaw)>100000)throw invalid()
  const offset=Number(offsetRaw)
  let q=db.from('reviews').select('id,quality,difficulty,body,created_at,course_id,courses(code,title)').eq('professor_id',pid).eq('is_hidden',false)
  if(cid)q=q.eq('course_id',catalogId(cid))
  if(!['recent','oldest'].includes(sort))q=q.order(['difficulty','highestDifficulty'].includes(sort)?'difficulty':'quality',{ascending:!['highest','highestDifficulty'].includes(sort)})
  const {data,error}=await q.order('created_at',{ascending:sort==='oldest'}).order('id',{ascending:true}).range(offset,offset+20)
  if(error||!data)throw unavailable()
  return {reviews:data.slice(0,20).map(r=>({id:r.id,quality:r.quality,difficulty:r.difficulty,body:r.body,date:r.created_at,courseId:String(r.course_id),course:(r.courses as unknown as {code:string}|null)?.code??''})),nextOffset:data.length>20?offset+20:null}
}
