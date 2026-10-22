import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtemp, readFile, rm } from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'
import { setTimeout as delay } from 'node:timers/promises'
import { ScheduleAPI, mapSections, SCHEDULE_URL, type WireSection } from '../src/main/schedule-api'
import { ByeReviewsAPI } from '../src/main/bye-reviews'
import { ReadAPI, ReadError } from '../src/main/read-api'
import { SchedulePoll } from '../src/main/schedule-poll'
import { Engine } from '../src/main/engine'
import { Store } from '../src/main/storage'
import { fixtureServices, term } from '../scripts/offline-fixtures'
import { fits, sameCourse, course, formatLabel } from '../src/shared/domain'
import { openSeatTotal, staleSource } from '../vendor/bye-shared/core/freshness'
import { publicClientKey } from '../src/main/public-key'

const c = {key:'MATH 005AH',subject:'MATH',number:'005AH',title:'CALCULUS HONORS'}
const checked = () => ({stale:false,sourceCheckedAt:new Date().toISOString(),catalogVersion:'catalog-1'})
const meeting = (startDate='2026-10-01',formatCode='LE') => ({startDate,endDate:startDate,days:formatCode === 'OD' ? []:['thu'],beginTime:formatCode === 'OD' ? null:'1300',endTime:formatCode === 'OD' ? null:'1400',formatCode,formatDescription:'Source format',campus:'Main',building:'C',room:'101',sourceFields:{ptrmDesc:'Full term'}})
const section = (): WireSection => ({crn:'12345',courseKey:c.key,units:'1',information:{sectionNote:['<script>inert</script>']},meetings:[meeting(),meeting('2026-10-15'),meeting('2026-10-15','OD')],instructors:[{assignmentId:'a',role:'primary',name:'Alex Example'},{assignmentId:'b',role:'secondary',name:'Blair Sample'}],availability:{statusCode:'X',seatsAvailable:4,capacity:20,waitlistCount:null,waitlistCapacity:5}})
test('Windows build accepts application keys and refuses privileged credentials',()=>{
  const key='bye_pk_'+'a'.repeat(43);assert.equal(publicClientKey(key),key)
  assert.equal(publicClientKey('sb_publishable_fixture'),'sb_publishable_fixture')
  const jwt=(role:string)=>'header.'+Buffer.from(JSON.stringify({role})).toString('base64url')+'.signature'
  assert.equal(publicClientKey(jwt('anon')),jwt('anon'))
  for(const value of ['sb_secret_fixture',jwt('service_role'),'server-token'])assert.throws(()=>publicClientKey(value),/Privileged credentials/)
})
function fixtureAPI() {
  let offline=false, unauthorized=false, notModified=false, active=0, peak=0, calls: {url:URL;headers:Headers}[]=[]
  const request: typeof fetch = async (input,init) => {
    const url=new URL(String(input)),headers=new Headers(init?.headers);calls.push({url,headers})
    assert.ok(url.href.startsWith(SCHEDULE_URL));assert.equal(init?.redirect,'error');assert.equal(init?.credentials,'omit')
    assert.equal(headers.get('apikey'),'fixture-public-key')
    if (offline) throw new TypeError('offline')
    if (unauthorized) return Response.json({error:{code:'UNAUTHORIZED'}},{status:401})
    active++;peak=Math.max(peak,active);await delay(2);active--
    if(notModified && headers.has('If-None-Match'))return new Response(null,{status:304})
    let data: unknown
    if(url.pathname.endsWith('/terms'))data=[{termCode:'202670',name:'Fall 2026'}]
    else if(url.pathname.endsWith('/catalog'))data=[c,{...c,key:'MATH 005AL',number:'005AL',title:'Calculus lab'}]
    else if(url.pathname.endsWith('/sections'))data=[section()]
    else if(url.pathname.endsWith('/manifest'))data={catalogVersion:'catalog-1'}
    else if(url.pathname.endsWith('/availability'))data=url.searchParams.get('crns')!.split(',').map(crn=>({crn,availability:{...section().availability!,seatsAvailable:2}}))
    else throw new Error('Unexpected route')
    return Response.json({data,meta:checked()},{headers:{ETag:'"fixture"'}})
  }
  return {request,calls,setOffline:(b:boolean)=>offline=b,setUnauthorized:(b:boolean)=>unauthorized=b,set304:()=>notModified=true,peak:()=>peak}
}

