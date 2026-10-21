import assert from 'node:assert/strict';
import {prepare} from '../src/domain.ts';
import {upload,worker} from '../src/sync.ts';
export async function multiTermScenarios(db,check,query,call,rpc,fixture) {
  const advance=()=>db.exec("update bye_schedule.collection_control set next_fetch='-infinity',lock_token=null,lock_until=null; update bye_schedule.state set next_fetch='-infinity',lock_token=null,lock_until=null");
  const terms=[fixture.terms[0],{termCode:'202730',termName:'Spring 2027',termDisplayControl:'Y'}];
  await check('daily discovery preserves snapshots; unvalidated terms never appear',async()=>{
    await advance(); await db.exec("update bye_schedule.collection_control set discovery_checked_at=null"); const c=await call('discover-claim'); assert(c.token);
    await assert.rejects(call('discover-publish',{token:c.token,terms:[{termCode:'oops'}]}));
    await call('discover-publish',{token:c.token,terms});
    const list=await call('read',{route:'terms',identity:'b'.repeat(64)});
    assert(!list.data.some(t=>t.termCode==='202730'));
    assert.equal((await call('discover-claim')).skipped,'DISCOVERED');
  });
  await check('private calendar configuration requires verified official dates and reference',async()=>{
    await assert.rejects(call('term-dates',{term:'202670',startDate:'2026-08-24',endDate:'2026-12-13',reference:'https://example.invalid/calendar'}));
    await call('term-dates',{term:'202670',startDate:'2026-08-24',endDate:'2026-12-13',reference:'https://pasadena.edu/fixture-calendar'});
    assert.equal((await call('state')).official_start,'2026-08-24');
    await db.exec("update bye_schedule.state set official_start=null,official_end=null,date_reference=null where term='202670'");
  });
  let spring;
  await check('repeated CRNs are isolated across semesters; global budget cannot be bypassed',async()=>{
    await advance();
    const rows=structuredClone(fixture.rows).map(r=>({...r,termCode:'202730',seatsAvail:'41'}));
    spring=await prepare(rows,undefined,'202730');
    const c=await call('claim',{mode:'owner',term:'202730'});assert(c.token);
    assert.equal((await call('claim',{mode:'owner',term:'202670'})).skipped,'LOCKED');
    await upload(rpc,c.token,spring,c,new Date().toISOString(),terms[1],true,'202730');
    assert.equal((await call('claim',{mode:'owner',term:'202670'})).skipped,'COOLDOWN');
    const count=await query("select term,value->>'seatsAvailable' seats from bye_schedule.availability where crn='80206' order by term");
    assert.equal(count.length,2);assert.equal(count[1].seats,'41');assert.notEqual(count[0].seats,'41');
  });
  await check('instructor assignment changes invalidate catalog but not seats; other terms survive cleanup',async()=>{
    const rows=structuredClone(spring.raw);for(const r of rows) if(r.crn==='90003') r.pfaName='Taylor Example';
    const next=await prepare(rows,undefined,'202730');
    assert.notEqual(next.catalogHash,spring.catalogHash);assert.equal(next.availabilityHash,spring.availabilityHash);
    await advance();const c=await call('claim',{mode:'owner',term:'202730'});
    await upload(rpc,c.token,next,c,new Date().toISOString(),terms[1],false,'202730');
    await call('cleanup');
    assert((await query("select 1 from bye_schedule.sections where catalog=(select catalog from bye_schedule.state where term='202670')")).length);
    await call('rollback',{term:'202730',target:'catalog'});
    assert.equal((await call('state',{term:'202730'})).catalog,spring.catalogHash);
  });
  await check('removed terms remain readable but counts expire and collection stops',async()=>{
    await advance();await db.exec("update bye_schedule.collection_control set discovery_checked_at=null");
    const c=await call('discover-claim');await call('discover-publish',{token:c.token,terms:[terms[0]]});
    const r=await call('read',{route:'availability',term:'202730',crns:['80206'],identity:'c'.repeat(64)});
    assert.equal(r.meta.stale,true);assert.equal(r.data[0].availability,null);
    await advance();assert.equal((await call('claim',{mode:'owner',term:'202730'})).skipped,'IDLE');
  });
  await check('verified dates slow later terms; unknown dates keep early priority',async()=>{
    await db.exec("update bye_schedule.state set official_start=current_date-40,official_end=current_date+40,date_reference='fixture calendar' where term='202670'");
    const r=await call('read',{route:'manifest',term:'202670',identity:'d'.repeat(64)});
    assert.equal(r.meta.refreshPolicy.targetSeconds,1800);
    const unknown=await call('read',{route:'manifest',term:'202730',identity:'d'.repeat(64)});
    assert.equal(unknown.meta.refreshPolicy.targetSeconds,300);
  });
  await check('idle early terms slow down and discovery failure does not starve known terms',async()=>{
    await advance();await db.exec("update bye_schedule.state set enabled=true,listed=true,official_start=null,official_end=null,date_reference=null,active_until=null,renewed_at=null where term='202670';update bye_schedule.collection_control set discovery_checked_at=null,discovery_next_fetch='-infinity'");
    const discovery=await call('discover-claim');assert(discovery.token);
    await call('discover-fail',{token:discovery.token,code:'TERMS_VALIDATION_FAILED'});
    assert.equal((await call('discover-claim')).skipped,'DISCOVERY_BACKOFF');
    await db.exec("update bye_schedule.collection_control set next_fetch='-infinity'");
    const c=await call('claim',{mode:'owner',term:'202670'});assert(c.token);
    const p=await prepare(fixture.rows);
    await upload(rpc,c.token,p,c,new Date().toISOString(),fixture.terms[0],false);
    assert((await query("select next_fetch>now()+interval '29 minutes' slow from bye_schedule.state where term='202670'"))[0].slow);
    await call('read',{route:'manifest',term:'202670',identity:'e'.repeat(64)});
    assert((await query("select next_fetch<=now() due from bye_schedule.state where term='202670'"))[0].due);
    assert.equal((await call('claim',{mode:'owner',term:'202670'})).skipped,'COOLDOWN');
  });
  await check('fetch, decode, validation, staging and publication failures have safe diagnostics',async()=>{
    for(const [source,code] of [[()=>new Response('secret upstream message',{status:429,headers:{'Retry-After':'600'}}),'SOURCE_FETCH_FAILED'],[()=>new Response('bad json'),'SOURCE_DECODE_FAILED'],[()=>Response.json([{termCode:'wrong'}]),'SCHEDULE_VALIDATION_FAILED']]) {
      await advance();await call('enable',{enabled:true});
      const response=await worker(rpc,'test',async()=>source())(new Request('http://worker',{method:'POST',headers:{Authorization:'Bearer test'},body:JSON.stringify({action:'run'})}));
      const body=await response.json();assert.equal(body.diagnosticCode,code);assert(!JSON.stringify(body).includes('secret'));assert(body.previousRetained);
    }
    for(const failure of ['stage','publish']) {
      let recorded;
      const fake={rpc:async(_,{op,args})=>{
        if(op==='cleanup') return {};
        if(op==='claim') return {token:'fixture',metadata:terms[0],daily:false};
        if(op==='values') return [];
        if(op===failure) throw new Error('password and private SQL');
        if(op==='fail') {recorded=args;return {};}
        return {};
      }};
      const result=await worker(fake,'test',async()=>Response.json(fixture.rows))(new Request('http://worker',{method:'POST',headers:{Authorization:'Bearer test'},body:'{"action":"run"}'}));
      const body=await result.json();assert.equal(body.diagnosticCode,failure==='stage'?'STAGING_FAILED':'PUBLICATION_FAILED');assert.equal(recorded.code,body.diagnosticCode);assert(!JSON.stringify(body).includes('password'));
    }
  });
}
