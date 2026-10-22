import { test } from 'node:test'
import assert from 'node:assert/strict'
import { courseSearchPattern, handleReviewRequest, mergeCourseRows, validateReview } from '../src/reviews'
import { REVIEW_COMMENT_LIMIT } from '@bye/contracts/reviews'
import { reviewFixture, TEST_EMAIL, validForm, REVIEW_ID, jwt } from './review-fixtures'
const sessionCookie=()=>`__Secure-bye-review=${jwt()}`
test('review feature fails closed without complete owner/public-key config',async()=>{
  for(const changes of [{REVIEWS_ENABLED:'false'},{REVIEW_TEST_EMAIL:''},{REVIEW_TEST_EMAIL:'tester@example.com'},{SUPABASE_URL:'https://evil.test'},{SUPABASE_PUBLISHABLE_KEY:'sb_secret_private'},{SUPABASE_PUBLISHABLE_KEY:'x.'+btoa(JSON.stringify({role:'service_role'}))+'.x'}]) {
    const f=reviewFixture();Object.assign(f.env,changes)
    assert.equal((await(await f.request('status')).json() as any).data.enabled,false)
    assert.equal((await f.request('auth/send',{email:TEST_EMAIL})).status,503)
    assert.equal(f.state.calls.length,0)
  }
})
test('mutations require same-origin JSON and reject large bodies before auth send',async()=>{
  const f=reviewFixture()
  assert.equal((await f.request('auth/send',{email:TEST_EMAIL},undefined,'https://evil.test')).status,403)
  for(const origin of [undefined,'null']) {
    const request=new Request('https://bye.test/api/reviews/auth/send',{method:'POST',headers:{'Content-Type':'application/json',...(origin?{Origin:origin}:{})},body:JSON.stringify({email:TEST_EMAIL})})
    assert.equal((await handleReviewRequest(request,f.env,f.outbound)).status,403)
  }
  const wrong=new Request('https://bye.test/api/reviews/auth/send',{method:'POST',headers:{Origin:'https://bye.test','Content-Type':'text/plain'},body:'{}'})
  assert.equal((await handleReviewRequest(wrong,f.env,f.outbound)).status,415)
  const large=new Request('https://bye.test/api/reviews/auth/send',{method:'POST',headers:{Origin:'https://bye.test','Content-Type':'application/json'},body:JSON.stringify({email:TEST_EMAIL,padding:'x'.repeat(17000)})})
  assert.equal((await handleReviewRequest(large,f.env,f.outbound)).status,413)
  assert.equal(f.state.calls.length,0)
})
test('email sending normalizes owner address and blocks other addresses before contacting Supabase',async()=>{
  const f=reviewFixture()
  for(const email of ['tester@example.com','other@go.pasadena.edu','tester@go.pasadena.edu.evil.test'])assert.equal((await f.request('auth/send',{email})).status,403)
  assert.equal(f.state.otpRequests,0)
  const result=await f.request('auth/send',{email:'  TESTER@GO.PASADENA.EDU '})
  assert.equal(result.status,200);assert.equal(f.state.otpRequests,1)
  assert.equal(result.headers.get('Cache-Control'),'no-store')
  f.state.emailRateLimited=true
  const limited=await f.request('auth/send',{email:TEST_EMAIL})
  assert.equal(limited.status,429);assert.equal(limited.headers.get('Retry-After'),'60')
})
test('only a verified code sets a short-lived HttpOnly cookie and no token enters JSON',async()=>{
  const f=reviewFixture()
  assert.equal((await f.request('auth/verify',{email:TEST_EMAIL,code:'000000'})).status,400)
  const result=await f.request('auth/verify',{email:TEST_EMAIL,code:'123456'})
  assert.equal(result.status,200)
  assert.match(result.headers.get('Set-Cookie')!,/__Secure-bye-review=.*; Path=\/api\/reviews\/; HttpOnly; SameSite=Strict; Secure; Max-Age=\d+/)
  const text=await result.text();assert.ok(!text.includes('refresh'));assert.ok(!text.includes('access_token'));assert.ok(!text.includes('fixture_signature'))
  for(const failure of ['unconfirmed','nonPcc'] as const) { f.state[failure]=true;const rejected=await f.request('auth/verify',{email:TEST_EMAIL,code:'123456'});assert.equal(rejected.status,401);assert.equal(rejected.headers.get('Set-Cookie'),null);f.state[failure]=false }
})
test('session is checked against Supabase and signout clears only this browser cookie',async()=>{
  const f=reviewFixture()
  assert.deepEqual((await(await f.request('session')).json() as any).data,{signedIn:false})
  assert.equal((await f.request('dimensions')).status,401)
  assert.equal((await f.request('session',undefined,sessionCookie())).status,200)
  f.state.authExpired=true
  assert.equal((await f.request('submit',validForm,sessionCookie())).status,401)
  const signout=await f.request('auth/signout',{})
  assert.match(signout.headers.get('Set-Cookie')!,/Max-Age=0/)
  assert.equal(f.state.saves.length,0)
})
test('catalog searches stay bounded, request permitted columns, and reject query injection',async()=>{
  const f=reviewFixture(),cookie=sessionCookie()
  assert.equal((await f.request('dimensions',undefined,cookie)).status,200)
  assert.equal((await f.request('courses?q=TEST',undefined,cookie)).status,200)
  assert.equal((await f.request('professors?q=Alex%20Fixture',undefined,cookie)).status,200)
  const courseCall=f.state.calls.find(x=>x.url.includes('/rest/v1/courses'))!
  assert.equal(new URL(courseCall.url).searchParams.get('limit'),'20')
  assert.equal(new URL(courseCall.url).searchParams.get('select'),'id,code,title')
  const professorCall=f.state.calls.find(x=>x.url.includes('/rest/v1/professors'))!
  assert.equal(new URL(professorCall.url).searchParams.getAll('or').length,2)
  assert.equal((await f.request('courses?q=a',undefined,cookie)).status,400)
  assert.equal((await f.request('professors?q=x%2Cy%28',undefined,cookie)).status,400)
})
test('submission forwards only validated fields under caller JWT and keeps neutral answers',async()=>{
  const f=reviewFixture(), cookie=sessionCookie()
  const result=await f.request('submit',validForm,cookie)
  assert.equal(result.status,200);assert.equal((await result.json() as any).data.id,REVIEW_ID)
  assert.equal(f.state.saves.length,1)
  assert.deepEqual(f.state.saves[0].p_answers,{grading:1,clarity:0})
  assert.equal(f.state.saves[0].p_body,f.prefix+validForm.body)
  assert.equal(f.state.saves[0].p_author_id,undefined)
  assert.equal(f.state.calls.find(x=>x.url.includes('/rpc/'))!.authorization,'Bearer '+cookie.split('=')[1])
  assert.equal((await f.request('submit',validForm,cookie)).status,409)
  assert.equal(f.state.saves.length,1)
})
test('ratings, selected IDs, optional answers, lengths and author spoofing validate before RPC',()=>{
  for(const overrides of [{author_id:'spoof'},{quality:0},{difficulty:6},{quality:1.5},{quality:'5'},{professorId:'1 OR 1=1'},{courseId:'0'},{answers:{grading:2}},{answers:{grading:null}},{answers:[]},{body:'x'.repeat(REVIEW_COMMENT_LIMIT+1)}])assert.throws(()=>validateReview({...validForm,...overrides}))
  assert.deepEqual(validateReview({...validForm,answers:{},body:''}).answers,{})
})
test('uncertain saves do not retry, expose upstream errors, or leak credentials',async()=>{
  const f=reviewFixture();f.state.saveFails=true
  const result=await f.request('submit',validForm,sessionCookie())
  assert.equal(result.status,503)
  const body=await result.text();assert.match(body,/SAVE_UNCONFIRMED/);assert.ok(!body.includes('fixture failure'));assert.ok(!body.includes('fixture_signature'))
  assert.equal(f.state.calls.filter(x=>x.url.includes('/rpc/')).length,1)
})
test('unknown paths and methods do not reach Supabase',async()=>{
  const f=reviewFixture()
  assert.equal((await f.request('unknown')).status,404)
  assert.equal((await f.request('submit')).status,405)
  assert.equal(f.state.calls.length,0)
})