test('structured API keeps suffixes, source status, co-instructors and every dated meeting',async()=>{
  const f=fixtureAPI(),api=new ScheduleAPI('fixture-public-key',undefined,f.request)
  assert.deepEqual((await api.terms()).map(t=>t.termCode),['202670'])
  const suggestions=await api.suggest('202670','math5ah');assert.equal(suggestions[0].course.number,'005AH')
  const result=await api.search('202670','MATH5AH',false,new AbortController().signal)
  assert.equal(result.professors.length,2)
  for(const p of result.professors){const s=p.sections[0];assert.equal(s.status,'X');assert.equal(s.details?.seatsOpen,4);assert.equal(s.details?.waitlistCount,undefined);assert.equal(s.meetings.length,2);assert.match(s.meetings[1],/2026-10-15/);assert.equal(fits(s,['Thu']),true);assert.equal(fits(s,['Mon']),false)}
  assert.equal(sameCourse(course('MATH 005AH'),'MATH5AH'),true)
  assert.equal(sameCourse(course('MATH 005AH'),'MATH5AL'),false)
  assert.equal(openSeatTotal(result.professors.flatMap(p=>p.sections)),4,'Co-instructors must not double count seats')
  const s=mapSections(c,[{...section(),meetings:[meeting('2026-10-01','OD')]}],checked()).professors[0].sections[0]
  assert.equal(fits(s,['Mon','Tue']),true)
  const unknown=mapSections(c,[{...section(),meetings:[{...meeting(),formatCode:null,days:[]}],availability:null}],{stale:true,sourceCheckedAt:null,catalogVersion:'x'}).professors[0].sections[0]
  assert.equal(formatLabel(unknown),'Format not announced');assert.equal(fits(unknown,['Mon']),false);assert.equal(unknown.details?.seatsOpen,undefined)
  assert.deepEqual(unknown.information,{sectionNote:['<script>inert</script>']})
})

test('conditional reads retain cached bodies and one API request is in flight',async()=>{
  const f=fixtureAPI(),api=new ScheduleAPI('fixture-public-key',undefined,f.request)
  await api.search('202670','MATH5AH',false,new AbortController().signal);f.set304()
  const results=await Promise.all([api.search('202670','MATH5AH',true,new AbortController().signal),api.terms(),api.suggest('202670','math')])
  assert.equal(results[0].course.number,'005AH');assert.equal(f.peak(),1);assert.ok(f.calls.some(c=>c.headers.get('If-None-Match')==='"fixture"'))
})

test('cached schedules fail stale offline and revoked keys do not gain a cached authorization bypass',async t=>{
  const root=await mkdtemp(path.join(os.tmpdir(),'bye-schedule-'));t.after(()=>rm(root,{recursive:true,force:true}))
  const f=fixtureAPI(),file=path.join(root,'schedule.json'),api=new ScheduleAPI('fixture-public-key',file,f.request)
  await api.search('202670','MATH5AH',false,new AbortController().signal)
  f.setOffline(true);const result=await api.search('202670','MATH5AH',false,new AbortController().signal)
  assert.equal(result.offline,true);assert.equal(result.source?.stale,true);assert.equal(result.professors[0].sections[0].details?.seatsOpen,undefined)
  f.setOffline(false);f.setUnauthorized(true)
  await assert.rejects(()=>api.search('202670','MATH5AH',false,new AbortController().signal),(e:any)=>e.code==='UNAUTHORIZED')
  await delay(20);assert.equal((await readFile(file,'utf8')).includes('fixture-public-key'),false)
  const restored=new ScheduleAPI('fixture-public-key',file,async()=>{throw new TypeError('offline')})
  assert.equal((await restored.suggest('202670','math')).length,2)
})

