/** Actual compiled Pages function runs in workerd; outbound Supabase is a fixture. */
import { Miniflare } from 'miniflare'
import { execFileSync } from 'node:child_process'
import { mkdir } from 'node:fs/promises'
import { resolve } from 'node:path'
const frontend=process.argv[2]
if(!frontend)throw new Error('Pass the explicit frontend relocation directory to test its real Pages forwarder.')
import assert from 'node:assert/strict'
import { reviewFixture, TEST_EMAIL, validForm, REVIEW_ID } from '../services/web-api/tests/review-fixtures'
const out=resolve('.wrangler/review-test-build');await mkdir(out,{recursive:true})
execFileSync(process.execPath,['node_modules/wrangler/bin/wrangler.js','deploy','--config','services/web-api/wrangler.jsonc','--dry-run','--outdir',out],{env:{...process.env,WRANGLER_SEND_METRICS:'false',WRANGLER_LOG_PATH:'/private/tmp/bye-review-runtime.log'},stdio:'pipe'})
const pagesOut=resolve('.wrangler/review-pages-test-build');await mkdir(pagesOut,{recursive:true})
execFileSync(process.execPath,[resolve('node_modules/wrangler/bin/wrangler.js'),'pages','functions','build','functions','--outdir',pagesOut],{cwd:resolve(frontend),env:{...process.env,WRANGLER_SEND_METRICS:'false',WRANGLER_LOG_PATH:'/private/tmp/bye-review-pages-build.log'},stdio:'pipe'})
const f=reviewFixture()
const mf=new Miniflare({workers:[
  {name:'pages',modules:true,scriptPath:pagesOut+'/index.js',compatibilityDate:'2025-10-11',serviceBindings:{WEB_API:'reviews'}},
  {name:'pages-disabled',modules:true,scriptPath:pagesOut+'/index.js',compatibilityDate:'2025-10-11',serviceBindings:{WEB_API:'disabled'}},
  {name:'reviews',modules:true,scriptPath:out+'/index.js',compatibilityDate:'2025-10-11',bindings:{...f.env},outboundService:async request=>{try{return await f.outbound(request as Request)}catch(e){console.error('Fixture transport failure',e);throw e}}},
  {name:'disabled',modules:true,scriptPath:out+'/index.js',compatibilityDate:'2025-10-11',bindings:{REVIEWS_ENABLED:'false',LIVE_APP_ENABLED:'false'},outboundService:()=>{throw new Error('Disabled API must not fetch')}},
]})
try {
  const worker=await mf.getWorker('pages'),disabled=await mf.getWorker('pages-disabled')
  const req=(path:string,body?:unknown,cookie?:string)=>worker.fetch('https://fixture.local/api/reviews/'+path,{method:body===undefined?'GET':'POST',headers:{...(body===undefined?{}:{Origin:'https://fixture.local','Content-Type':'application/json'}),...(cookie?{Cookie:cookie}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})})
  assert.equal((await(await disabled.fetch('https://fixture.local/api/reviews/status')).json() as any).data.enabled,false)
  assert.equal((await disabled.fetch('https://fixture.local/api/reviews/dimensions')).status,503)
  const sent=await req('auth/send',{email:TEST_EMAIL})
  assert.equal(sent.status,200,JSON.stringify({response:await sent.json(),calls:f.state.calls}))
  const verification=await req('auth/verify',{email:TEST_EMAIL,code:'123456'})
  assert.equal(verification.status,200)
  const cookie=verification.headers.get('Set-Cookie')!.split(';')[0]
  assert.match(verification.headers.get('Set-Cookie')!,/HttpOnly/)
  assert.match(cookie,/^__Secure-bye-review=/)
  assert.equal(verification.headers.get('Cache-Control'),'no-store')
  const number=await req('number',{},cookie)
  assert.equal(number.status,200);assert.deepEqual((await number.json() as any).data,{number:2,total:1})
  assert.deepEqual((await(await req('number',{},cookie)).json() as any).data,{number:2,total:1})
  const count=await req('numbers');assert.equal(count.status,200)
  assert.deepEqual((await count.json() as any).data,{total:1});assert.equal(count.headers.get('Cache-Control'),'no-store')
  assert.equal((await req('number',{})).status,401)
  assert.equal((await worker.fetch('https://fixture.local/api/reviews/number',{method:'POST',headers:{Cookie:cookie,'Content-Type':'application/json'},body:'{}'})).status,403)
  assert.equal((await worker.fetch('https://fixture.local/api/reviews/number',{method:'POST',headers:{Origin:'https://fixture.local',Cookie:cookie,'Content-Type':'text/plain'},body:'{}'})).status,415)
  f.state.emailRateLimited=true
  const limited=await req('auth/send',{email:TEST_EMAIL});assert.equal(limited.status,429)
  assert.equal(limited.headers.get('Retry-After'),'60');assert.equal(limited.headers.get('Cache-Control'),'no-store')
  f.state.emailRateLimited=false
  assert.equal((await req('courses?q=TEST',undefined,cookie)).status,200)
  assert.equal((await req('professors?q=Alex',undefined,cookie)).status,200)
  assert.equal((await req('dimensions',undefined,cookie)).status,200)
  const resolved=await req('resolve?instructor=Alex%20Fixture&course=TEST1')
  assert.equal(resolved.status,200);assert.equal((await resolved.json() as any).data.professor.id,'1')
  const ratings=await req('profile?professorId=1');assert.equal(ratings.status,200);assert.equal((await ratings.json() as any).data.count,1)
  const list=await req('list?professorId=1&courseId=2');assert.equal(list.status,200);assert.equal((await list.json() as any).data.reviews[0].id,REVIEW_ID)
  assert.equal((await req('selection?professorId=1&courseId=2',undefined,cookie)).status,200)
  assert.equal((await req('report',{reviewId:REVIEW_ID,reason:'Fictional runtime report'},cookie)).status,200);assert.equal(f.state.reportCount,1)
  const saved=await req('submit',validForm,cookie)
  assert.equal(saved.status,200);assert.equal((await saved.json() as any).data.id,REVIEW_ID)
  assert.equal((await req('submit',validForm,cookie)).status,409)
  assert.equal(f.state.saves.length,1)
  assert.equal((await req('auth/signout',{})).status,200)
  assert.equal((await req('submit',validForm)).status,401)
  assert.equal((await worker.fetch('https://fixture.local/api/v1/terms')).status,503,'Source API remains disabled without SOURCES')
  console.log('Compiled Pages forwarder + bound backend review runtime passed: real SDK, cookies, catalogs, public reviews/ratings, verified prefill/reporting, submission, duplicate rejection and source isolation. Fixture only; no real email or DB writes.')
} finally {await mf.dispose()}