test('transport rejects redirects without following them and insecure deployed origins fail closed',async()=>{
  const f=reviewFixture();let calls=0
  const redirected:typeof fetch=async (_url,init)=>{calls++;assert.equal(init?.redirect,'manual');return new Response(null,{status:302,headers:{Location:'https://untrusted.test'}})}
  const request=new Request('https://bye.test/api/reviews/auth/send',{method:'POST',headers:{Origin:'https://bye.test','Content-Type':'application/json'},body:JSON.stringify({email:TEST_EMAIL})})
  const response=await handleReviewRequest(request,f.env,redirected)
  assert.equal(response.status,503);assert.equal(calls,1)
  const insecure=new Request('http://public.test/api/reviews/status')
  assert.equal((await handleReviewRequest(insecure,f.env,f.outbound)).status,400)
})
test('students mode accepts any confirmed PCC address and saves without the test label',async()=>{
  const f=reviewFixture();f.env.REVIEW_ACCESS='students';f.env.REVIEW_TEST_EMAIL=''
  const status=(await(await f.request('status')).json() as any).data
  assert.equal(status.enabled,true);assert.equal(status.ownerTest,false)
  for(const email of ['tester@example.com','other@go.pasadena.edu.evil.test'])assert.equal((await f.request('auth/send',{email})).status,403)
  assert.equal((await f.request('auth/send',{email:'other@go.pasadena.edu'})).status,200)
  assert.equal(f.state.otpRequests,1)
  const session=(await(await f.request('session',undefined,sessionCookie())).json() as any).data
  assert.deepEqual(session,{signedIn:true,email:TEST_EMAIL})
  assert.equal((await f.request('submit',validForm,sessionCookie())).status,200)
  assert.equal(f.state.saves[0].p_body,validForm.body)
  f.state.nonPcc=true
  assert.equal((await f.request('session',undefined,sessionCookie())).status,401)
})
test('owner mode still reports a private test and keeps the test label',async()=>{
  const f=reviewFixture()
  assert.equal((await(await f.request('status')).json() as any).data.ownerTest,true)
  assert.equal((await f.request('submit',validForm,sessionCookie())).status,200)
  assert.ok(String(f.state.saves[0].p_body).startsWith(f.prefix))
})
test('per-address limits stop repeated code requests before Supabase',async()=>{
  const f=reviewFixture();f.env.REVIEW_ACCESS='students'
  let n=0
  const send=(ip:string)=>handleReviewRequest(new Request('https://bye.test/api/reviews/auth/send',{method:'POST',headers:{Origin:'https://bye.test','Content-Type':'application/json','CF-Connecting-IP':ip},body:JSON.stringify({email:`ip-limit-${n++}@go.pasadena.edu`})}),f.env,f.outbound)
  for(let i=0;i<5;i++)assert.equal((await send('203.0.113.9')).status,200)
  const limited=await send('203.0.113.9')
  assert.equal(limited.status,429);assert.ok(Number(limited.headers.get('Retry-After'))>0)
  assert.equal(f.state.otpRequests,5)
  assert.equal((await send('203.0.113.10')).status,200)
})
test('per-email limits hold when an attacker rotates IP addresses',async()=>{
  const f=reviewFixture();f.env.REVIEW_ACCESS='students'
  const call=(route:string,body:object,i:number)=>handleReviewRequest(new Request('https://bye.test/api/reviews/'+route,{method:'POST',headers:{Origin:'https://bye.test','Content-Type':'application/json','CF-Connecting-IP':'198.51.100.'+i},body:JSON.stringify(body)}),f.env,f.outbound)
  const sends=[];for(let i=0;i<6;i++)sends.push((await call('auth/send',{email:'flooded@go.pasadena.edu'},i)).status)
  assert.deepEqual(sends,[200,200,200,200,429,429]);assert.equal(f.state.otpRequests,4)
  const guesses=[];for(let i=0;i<12;i++)guesses.push((await call('auth/verify',{email:'guessed@go.pasadena.edu',code:String(200000+i)},50+i)).status)
  assert.deepEqual(guesses,[...Array(10).fill(400),429,429])
  // Another student is unaffected.
  assert.equal((await call('auth/send',{email:'someone-else@go.pasadena.edu'},99)).status,200)
})
test('plus-tagged school addresses are rejected so one inbox cannot act as many students',async()=>{
  const f=reviewFixture();f.env.REVIEW_ACCESS='students'
  for(const email of ['jdoe+1@go.pasadena.edu','JDOE+reviews@GO.PASADENA.EDU','+@go.pasadena.edu']){
    const r=await f.request('auth/send',{email});assert.equal(r.status,403);assert.equal((await r.json() as any).error.code,'PCC_EMAIL_ALIAS')
  }
  assert.equal(f.state.otpRequests,0)
  // An existing session for a plus address no longer counts as a student.
  const s=reviewFixture();s.env.REVIEW_ACCESS='students'
  const plus=async(input:any,init?:any)=>{const r=await s.outbound(input,init);const u=new URL(typeof input==='string'?input:input.url);if(u.pathname==='/auth/v1/user')return Response.json({...(await r.json() as object),email:'jdoe+2@go.pasadena.edu'});return r}
  const r=await handleReviewRequest(new Request('https://bye.test/api/reviews/submit',{method:'POST',headers:{Origin:'https://bye.test','Content-Type':'application/json',Cookie:sessionCookie()},body:JSON.stringify(validForm)}),s.env,plus)
  assert.equal(r.status,401);assert.equal(s.state.saves.length,0)
})
test('optional Turnstile bot check guards code requests only when both keys are set',async()=>{
  const f=reviewFixture();f.env.REVIEW_ACCESS='students'
  assert.equal((await(await f.request('status')).json() as any).data.turnstileSiteKey,undefined)
  f.env.TURNSTILE_SITE_KEY='0x4AAAAAAAfixture';f.env.TURNSTILE_SECRET_KEY='0x4AAAAAAAsecret'
  assert.equal((await(await f.request('status')).json() as any).data.turnstileSiteKey,'0x4AAAAAAAfixture')
  const verdicts:Record<string,object>={good:{success:true,hostname:'bye.test',action:'send-code'},bad:{success:false},host:{success:true,hostname:'evil.test',action:'send-code'},action:{success:true,hostname:'bye.test',action:'other'}}
  const seen:string[]=[]
  const outbound:typeof fetch=async(input,init)=>{
    const url=typeof input==='string'?input:input instanceof URL?input.href:input.url
    if(url==='https://challenges.cloudflare.com/turnstile/v0/siteverify'){const body=init?.body as FormData;seen.push(String(body.get('secret')));const v=verdicts[String(body.get('response'))];return v?Response.json(v):new Response('',{status:500})}
    return f.outbound(input,init)
  }
  const send=(email:string,turnstileToken?:string)=>handleReviewRequest(new Request('https://bye.test/api/reviews/auth/send',{method:'POST',headers:{Origin:'https://bye.test','Content-Type':'application/json'},body:JSON.stringify({email,turnstileToken})}),f.env,outbound)
  const code=async(r:Response)=>(await r.json() as any).error?.code??'OK'
  assert.equal(await code(await send('bot1@go.pasadena.edu')),'BOT_CHECK_REQUIRED')
  // Failed checks don't use up the address's own send limit (4 per 30 minutes).
  for(let i=0;i<6;i++)assert.equal(await code(await send('victim@go.pasadena.edu','bad')),'BOT_CHECK_FAILED')
  assert.equal((await send('victim@go.pasadena.edu','good')).status,200);f.state.otpRequests=0
  for(const t of ['bad','host','action'])assert.equal(await code(await send('bot2@go.pasadena.edu',t)),'BOT_CHECK_FAILED',t)
  assert.equal(await code(await send('bot3@go.pasadena.edu','down')),'BOT_CHECK_UNAVAILABLE')
  assert.equal(f.state.otpRequests,0)
  assert.equal((await send('bot4@go.pasadena.edu','good')).status,200);assert.equal(f.state.otpRequests,1)
  assert.ok(seen.every(s=>s==='0x4AAAAAAAsecret'))
  // Verifying a code needs no new check.
  assert.equal((await f.request('auth/verify',{email:'bot4@go.pasadena.edu',code:'123456'})).status,200)
})