test('availability refresh requests only visible CRNs, and unknown or stale totals stay unknown',async()=>{
  const f=fixtureAPI(),api=new ScheduleAPI('fixture-public-key',undefined,f.request),signal=new AbortController().signal
  const result=await api.search('202670','math5ah',false,signal),next=await api.update('202670',result,['12345'],signal)
  assert.equal(next.professors[0].sections[0].details?.seatsOpen,2)
  assert.equal(f.calls.find(c=>c.url.pathname.endsWith('/availability'))?.url.searchParams.get('crns'),'12345')
  const s=next.professors[0].sections[0],time=s.source!.retrievedAt
  assert.equal(staleSource(s.source,time+899999),false);assert.equal(staleSource(s.source,time+900000),true)
  assert.equal(openSeatTotal([s],time+900000),undefined)
  assert.equal(openSeatTotal([s,{...s,crn:'99999',details:undefined}],time),undefined)
  assert.equal(staleSource({...s.source!,expiresAt:undefined},time+300000),true,'Web keeps its five-minute deadline')
})

test('transport honors rate limits, bounds response bodies, and rejects cancellation before another request',async()=>{
  let count=0
  const api=new ReadAPI('https://fixture.test','',async()=>{count++;return new Response(null,{status:429,headers:{'Retry-After':'120'}})})
  await assert.rejects(()=>api.get('/test',new AbortController().signal),(e:any)=>e instanceof ReadError && e.retryMs>=120000)
  await assert.rejects(()=>api.get('/test',new AbortController().signal));assert.equal(count,1)
  const abort=new AbortController();abort.abort();await assert.rejects(()=>api.get('/test',abort.signal));assert.equal(count,1)
  const huge=new ReadAPI('https://fixture.test','',async()=>new Response('x'.repeat(8*1024*1024+1)))
  await assert.rejects(()=>huge.get('/test',new AbortController().signal))
})

test('public BYE review client strips private fields and keeps authored text inert',async()=>{
  const api=new ByeReviewsAPI(async(input,init)=>{
    const url=new URL(String(input));assert.equal(url.origin,'https://bye-before-you-enroll.pages.dev');assert.equal(init?.credentials,'omit');assert.equal(new Headers(init?.headers).has('apikey'),false)
    return Response.json({data:{reviews:[{id:'review-1',quality:4,difficulty:2,body:'<img src=x onerror=alert(1)>',date:'2026-10-01',courseId:'61',course:'MATH 005AH',author_id:'private'}],nextOffset:null}})
  })
  const page=await api.list('51','61','recent',0,new AbortController().signal)
  assert.equal((page.reviews[0] as any).author_id,undefined);assert.match(page.reviews[0].body!,/<img/)
})
test('empty BYE profiles keep scores unknown, and malformed pagination is rejected',async()=>{
  const api=new ByeReviewsAPI(async input=>Response.json({data:String(input).includes('/profile?') ? {professorId:'51',count:0,quality:null,difficulty:null,courses:[],retrievedAt:new Date().toISOString()} : {reviews:[],nextOffset:999}}))
  assert.equal((await api.profile('51',new AbortController().signal)).quality,null)
  await assert.rejects(()=>api.list('51',undefined,'recent',0,new AbortController().signal))
})
test('BYE identity responses cannot attach a different full name or course',async()=>{
  const request:typeof fetch=async()=>Response.json({data:{match:'matched',professor:{id:'51',first_name:'Someone',last_name:'Else'},course:{id:'61',code:'MATH 005A',title:'Fixture'}}})
  await assert.rejects(()=>new ByeReviewsAPI(request).resolve('Alex Example','MATH 005A',new AbortController().signal))
})

