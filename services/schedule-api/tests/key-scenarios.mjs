import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { sha } from '../src/domain.ts';
import { api } from '../src/api.ts';
export async function keyScenarios(db,check,query,call,rpc){
 const owner='11111111-1111-4111-8111-111111111111', outsider='22222222-2222-4222-8222-222222222222';
 let fixtureTime='2030-01-01T00:00:00Z';
 const setTime=async iso=>{fixtureTime=iso;return db.exec(`create or replace function bye_schedule.key_clock() returns timestamptz language sql volatile set search_path=pg_catalog as $$select '${iso}'::timestamptz$$`);};
 const manage=async(action,args={})=>(await query('select public.bye_key_management($1,$2::jsonb) value',[action,JSON.stringify(args)]))[0].value;
 const stamp=async()=>new Date(fixtureTime).toISOString();
 const mutation=async(action,args={})=>manage(action,{requestId:randomUUID(),requestedAt:await stamp(),...args});
 let key,rotated,raw='bye_pk_'+('a'.repeat(43));
 await setTime('2030-01-01T00:00:00Z');
 await check('explicit confirmed owner bootstrap; ordinary accounts and private tables denied',async()=>{
  await db.exec(`insert into auth.users(id,email_confirmed_at) values('${owner}',now()),('${outsider}',now())`);
  assert.equal((await call('owner-add',{userId:randomUUID()})).error,'CONFIRMED_USER_REQUIRED');
  await call('owner-add',{userId:owner});
  await db.exec('set role authenticated');
  assert.equal((await manage('session')).error,'FORBIDDEN');
  await query("select set_config('request.jwt.claim.sub',$1,false)",[outsider]);
  assert.equal((await mutation('create')).error,'FORBIDDEN');
  for(const table of ['owners','client_keys','key_audit','key_receipts']) await assert.rejects(db.exec('select * from bye_schedule.'+table),/permission denied/);
  await assert.rejects(db.exec("select bye_schedule.schedule_command('read','{}')"),/permission denied/);
  await query("select set_config('request.jwt.claim.sub',$1,false)",[owner]);
  assert.equal((await manage('session')).owner,owner);
  await db.exec('reset role');
 });
 await check('creation is digest-only, no expiry, paginated and idempotent even after a lost response',async()=>{
  const args={requestId:randomUUID(),requestedAt:await stamp(),newId:randomUUID(),digest:await sha(raw),mask:'bye_pk_…aaaa',label:'Windows fixture',clientType:'windows'};
  const result=await manage('create',args);key=result.key;
  assert.equal(key.retire_at,null);assert.equal(key.digest,undefined);
  const replay=await manage('create',{...args,newId:randomUUID(),digest:await sha('another random retry'),mask:'bye_pk_…bbbb'});
  assert.equal(replay.key.id,key.id);assert.equal(replay.replayed,true);assert.equal(replay.keyRecoverable,false);
  assert.equal((await manage('create',{...args,label:'different'})).error,'IDEMPOTENCY_CONFLICT');
  assert.equal((await manage('create',{...args,requestedAt:'2020-01-01T00:00:00Z'})).error,'REQUEST_EXPIRED');
  assert.equal((await manage('list',{offset:0})).limit,25);
  assert(!JSON.stringify(await manage('audit')).includes(raw));
 });
 await check('registry authenticates every cached read; sampled usage changes at five minutes only',async()=>{
  const handler=api(rpc,'fixture-key-limits');
  const read=etag=>handler(new Request('https://fixture/v1/terms/202670/catalog',{headers:{apikey:raw,...(etag?{'If-None-Match':etag}:{})}}));
  const initial=await read();assert.equal(initial.status,200);const etag=initial.headers.get('etag');
  assert.equal((await read(etag)).status,304);
  const first=(await query('select last_used_at from bye_schedule.client_keys where id=$1',[key.id]))[0].last_used_at;
  await setTime('2030-01-01T00:04:59Z');assert.equal((await read(etag)).status,304);
  assert.equal(String((await query('select last_used_at from bye_schedule.client_keys where id=$1',[key.id]))[0].last_used_at),String(first));
  await setTime('2030-01-01T00:05:00Z');assert.equal((await read(etag)).status,304);
  assert.notEqual(String((await query('select last_used_at from bye_schedule.client_keys where id=$1',[key.id]))[0].last_used_at),String(first));
  key=(await mutation('disable',{id:key.id,revision:key.revision})).key;
  assert.equal((await read(etag)).status,401);
  key=(await mutation('enable',{id:key.id,revision:key.revision})).key;assert.equal((await read(etag)).status,304);
 });
 await check('rotation serialized by revision; active replacement and exact thirty-day retirement',async()=>{
  await setTime('2030-01-01T00:00:00Z');
  const args={id:key.id,revision:key.revision,label:'Rotated fixture',clientType:'windows',newId:randomUUID(),digest:await sha('replacement'),mask:'bye_pk_…test'};
  const results=await Promise.all([mutation('rotate',args),mutation('rotate',{...args,newId:randomUUID(),digest:await sha('conflicting replacement')})]);
  assert.equal(results[1].error,'CONFLICT');key=results[0].previous;rotated=results[0].key;
  assert.equal(new Date(key.retire_at).toISOString(),'2030-01-31T00:00:00.000Z');assert.equal(rotated.retire_at,null);
  assert.equal(rotated.rotated_from,key.id);
  await setTime('2030-01-30T23:59:59.999Z');
  const argsRead={route:'terms',identity:await sha('boundary'),keyDigest:await sha(raw)};
  assert.equal((await call('read',argsRead)).error,undefined);
  await setTime('2030-01-31T00:00:00Z');assert.equal((await call('read',argsRead)).error,'UNAUTHORIZED');
  const handler=api(rpc,'expiry');assert.equal((await handler(new Request('https://fixture/v1/terms/202670/catalog',{headers:{apikey:raw,'If-None-Match':'*'}}))).status,401);
 });
 await check('expired extension requires confirmation, defaults from later deadline, enable cannot bypass expiry',async()=>{
  assert.equal((await mutation('extend',{id:key.id,revision:key.revision})).error,'CONFIRM_RESTORE');
  key=(await mutation('disable',{id:key.id,revision:key.revision})).key;
  key=(await mutation('enable',{id:key.id,revision:key.revision})).key;assert.equal(key.effective_status,'expired');
  key=(await mutation('extend',{id:key.id,revision:key.revision,confirmRestore:true})).key;
  assert.equal(new Date(key.retire_at).toISOString(),'2030-03-02T00:00:00.000Z');
  key=(await mutation('extend',{id:key.id,revision:key.revision})).key;
  assert.equal(new Date(key.retire_at).toISOString(),'2030-04-01T00:00:00.000Z');
  assert.equal((await mutation('extend',{id:key.id,revision:key.revision,retireAt:'2030-03-31T00:00:00Z'})).error,'INVALID_QUERY');
 });
 await check('revocation permanent; legacy registry record has no retirement or fallback',async()=>{
  assert.equal((await mutation('revoke',{id:rotated.id,revision:rotated.revision})).error,'CONFIRM_REVOKE');
  rotated=(await mutation('revoke',{id:rotated.id,revision:rotated.revision,confirm:true})).key;
  assert.equal((await mutation('enable',{id:rotated.id,revision:rotated.revision})).error,'REVOKED');
  assert.equal((await call('read',{route:'terms',identity:await sha('other'),keyDigest:await sha('replacement')})).error,'UNAUTHORIZED');
  const legacy=(await query("select * from bye_schedule.client_keys where label='Existing BYE key' order by digest"));
  assert(legacy.every(k=>k.retire_at===null));
  assert.equal((await rpc.rpc('bye_schedule_backend',{op:'read',args:{route:'terms',identity:await sha('other')}})).error,'UNAUTHORIZED');
 });
 await check('shared network limit cannot multiply with extra keys; registry and receipts are bounded',async()=>{
  const identity=await sha('shared-client-network');
  for(let i=0;i<120;i++)assert.notEqual((await call('read',{route:'terms',identity,keyDigest:await sha(i%2?'key':raw)})).error,'RATE_LIMITED');
  assert.equal((await call('read',{route:'terms',identity,keyDigest:await sha('key')})).error,'RATE_LIMITED');
  await db.exec("insert into bye_schedule.client_keys(id,digest,label,client_type,mask) select gen_random_uuid(),md5(i::text)||md5(i::text),'cap','other','cap' from generate_series(1,100-(select count(*)::int from bye_schedule.client_keys where status<>'revoked')) i");
  assert.equal((await mutation('create',{newId:randomUUID(),digest:await sha('cap'),label:'cap',clientType:'other',mask:'cap'})).error,'REGISTRY_FULL');
  await db.exec("insert into bye_schedule.key_audit(at,actor,action,details) select bye_schedule.key_clock(),'11111111-1111-4111-8111-111111111111','fixture','{}' from generate_series(1,2600)");
  await manage('audit');assert.equal(Number((await query('select count(*) n from bye_schedule.key_audit'))[0].n),2500);
  await setTime('2030-08-01T00:00:00Z');await call('cleanup');
  assert.equal(Number((await query('select count(*) n from bye_schedule.key_receipts'))[0].n),0);
  assert.equal((await query('select count(*) n from bye_schedule.client_keys where id=$1',[rotated.id]))[0].n,0);
  assert.equal((await query('select body from public.review_sentinel'))[0].body,'unchanged');
 });
}