test('course search ranks PCC course codes before title matches',async()=>{
  // PCC pads numbers: "math 5a" must find MATH 005A, and "math" must look at codes before titles.
  assert.equal(courseSearchPattern('math'),'MATH%')
  assert.equal(courseSearchPattern('Coll'),'COLL%')
  assert.equal(courseSearchPattern('math 5'),'MATH 005%')
  assert.equal(courseSearchPattern('math5a'),'MATH 005A%')
  assert.equal(courseSearchPattern('MATH 005A'),'MATH 005A%')
  assert.equal(courseSearchPattern('eth 14'),'ETH 014%')
  assert.equal(courseSearchPattern('5a'),'% 005A%')
  assert.equal(courseSearchPattern('abe 3002'),'ABE 3002%')
  assert.equal(courseSearchPattern('engl c1001'),'ENGL C1001%')
  const byCode=[{id:1,code:'MATH 005A'},{id:2,code:'MATH 005B'}],byTitle=[{id:9,code:'ABE 3002'},{id:2,code:'MATH 005B'}]
  assert.deepEqual(mergeCourseRows(byCode,byTitle).map(r=>r.id),[1,2,9])
  assert.equal(mergeCourseRows(Array.from({length:30},(_,i)=>({id:i})),[]).length,20)
  // The handler queries codes and titles separately.
  const f=reviewFixture(),cookie=sessionCookie()
  assert.equal((await f.request('courses?q=math 5a',undefined,cookie)).status,200)
  const urls=f.state.calls.filter(c=>c.url.includes('/rest/v1/courses')).map(c=>decodeURIComponent(c.url.replace(/\+/g,' ')))
  assert.ok(urls.some(u=>u.includes('code.ilike.MATH 005A%') && u.includes('code.ilike.%math 5a%')),'code prefix or code-contains query')
  assert.ok(urls.some(u=>u.includes('title=ilike.%math 5a%')),'title query')
})