async function engineFixture(t:any){
  const dir=await mkdtemp(path.join(os.tmpdir(),'bye-integrated-'));t.after(()=>rm(dir,{recursive:true,force:true}))
  const services=fixtureServices([]),engine=new Engine(services.pcc,services.rmp,new Store(dir),{cacheIdentity:'disabled',summarize:async()=>{throw new Error('must not run')}},()=>{},undefined,services.bye)
  return {engine,...services}
}
test('BYE begins before automatic RMP and each source survives the other failing',async t=>{
  const f=await engineFixture(t),events:string[]=[]
  const resolve=f.bye.resolve.bind(f.bye),candidates=f.rmp.candidates.bind(f.rmp)
  f.bye.resolve=async(...a)=>{events.push('bye');return resolve(...a)};f.rmp.candidates=async(...a)=>{events.push('rmp');return candidates(...a)}
  await f.engine.search('math5a',term);await f.engine.idle()
  assert.equal(events[0],'bye');assert.ok(events.includes('rmp'));assert.equal(f.engine.state.professors[0].bye?.profile?.count,25)
  f.controls.byeFailure=true;await f.engine.loadBye(f.engine.state.professors[0].id)
  assert.match(f.engine.state.professors[0].bye?.issue??'',/BYE reviews unavailable/);assert.ok(f.engine.state.professors[0].profile)
  f.controls.byeFailure=false;f.controls.candidateFailure=true;await f.engine.search('math5a',term,true);await f.engine.idle()
  assert.ok(f.engine.state.professors.every(p=>p.state==='unavailable'));assert.equal(f.engine.state.professors[0].bye?.reviews.length,20)
})
test('BYE pages are bounded, filter changes replace rows, and ambiguous identities never attach reviews',async t=>{
  const f=await engineFixture(t);await f.engine.search('math5a',term);await f.engine.idle();const p=f.engine.state.professors[0]
  await f.engine.loadBye(p.id,'this','recent',true);assert.equal(p.bye?.reviews.length,25);assert.equal(p.bye?.nextOffset,null)
  await f.engine.loadBye(p.id,'all','highest');assert.equal(p.bye?.reviews.length,20);assert.equal(p.bye?.sort,'highest')
  assert.throws(()=>f.engine.loadBye(p.id,'999','recent'))
  f.controls.byeAmbiguous=true;await f.engine.loadBye(p.id);assert.equal(p.bye?.resolution?.match,'ambiguous');assert.equal(p.bye?.reviews.length,0);assert.equal(p.bye?.profile,undefined)
})
test('schedule refresh preserves reports and surfaces failures without resetting the current course',async t=>{
  const f=await engineFixture(t);await f.engine.search('math5a',term);await f.engine.idle();const p=f.engine.state.professors[0],profile=p.profile,bye=p.bye,operation=f.engine.state.operationId
  await f.engine.refreshSchedule();assert.equal(f.engine.state.professors[0].profile,profile);assert.equal(f.engine.state.professors[0].bye,bye);assert.equal(f.engine.state.operationId,operation)
  f.controls.scheduleFailure=true;await assert.rejects(()=>f.engine.refreshSchedule());assert.match(f.engine.state.scheduleIssue??'',/refresh failed/);assert.equal(f.engine.state.course?.display,'MATH 005A');assert.equal(f.engine.state.refreshing,false)
})
test('schedule updates do not detach RMP jobs that are still retrieving their first profile',async t=>{
  const f=await engineFixture(t),page=f.rmp.page.bind(f.rmp)
  let release!:()=>void;const gate=new Promise<void>(r=>release=r)
  f.rmp.page=async(...args)=>{await gate;return page(...args)}
  const search=f.engine.search('math5a',term)
  for(let n=0;n<100 && !f.engine.state.course;n++)await delay(2)
  assert.equal(f.engine.state.loading,false,'Schedule browsing must not wait for RMP')
  const original=f.engine.state.professors[0]
  await f.engine.refreshSchedule();assert.equal(f.engine.state.professors[0],original)
  release();await search;await f.engine.idle();assert.ok(f.engine.state.professors[0].profile)
})
test('canceled BYE lookups cannot publish into the next course',async t=>{
  const f=await engineFixture(t);f.controls.byeDelay=10000
  await f.engine.search('math5a',term);const old=f.engine.state.professors[0]
  f.controls.byeDelay=0;await f.engine.search('math5b',term);await f.engine.idle();assert.equal(f.engine.state.course?.display,'MATH 005B');assert.equal(old.bye?.resolution,undefined)
})
test('visible polling never overlaps and pauses on hide/offline until reactivated',async()=>{
  let active=0,peak=0,calls=0
  const poll=new SchedulePoll(async signal=>{calls++;active++;peak=Math.max(peak,active);try{await delay(12,undefined,{signal})}finally{active--}},10)
  poll.setActive(true);await delay(65);poll.setActive(false);await delay(20);const at=calls;await delay(30);assert.equal(calls,at);assert.equal(peak,1)
  poll.setActive(true);await delay(20);poll.stop();await delay(20);assert.ok(calls>at)
})
