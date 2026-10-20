import {test} from 'node:test';
import {request as httpRequest} from 'node:http';
import assert from 'node:assert/strict';
import {dashboard} from '../dashboard/server.ts';
import {management} from '../src/admin.ts';
import {sha} from '../src/domain.ts';
const token='eyJ.fixture.owner-token-1234567890';
const json=(value:any,status=200)=>new Response(JSON.stringify(value),{status,headers:{'Content-Type':'application/json'}});
test('management validates user and owner before mutation; one-time secrets and replay',async()=>{
 let mode='owner',calls=0,first:any;
 const handler=management('https://fixture.supabase.co','sb_publishable_fixture',async()=>json({},mode==='invalid'?401:200),()=>({rpc:async(_name,input:any)=>{
  calls++;if(input.action==='session')return mode==='nonowner'?{error:'FORBIDDEN'}:{owner:'owner'};
  if(input.action==='create'){if(first)return {...first,replayed:true};assert.equal(input.args.digest.length,64);assert.notEqual(input.args.digest,'attacker');first={key:{id:input.args.newId},replayed:false};return {...first};}
  return {items:[]};
 }}));
 const req=(action='create',auth=token)=>new Request('https://fixture/admin',{method:'POST',headers:{Authorization:'Bearer '+auth,'Content-Type':'application/json'},body:JSON.stringify({action,args:{requestId:'fixture',digest:'attacker'}})});
 assert.equal((await handler(req('create','bye_pk_shared'))).status,401);
 mode='invalid';assert.equal((await handler(req())).status,401);assert.equal(calls,0);
 mode='nonowner';assert.equal((await handler(req())).status,403);assert.equal(calls,1);
 mode='owner';const created=await (await handler(req())).json();assert.match(created.plaintext,/^bye_pk_[A-Za-z0-9_-]{43}$/);
 assert.equal((await sha(created.plaintext)).length,64);
 const replay=await (await handler(req())).json();assert.equal(replay.plaintext,undefined);assert.equal(replay.key.id,created.key.id);
});
test('management fails closed on database outages without leaking errors',async()=>{
 const h=management('https://fixture.supabase.co','sb_publishable_fixture',async()=>json({}),()=>({rpc:async()=>{throw Error('private credential');}}));
 const r=await h(new Request('https://fixture',{method:'POST',headers:{Authorization:'Bearer '+token},body:'{}'}));assert.equal(r.status,503);assert(!await r.text().then(x=>x.includes('private credential')));
});
test('loopback dashboard protects Host, Origin, CSRF, opaque sessions, expiry, logout and bounded sessions',async()=>{
 let clock=Date.now(),owner=true,fail=false,emails=0;
 const app=dashboard({url:'http://fixture.test',key:'sb_publishable_fixture',port:0,clock:()=>clock,request:async(url,init)=>{
  if(fail)throw Error('network');
  const path=new URL(String(url)).pathname;
  if(path.endsWith('/otp')){emails++;assert.equal(JSON.parse(String(init?.body)).create_user,false);return json({});}
  if(path.endsWith('/verify'))return json({access_token:token,refresh_token:'must-not-leak',expires_in:60,user:{id:'owner'}});
  if(path.includes('bye-key-admin'))return owner?json({owner:'owner',items:[]}):json({error:{code:'FORBIDDEN'}},403);
  return json({});
 }});
 await app.start();const addr=app.server.address() as any;assert.equal(addr.address,'127.0.0.1');const base='http://127.0.0.1:'+addr.port;
 let cookie='',csrf='';
 const post=(path:string,data:any={},headers:Record<string,string>={})=>fetch(base+path,{method:'POST',headers:{Origin:base,'Content-Type':'application/json','X-BYE-Local':'1',Cookie:cookie,'X-CSRF-Token':csrf,...headers},body:JSON.stringify(data)});
 const login=async()=>{const r=await post('/api/auth/verify',{email:'owner@example.test',code:'123456'});const d=await r.json();if(r.ok){cookie=r.headers.get('set-cookie')!.split(';')[0];csrf=d.csrf;}return {r,d};};
 try{
  assert.equal(await new Promise(resolve=>{const r=httpRequest(base+'/api/session',{headers:{Host:'evil.example'}},res=>{res.resume();resolve(res.statusCode);});r.end();}),403);
  assert.equal((await post('/api/auth/send',{email:'owner@example.test'},{Origin:'https://evil.example'})).status,403);assert.equal(emails,0);
  assert.equal((await post('/api/auth/send',{email:'owner@example.test'})).status,200);assert.equal(emails,1);
  owner=false;assert.equal((await login()).r.status,403);assert.equal(app.sessionCount(),0);owner=true;
  const first=await login();assert.equal(first.r.status,200);assert.match(first.r.headers.get('set-cookie')!,/HttpOnly; SameSite=Strict/);assert(!JSON.stringify(first.d).includes(token));assert(!cookie.includes(token));
  assert.equal((await post('/api/manage',{action:'list'},{'X-CSRF-Token':'wrong'})).status,403);
  assert.equal((await post('/api/manage',{action:'list'})).status,200);
  fail=true;assert.equal((await post('/api/manage',{action:'create'})).status,503);fail=false;
  clock+=61000;assert.equal((await post('/api/manage',{action:'list'})).status,401);assert.equal(app.sessionCount(),0);
  await login();assert.equal((await post('/api/signout')).status,200);assert.equal(app.sessionCount(),0);assert.equal((await post('/api/manage',{action:'list'})).status,401);
  cookie='';csrf='';for(let i=0;i<8;i++){await login();cookie='';csrf='';}assert.equal(app.sessionCount(),8);assert.equal((await login()).r.status,429);
  const html=await fetch(base+'/');assert.match(html.headers.get('content-security-policy')!,/frame-ancestors 'none'/);assert.match(await html.text(),/Owner sign-in/);
 }finally{await app.close();}assert.equal(app.sessionCount(),0);
});
