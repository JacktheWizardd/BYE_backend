import { test } from 'node:test'
import assert from 'node:assert/strict'
import { handleReviewRequest } from '../src/reviews'
import { reviewFixture, jwt } from './review-fixtures'
const sessionCookie=()=>`__Secure-bye-review=${jwt()}`

test('a signed-in student gets a number from 2 up, and the same one on every later claim',async()=>{
  const f=reviewFixture()
  const first=await f.request('number',{},sessionCookie())
  assert.equal(first.status,200);assert.equal(first.headers.get('Cache-Control'),'no-store')
  assert.deepEqual((await first.json() as any).data,{number:2,total:1})
  assert.deepEqual((await(await f.request('number',{},sessionCookie())).json() as any).data,{number:2,total:1})
  assert.equal(f.state.numbers.size,1)
})
test('claiming a number needs a verified school session and the site origin',async()=>{
  const f=reviewFixture()
  assert.equal((await f.request('number',{})).status,401)
  assert.equal((await f.request('number',{},sessionCookie(),'https://evil.test')).status,403)
  f.state.nonPcc=true
  assert.equal((await f.request('number',{},sessionCookie())).status,401)
  assert.equal(f.state.numbers.size,0)
})
test('number routes only accept their own methods',async()=>{
  const f=reviewFixture()
  assert.equal((await f.request('number',undefined,sessionCookie())).status,405)
  const post=new Request('https://bye.test/api/reviews/numbers',{method:'POST',headers:{Origin:'https://bye.test','Content-Type':'application/json'},body:'{}'})
  assert.equal((await handleReviewRequest(post,f.env,f.outbound)).status,405)
})
test('the student count is public and reveals only a number',async()=>{
  const f=reviewFixture()
  await f.request('number',{},sessionCookie())
  const count=await f.request('numbers')
  assert.equal(count.status,200)
  assert.deepEqual((await count.json() as any).data,{total:1})
})
test('database failures never invent a number',async()=>{
  const f=reviewFixture();f.state.numberFails=true
  const claim=await f.request('number',{},sessionCookie())
  assert.equal(claim.status,503);assert.equal((await claim.json() as any).error.code,'NUMBER_UNAVAILABLE')
  assert.equal((await f.request('numbers')).status,503)
})

function raw(f: ReturnType<typeof reviewFixture>, body: string | undefined = '{}', headers: Record<string,string> = {}, url = 'https://bye.test/api/reviews/number') {
  return handleReviewRequest(new Request(url, {method:'POST', headers:{Origin:'https://bye.test','Content-Type':'application/json',Cookie:sessionCookie(),...headers},body}), f.env, f.outbound)
}
const claims = (f: ReturnType<typeof reviewFixture>) => f.state.calls.filter(c=>c.url.endsWith('/rpc/claim_bye_number')).length

test('missing Origin is rejected before any upstream request',async()=>{
  const f=reviewFixture()
  const r=await handleReviewRequest(new Request('https://bye.test/api/reviews/number',{method:'POST',headers:{'Content-Type':'application/json',Cookie:sessionCookie()},body:'{}'}),f.env,f.outbound)
  assert.equal(r.status,403);assert.equal(f.state.calls.length,0)
})
test('claim validates JSON content type, byte limit, object and empty fields before RPC',async()=>{
  for(const [body,headers,status] of [
    ['{}',{'Content-Type':'text/plain'},415], ['',{},400], ['{',{},400], ['null',{},400], ['[]',{},400],
    ['{"number":1}',{},400], [' '.repeat(16385),{},413], ['{}',{'Content-Type':'application/json; charset=utf-8'},200],
  ] as [string,Record<string,string>,number][]) {
    const f=reviewFixture(),r=await raw(f,body,headers)
    assert.equal(r.status,status);assert.equal(claims(f),status===200?1:0)
  }
})
test('expired, unconfirmed and aliased students cannot reach claim RPC',async()=>{
  for(const flag of ['authExpired','unconfirmed','plusAlias'] as const){
    const f=reviewFixture();f.state[flag]=true
    assert.equal((await raw(f)).status,401);assert.equal(claims(f),0)
  }
})
test('disabled configuration and non-HTTPS requests make no upstream call',async()=>{
  const f=reviewFixture();f.env.REVIEWS_ENABLED='false'
  assert.equal((await raw(f)).status,503)
  f.env.REVIEWS_ENABLED='true'
  assert.equal((await raw(f,'{}',{Origin:'http://bye.test'},'http://bye.test/api/reviews/number')).status,400)
  assert.equal(f.state.calls.length,0)
})
test('RPC session errors map to 401 and never expose upstream content',async()=>{
  for(const code of ['42501','PGRST301','PGRST303','XX000']){
    const f=reviewFixture();f.state.numberError=code
    const r=await raw(f);assert.equal(r.status,code==='XX000'?503:401)
    assert.doesNotMatch(await r.text(),/upstream-secret|fixture failure/)
  }
})
test('malformed claim results fail closed; gaps are valid',async()=>{
  for(const value of [null,[],[null],[{number:2,total:1},{number:3,total:2}],{number:2,total:1},[{number:0,total:1}],[{number:2,total:0}],[{number:'2',total:1}],[{number:2.5,total:1}],[{number:2,total:Number.MAX_SAFE_INTEGER+1}]]){
    const f=reviewFixture();f.state.claimResult={value}
    assert.equal((await raw(f)).status,503)
  }
  const f=reviewFixture();f.state.claimResult={value:[{number:42,total:3}]}
  assert.deepEqual((await (await raw(f)).json() as any).data,{number:42,total:3})
})
test('count rejects invalid results and accepts zero with all privacy headers',async()=>{
  for(const value of [null,-1,1.5,'1',{},Number.MAX_SAFE_INTEGER+1]){
    const f=reviewFixture();f.state.countResult={value}
    assert.equal((await f.request('numbers')).status,503)
  }
  const f=reviewFixture(),r=await f.request('numbers')
  assert.deepEqual((await r.json() as any).data,{total:0})
  assert.equal(r.headers.get('Cache-Control'),'no-store')
  assert.equal(r.headers.get('X-Robots-Tag'),'noindex, nofollow')
  assert.equal(r.headers.get('X-Content-Type-Options'),'nosniff')
  assert.equal(r.headers.get('Vary'),'Cookie');assert.equal(r.headers.get('Set-Cookie'),null)
})
test('claim and count IP limits return Retry-After without another RPC',async()=>{
  for(const [route,max,ip] of [['number',10,'192.0.2.21'],['numbers',60,'192.0.2.22']] as const){
    const f=reviewFixture()
    const request=()=>handleReviewRequest(new Request('https://bye.test/api/reviews/'+route,{method:route==='number'?'POST':'GET',headers:{'CF-Connecting-IP':ip,Origin:'https://bye.test','Content-Type':'application/json',Cookie:sessionCookie()},...(route==='number'?{body:'{}'}:{})}),f.env,f.outbound)
    for(let i=0;i<max;i++)assert.equal((await request()).status,200)
    const before=f.state.calls.length,r=await request()
    assert.equal(r.status,429);assert.ok(Number(r.headers.get('Retry-After'))>0)
    assert.equal(r.headers.get('Cache-Control'),'no-store');assert.equal(f.state.calls.length,before)
  }
})
