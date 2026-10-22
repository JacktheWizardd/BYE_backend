import { handleReviewRequest, type ReviewEnv } from '../src/reviews'
import { TEST_REVIEW_PREFIX } from '@bye/contracts/reviews'
export const TEST_EMAIL = 'tester@go.pasadena.edu'
export const REVIEW_ID = '11111111-1111-4111-8111-111111111111'
export const dimensions = [
  ['grading','lenient','strict'], ['workload','light','heavy'], ['attendance','optional','required'],
  ['clarity','unclear','clear'], ['feedback_speed','slow','fast'], ['test_alignment','rarely match class','closely match class'], ['textbook','optional','required'],
].map(([name,low_label,high_label], i)=>({name,low_label,high_label,sort_order:i+1}))
export const validForm = { professorId:'1', courseId:'2', quality:4, difficulty:3, body:'A temporary test.', answers:{grading:1,clarity:0} }
export const user = { id:'22222222-2222-4222-8222-222222222222', email:TEST_EMAIL, email_confirmed_at:'2026-10-16T00:00:00Z', aud:'authenticated', created_at:'2026-10-16T00:00:00Z', app_metadata:{provider:'email'}, user_metadata:{} }
export const jwt = () => [btoa(JSON.stringify({alg:'HS256',typ:'JWT'})), btoa(JSON.stringify({sub:user.id,role:'authenticated',exp:Math.floor(Date.now()/1000)+3600,iat:Math.floor(Date.now()/1000),iss:'https://fixture.supabase.co/auth/v1'})), 'fixture_signature'].join('.')
export function reviewFixture() {
  const env:ReviewEnv={REVIEWS_ENABLED:'true',REVIEW_TEST_EMAIL:TEST_EMAIL,SUPABASE_URL:'https://fixture.supabase.co',SUPABASE_PUBLISHABLE_KEY:'sb_publishable_fixture',REVIEW_LOCAL_HTTP:'true'}
  const state={authExpired:false, plusAlias:false, unconfirmed:false, nonPcc:false, emailRateLimited:false, saveFails:false, duplicate:false, catalogFails:false, verified:false, reportCount:0, otpRequests:0, numbers:new Map<string,number>(), numberFails:false, numberError:null as string|null, claimResult:null as {value:unknown}|null, countResult:null as {value:unknown}|null, saves:[] as Record<string,unknown>[], calls:[] as {method:string;url:string;authorization:string}[]}
  const outbound:typeof fetch=async (input,init)=>{
    const url=new URL(typeof input==='string'?input:input instanceof URL?input.href:input.url)
    const request=typeof input!=='string' && !(input instanceof URL)?input:undefined
    const headers=new Headers(init?.headers??request?.headers), method=init?.method??request?.method??'GET'
    const requestBody=init?.body!==undefined?String(init.body):request && method==='POST'?await request.text():''
    state.calls.push({method,url:url.href,authorization:headers.get('Authorization')??''})
    if(url.origin!=='https://fixture.supabase.co')throw new Error('Unexpected fixture origin')
    if(url.pathname==='/auth/v1/otp') { state.otpRequests++; return state.emailRateLimited?Response.json({error_code:'over_email_send_rate_limit',msg:'Too many requests'},{status:429}):Response.json({}) }
    if(url.pathname==='/auth/v1/verify') {
      const body=JSON.parse(requestBody)
      if(body.token!=='123456')return Response.json({error_code:'otp_expired',msg:'Invalid test code'},{status:403})
      state.verified=true
      return Response.json({access_token:jwt(),token_type:'bearer',expires_in:3600,expires_at:Math.floor(Date.now()/1000)+3600,refresh_token:'fixture-refresh-must-not-reach-browser',user:{...user,...(state.nonPcc?{email:'tester@example.com'}:{}),...(state.plusAlias?{email:'tester+alias@go.pasadena.edu'}:{}),...(state.unconfirmed?{email_confirmed_at:null}:{})}})
    }
    if(url.pathname==='/auth/v1/user')return state.authExpired?Response.json({msg:'Expired',error_code:'bad_jwt'},{status:401}):Response.json({...user,...(state.nonPcc?{email:'tester@example.com'}:{}),...(state.plusAlias?{email:'tester+alias@go.pasadena.edu'}:{}),...(state.unconfirmed?{email_confirmed_at:null}:{})})
    if(url.pathname==='/rest/v1/rpc/submit_review') {
      if(state.saveFails)return Response.json({code:'XX000',message:'fixture failure'},{status:503})
      if(state.duplicate)return Response.json({code:'23505',message:'duplicate'},{status:409})
      const form=JSON.parse(requestBody);state.saves.push(form);state.duplicate=true
      return Response.json(REVIEW_ID)
    }
    if(url.pathname==='/rest/v1/rpc/claim_bye_number') {
      if(state.numberError)return Response.json({code:state.numberError,message:'upstream-secret'},{status:400})
      if(state.claimResult)return Response.json(state.claimResult.value)
      if(state.numberFails)return Response.json({code:'XX000',message:'fixture failure'},{status:503})
      if(!headers.get('Authorization')?.startsWith('Bearer ey'))return Response.json({code:'42501',message:'not a student'},{status:403})
      if(!state.numbers.has(user.id))state.numbers.set(user.id,state.numbers.size+2)
      return Response.json([{number:state.numbers.get(user.id),total:state.numbers.size}])
    }
    if(url.pathname==='/rest/v1/rpc/bye_number_count')return state.numberFails?Response.json({code:'XX000',message:'fixture failure'},{status:503}):Response.json(state.countResult?state.countResult.value:state.numbers.size)
    if(state.catalogFails)return Response.json({code:'XX000',message:'fixture catalog failure'},{status:503})
    if(url.pathname==='/rest/v1/dimensions')return Response.json(dimensions)
    if(url.pathname==='/rest/v1/reports') { state.reportCount++;return new Response(null,{status:201}) }
    if(url.pathname==='/rest/v1/reviews') {
      if(url.searchParams.get('select')==='id')return Response.json({id:REVIEW_ID})
      return Response.json([{id:REVIEW_ID,quality:4,difficulty:3,body:'Fictional saved review',created_at:'2026-10-16T00:00:00Z',course_id:2,courses:{code:'TEST 001',title:'FICTIONAL TEST CLASS'}}])
    }
    if(url.pathname==='/rest/v1/courses'){const row={id:2,code:'TEST 001',title:'FICTIONAL TEST CLASS'};return Response.json(headers.get('Accept')?.includes('object')?row:[row])}
    if(url.pathname==='/rest/v1/professors'){const row={id:1,first_name:'Alex',last_name:'Fixture'};return Response.json(headers.get('Accept')?.includes('object')?row:[row])}
    throw new Error('Unmocked fixture path: '+url.pathname)
  }
  return {env,state,outbound,request:(path:string,body?:unknown,cookie?:string,origin='https://bye.test')=>handleReviewRequest(new Request('https://bye.test/api/reviews/'+path,{method:body===undefined?'GET':'POST',headers:{...(body===undefined?{}:{Origin:origin,'Content-Type':'application/json'}),...(cookie?{Cookie:cookie}:{})},...(body===undefined?{}:{body:JSON.stringify(body)})}),env,outbound),prefix:TEST_REVIEW_PREFIX}
}
