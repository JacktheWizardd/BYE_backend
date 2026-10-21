import {test} from 'node:test'
import assert from 'node:assert/strict'
import {ScheduleClient,expired} from '../src/shared/schedule-api'
import {SchedulePCC} from '../src/main/schedule-pcc'
import {Engine} from '../src/main/engine'
import {course,professors} from '../src/shared/domain'
import {Store} from '../src/main/storage'
import type {ScheduleSection} from '../src/shared/schedule-api'
const meta=()=>({term:'202670',catalogVersion:'catalog-1',availabilityVersion:'seats-1',sourceCheckedAt:new Date().toISOString(),stale:false})
function fixture() {
  let version=meta(), requests:string[]=[]
  const courses=[{key:'MATH 005AH',subject:'MATH',number:'005AH',title:'Sample calculus'},{key:'ENGL C1000H',subject:'ENGL',number:'C1000H',title:'Sample writing'}]
  const sections:ScheduleSection[]=courses.map((c,i)=>({crn:String(80000+i),courseKey:c.key,units:'4',information:{},meetings:[{startDate:'2026-08-24',endDate:'2026-12-13',beginTime:null,endTime:null,days:[],formatCode:'OD',formatDescription:null,campus:null,building:'Online ASYNCH',room:null,sourceFields:{}}],instructors:[{name:'Taylor Example',assignmentId:'assignment-'+i,role:'primary'},{name:'Casey Sample',assignmentId:'secondary-'+i,role:'secondary'}],availability:{statusCode:'X',capacity:30,enrolled:20,seatsAvailable:10,waitlistCount:2,waitlistCapacity:5,waitlistAvailable:3}}))
  const client=new ScheduleClient('https://fixture.invalid','fixture-key',async(input)=>{
    const url=new URL(String(input));requests.push(url.pathname);await new Promise(r=>setTimeout(r,1))
    let data:unknown
    if(url.pathname.endsWith('/catalog'))data=courses
    else if(url.pathname.endsWith('/manifest'))data=version
    else if(url.pathname.endsWith('/sections'))data=sections.filter(s=>s.courseKey===decodeURIComponent(url.pathname.split('/').at(-2)!))
    else if(url.pathname.endsWith('/availability'))data=sections.filter(s=>url.searchParams.get('crns')?.split(',').includes(s.crn)).map(s=>({crn:s.crn,availability:s.availability}))
    else data=[{termCode:'202670',name:'Fall sample'}]
    return Response.json({data,meta:version})
  })
  return {client,pcc:new SchedulePCC(client),requests,sections,setMeta:(value:typeof version)=>{version=value},getMeta:()=>version}
}
test('concurrent courses, full suffixes and co-instructors remain isolated',async()=>{
  const f=fixture(),signal=AbortSignal.timeout(5000)
  const [a,b]=await Promise.all([f.pcc.courseSections('202670','math5ah',signal),f.pcc.courseSections('202670','ENGL C1000H',signal)])
  assert(a.rows.every(r=>r.courseNumbDisplay==='005AH'));assert(b.rows.every(r=>r.courseNumbDisplay==='C1000H'))
  assert.deepEqual(new Set(a.rows.map(r=>r.pfaName)),new Set(['Taylor Example','Casey Sample']))
  assert.equal(a.rows[0].fwSectOpenInd,'X');assert.equal(f.requests.filter(p=>p.endsWith('/catalog')).length,1)
  assert((await f.pcc.suggest('202670','math5ah')).length)
})
test('seat changes fetch only displayed CRNs and never re-fetch sections',async()=>{
  const f=fixture(),signal=AbortSignal.timeout(5000);await f.pcc.courseSections('202670','math5ah',signal)
  f.sections[0].availability!.seatsAvailable=4;f.setMeta({...f.getMeta(),availabilityVersion:'seats-2'})
  const result=await f.pcc.courseSections('202670','math5ah',signal)
  assert.equal(result.rows[0].seatsAvail,4);assert.equal(f.requests.filter(p=>p.endsWith('/sections')).length,1);assert.equal(f.requests.filter(p=>p.endsWith('/availability')).length,1)
})
test('stale counts expire locally; cancelled subscribers do not cancel another reader',async()=>{
  const f=fixture(),cancel=new AbortController(),alive=AbortSignal.timeout(5000)
  const abandoned=f.client.catalog('202670',cancel.signal);const retained=f.client.catalog('202670',alive);cancel.abort();await assert.rejects(abandoned);assert.equal((await retained).data.length,2)
  const old={...meta(),sourceCheckedAt:new Date(Date.now()-900_001).toISOString()};assert(expired(old));f.setMeta(old)
  const result=await f.pcc.courseSections('202670','math5ah',alive);assert.equal(result.rows[0].seatsAvail,null);assert.equal(result.rows[0].waitCount,null)
})
test('redirects, rate limits and revoked keys fail closed without leaking upstream text',async()=>{
  for(const status of [302,401,429]) {
    const client=new ScheduleClient('https://fixture.invalid','key',async()=>new Response('private upstream SQL',{status,headers:{'Retry-After':'60'}}))
    await assert.rejects(client.terms(AbortSignal.timeout(5000)),error=>error instanceof Error&&!error.message.includes('private'))
  }
})

test('background updates preserve the chosen profile and operation; changed assignments do not inherit evidence',async()=>{
  const f=fixture(),signal=AbortSignal.timeout(5000),c=course('MATH 005AH');
  const initial=await f.pcc.courseSections('202670',c.display,signal);
  const engine=new Engine(f.pcc,{candidates:async()=>[],page:async()=>{throw new Error('Unexpected RMP traffic')}},{} as Store,{} as never,()=>{});
  const list=professors(initial.rows,c),selected=list.find(p=>p.name==='Taylor Example')!;
  selected.profile={id:'123',firstName:'Taylor',lastName:'Example',school:'Pasadena City College',schoolID:2649,department:'',reviews:[],courseCounts:[],coverage:{}};selected.state='ready';
  engine.state={operationId:'keep-this-search',course:c,term:{termCode:'202670',termName:'Fall sample',termDisplayControl:'Y'},professors:list,loading:false,previewPending:0,scheduleSource:initial.meta};
  f.sections[0].availability!.seatsAvailable=2;f.setMeta({...f.getMeta(),availabilityVersion:'seats-2'});await engine.refreshSchedule();
  assert.equal(engine.state.operationId,'keep-this-search');assert.equal(engine.state.professors.find(p=>p.id===selected.id),selected);assert.equal(selected.profile.id,'123');assert.equal(selected.sections[0].details?.seatsOpen,2);
  f.sections[0].instructors[0].name='Jordan Example';f.setMeta({...f.getMeta(),catalogVersion:'catalog-2'});await engine.refreshSchedule();
  assert(!engine.state.professors.some(p=>p.name==='Taylor Example'));assert.equal(engine.state.professors.find(p=>p.name==='Jordan Example')?.profile,undefined);
  const count=f.requests.length;engine.state.scheduleSource={...f.getMeta(),sourceCheckedAt:new Date(Date.now()-900_001).toISOString()};engine.expireAvailability();
  assert(engine.state.professors.every(p=>p.sections.every(s=>s.details?.seatsOpen===undefined&&s.details?.waitlistCount===undefined)));assert.equal(f.requests.length,count);
});
