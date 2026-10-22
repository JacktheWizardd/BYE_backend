import { test } from 'node:test'
import assert from 'node:assert/strict'
import { handleReviewRequest } from '../src/reviews'
import { reviewFixture, REVIEW_ID, jwt } from './review-fixtures'
function fixture(){
  const f=reviewFixture(), calls:{url:URL;method:string;body:any;authorization:string}[]=[]
  let professors=[{id:1,first_name:'Alex',last_name:'Fixture'}],courses=[{id:2,code:'TEST 001',title:'TEST CLASS'}]
  let reviews=Array.from({length:25},(_,i)=>({id:`11111111-1111-4111-8111-${String(i).padStart(12,'0')}`,quality:i%5+1,difficulty:3,body:i===0?'<script>unsafe()</script>':'Comment '+i,created_at:'2026-10-16T00:00:00Z',course_id:2,courses:{code:'TEST 001',title:'TEST CLASS'}}))
  let reportCode='',reported=false,missing=false
  const outbound:typeof fetch=async(input,init)=>{
    const url=new URL(String(input)),method=init?.method??'GET',headers=new Headers(init?.headers),body=init?.body?JSON.parse(String(init.body)):null
    calls.push({url,method,body,authorization:headers.get('Authorization')??''})
    const path=url.pathname.split('/').at(-1),select=url.searchParams.get('select')??''
    if(path==='professors')return Response.json(url.searchParams.has('id')?professors[0]??null:professors)
    if(path==='courses')return Response.json(url.searchParams.has('id')?courses[0]??null:courses)
    if(path==='reviews'){
      assert.equal(url.searchParams.get('is_hidden'),'eq.false')
      assert.ok(!select.includes('author_id'));assert.ok(!select.includes('*'))
      if(select==='id')return Response.json(missing?null:{id:REVIEW_ID})
      const offset=Number(url.searchParams.get('offset')??0),limit=Number(url.searchParams.get('limit')??1000)
      return Response.json(reviews.slice(offset,offset+limit))
    }
    if(path==='reports'){
      if(reportCode)return Response.json({code:reportCode,message:'private upstream error'},{status:409})
      if(reported)return Response.json({code:'23505'},{status:409})
      reported=true;return new Response(null,{status:201})
    }
    return f.outbound(input,init)
  }
  const request=(path:string,body?:unknown,cookie?:string)=>handleReviewRequest(new Request('https://bye.test/api/reviews/'+path,{method:body?'POST':'GET',headers:{...(body?{Origin:'https://bye.test','Content-Type':'application/json'}:{}),...(cookie?{Cookie:cookie}:{})},...(body?{body:JSON.stringify(body)}:{})}),f.env,outbound)
  return {request,calls,f,setProfessors:(v:typeof professors)=>professors=v,setCourses:(v:typeof courses)=>courses=v,setReviews:(v:typeof reviews)=>reviews=v,setCode:(v:string)=>reportCode=v,setMissing:()=>missing=true}
}
test('public resolution accepts only unique normalized names and course equivalence',async()=>{
 const f=fixture(),path='resolve?instructor=Alex%20Fixture&course=TEST1'
 const value=(await(await f.request(path)).json() as any).data
 assert.equal(value.professor.id,'1');assert.equal(value.course.id,'2')
 assert.equal(f.calls.some(c=>c.url.pathname.startsWith('/auth')),false)
 f.setProfessors([{id:1,first_name:'Alex',last_name:'Fixture'},{id:3,first_name:'Alex',last_name:'Fixture'}])
 assert.equal((await(await f.request(path)).json() as any).data.match,'ambiguous')
 f.setProfessors([{id:4,first_name:'Alexander',last_name:'Fixture'}])
 assert.equal((await(await f.request(path)).json() as any).data.professor,null)
 f.setCourses([{id:2,code:'TEST 001',title:'TEST'},{id:3,code:'TEST 1',title:'TEST'}])
 assert.equal((await(await f.request(path)).json() as any).data.course,null)
 for(const bad of ['resolve?instructor=x%2Cfoo&course=TEST1','profile?professorId=0','list?professorId=1&offset=-1','list?professorId=1&sort=author_id'])assert.equal((await f.request(bad)).status,400)
})
test('BYE aggregates only permitted visible data, including all batches and empty results',async()=>{
 const f=fixture()
 let r=await f.request('profile?professorId=1');assert.equal(r.status,200)
 let p=(await r.json() as any).data;assert.equal(p.count,25);assert.equal(p.quality,3);assert.equal(p.difficulty,3);assert.equal(p.courses[0].count,25)
 const base={id:'1',quality:4,difficulty:2,body:'',created_at:'',course_id:2,courses:{code:'TEST 001',title:'TEST'}}
 f.setReviews(Array.from({length:1001},(_,i)=>({...base,id:String(i)})))
 p=(await(await f.request('profile?professorId=1')).json() as any).data;assert.equal(p.count,1001);assert.equal(p.quality,4)
 f.setReviews([]);p=(await(await f.request('profile?professorId=1')).json() as any).data;assert.equal(p.quality,null);assert.equal(p.count,0)
})
test('BYE pages are bounded with deterministic source sorting and explicit course filtering',async()=>{
 const f=fixture();let p=(await(await f.request('list?professorId=1&sort=highest&courseId=2')).json() as any).data
 assert.equal(p.reviews.length,20);assert.equal(p.nextOffset,20);assert.match(p.reviews[0].body,/<script>/)
 const call=f.calls.at(-1)!;assert.equal(call.url.searchParams.get('course_id'),'eq.2');assert.equal(call.url.searchParams.get('limit'),'21');assert.match(call.url.searchParams.get('order')!,/^quality.desc,created_at.desc,id.asc/)
 p=(await(await f.request('list?professorId=1&offset=20')).json() as any).data;assert.equal(p.reviews.length,5);assert.equal(p.nextOffset,null)
})
test('report writes use the verified caller and never accept reporter IDs or read reports',async()=>{
 const f=fixture(),cookie='__Secure-bye-review='+jwt(),body={reviewId:REVIEW_ID,reason:'Test report'}
 assert.equal((await f.request('report',body)).status,401)
 assert.equal((await f.request('report',{...body,reporter_id:'spoof'},cookie)).status,400)
 assert.equal((await f.request('report',{...body,reason:'x'.repeat(501)},cookie)).status,400)
 assert.equal((await f.request('report',body,cookie)).status,200)
 const write=f.calls.find(c=>c.url.pathname.endsWith('/reports'))!;assert.deepEqual(write.body,{review_id:REVIEW_ID,reason:'Test report'});assert.equal(write.method,'POST');assert.match(write.authorization,/^Bearer /)
 assert.equal((await f.request('report',body,cookie)).status,409)
 f.setMissing();assert.equal((await f.request('report',body,cookie)).status,404)
 assert.equal(f.calls.filter(c=>c.url.pathname.endsWith('/reports')&&c.method==='GET').length,0)
})
test('report errors are sanitized, and prefill requires auth and verified catalog IDs',async()=>{
 const f=fixture(),cookie='__Secure-bye-review='+jwt()
 for(const code of ['42501','XX000']){f.setCode(code);const r=await f.request('report',{reviewId:REVIEW_ID,reason:'Test'},cookie);assert.equal(r.status,code==='42501'?409:503);assert.ok(!(await r.text()).includes('private upstream'))}
 assert.equal((await f.request('selection?professorId=1&courseId=2')).status,401)
 const r=await f.request('selection?professorId=1&courseId=2',undefined,cookie);assert.equal(r.status,200);assert.equal((await r.json() as any).data.professor.first_name,'Alex')
})
