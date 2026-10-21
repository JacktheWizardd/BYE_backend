import {createServer} from 'node:http';
import {readFile,readdir,writeFile,mkdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {api} from '../src/api.ts';
import {worker} from '../src/sync.ts';
import {prepare,sha} from '../src/domain.ts';

// This executable can contact only its own ephemeral loopback simulator.
const nativeFetch=globalThis.fetch;
let origin='';
globalThis.fetch=async(input,init)=>{const url=new URL(typeof input==='string'?input:input instanceof URL?input.href:input.url);if(!origin || url.origin!==origin)throw new Error('EXTERNAL_NETWORK_DISABLED');return nativeFetch(input,init)};
const db=new PGlite();
const metrics={rpcCalls:0,writeRpcCalls:0,sourceRequests:0,sourceBytes:0};
const fixture=JSON.parse(await readFile(new URL('../tests/fixtures/fall-2026.json',import.meta.url),'utf8'));
await db.exec("create schema auth;create table auth.users(id uuid primary key,email_confirmed_at timestamptz,deleted_at timestamptz);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;create role anon;create role authenticated;create role service_role bypassrls;");
for(const name of (await readdir(new URL('../supabase/migrations/',import.meta.url))).filter(x=>x.endsWith('.sql')&&!x.includes('scheduler')).sort())await db.exec(await readFile(new URL('../supabase/migrations/'+name,import.meta.url),'utf8'));
await db.exec("create schema benchmark;create table benchmark.writes(kind text primary key,n bigint not null);create function benchmark.count_write() returns trigger language plpgsql as $$begin insert into benchmark.writes values(TG_TABLE_NAME||':'||TG_OP,1) on conflict(kind) do update set n=writes.n+1;return null;end$$");
for(const name of ['state','availability','catalogs','sections','raw_rows','staging','limits','client_keys'])await db.exec('create trigger benchmark_writes after insert or update or delete on bye_schedule.'+name+' for each row execute function benchmark.count_write()');
const writeCount=async()=>Number((await db.query('select coalesce(sum(n),0) n from benchmark.writes')).rows[0].n);
const rpc={async rpc(_,{op,args={}}){metrics.rpcCalls++;if(op!=='read'&&op!=='values'&&op!=='state')metrics.writeRpcCalls++;return (await db.query('select public.bye_schedule_backend($1,$2::jsonb) value',[op,JSON.stringify(args)])).rows[0].value}};
const call=(op,args={})=>rpc.rpc('',{op,args});
await call('register-key',{digest:await sha('fixture-only-key')});
const terms=Array.from({length:6},(_,i)=>({termCode:i===0?'202670':String(202700+i),termName:'Synthetic semester '+i,termDisplayControl:'Y'}));
const source=new Map(terms.map(t=>[t.termCode,fixture.rows.map(r=>({...r,termCode:t.termCode}))]));
let sourceScenario='normal';
const readApi=api(rpc,'fixture-salt');
const server=createServer(async(req,res)=>{
  try {
    const url=new URL(req.url,origin);
    if(url.pathname.startsWith('/pcc/')) {
      metrics.sourceRequests++;
      if(sourceScenario==='limited'){res.writeHead(429,{'Retry-After':'600'});res.end('{}');return;}
      if(sourceScenario==='timeout'){res.writeHead(504);res.end('{}');return;}
      const body=sourceScenario==='malformed'?'bad json':JSON.stringify(url.pathname==='/pcc/terms'?terms:source.get(url.pathname.split('/').at(-1)));
      metrics.sourceBytes+=Buffer.byteLength(body);res.writeHead(200,{'Content-Type':'application/json'});res.end(body);return;
    }
    const result=await readApi(new Request(origin+req.url,{headers:req.headers}));
    res.writeHead(result.status,Object.fromEntries(result.headers));res.end(Buffer.from(await result.arrayBuffer()));
  }catch{res.writeHead(500);res.end('{}');}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));origin='http://127.0.0.1:'+server.address().port;
const fetchSource=(url,init)=>{const u=new URL(url);if(u.origin!=='https://prod-apiweb.pasadena.edu')throw new Error('EXTERNAL_NETWORK_DISABLED');const path=u.pathname.endsWith('getClassScheduleTerms')?'/pcc/terms':'/pcc/'+u.pathname.split('/').at(-1);return fetch(origin+path,init)};
const sync=worker(rpc,'fixture-job',fetchSource);
const run=term=>sync(new Request(origin+'/worker',{method:'POST',headers:{Authorization:'Bearer fixture-job'},body:JSON.stringify({action:'run',term})}));
const reset=()=>db.exec("update bye_schedule.collection_control set next_fetch='-infinity',lock_token=null,lock_until=null;update bye_schedule.state set next_fetch='-infinity',lock_token=null,lock_until=null");
const percentile=(numbers,p)=>numbers.length?[...numbers].sort((a,b)=>a-b)[Math.min(numbers.length-1,Math.floor(numbers.length*p))]:0;
const started=performance.now(),cpu=process.cpuUsage();
const samples=[];
try {
  await reset();const discovery=await call('discover-claim');await call('discover-publish',{token:discovery.token,terms});
  for(const term of terms){await reset();const response=await run(term.termCode);if(response.status!==200)throw new Error('Fixture publication failed: '+await response.text());}
  for(const scenario of ['unchanged','seat-change','instructor-change','malformed','limited','timeout']) {
    sourceScenario=['malformed','limited','timeout'].includes(scenario)?scenario:'normal';
    if(scenario==='seat-change')for(const r of source.get('202670'))if(r.crn==='80206')r.seatsAvail='3';
    if(scenario==='instructor-change')for(const r of source.get('202670'))if(r.crn==='90003')r.pfaName='Taylor Example';
    await reset();const before=performance.now(),response=await run('202670'),body=await response.json();
    samples.push({scenario,status:response.status,elapsedMs:performance.now()-before,diagnosticCode:body.diagnosticCode??null});
  }
  sourceScenario='normal';
  const loads=[];
  for(const termCount of [1,3,6])for(const clients of [1,30,100,1000]) {
    await db.exec('delete from bye_schedule.limits');const durations=[];let successes=0,rateLimited=0;const beforeWrites=metrics.writeRpcCalls, beforeRows=await writeCount();
    for(let start=0;start<clients;start+=16)await Promise.all(Array.from({length:Math.min(16,clients-start)},async(_,offset)=>{
      const id=start+offset,term=terms[id%termCount].termCode,before=performance.now();
      const r=await fetch(origin+'/v1/terms/'+term+'/manifest',{headers:{apikey:'fixture-only-key','x-forwarded-for':id<clients*0.6?'campus-nat':'fixture-'+id}});await r.arrayBuffer();durations.push(performance.now()-before);if(r.status===200)successes++;else if(r.status===429)rateLimited++;else throw new Error('Unexpected fixture API response '+r.status);
    }));
    loads.push({termCount,clients,successes,rateLimited,latencyP50Ms:percentile(durations,.5),latencyP95Ms:percentile(durations,.95),latencyP99Ms:percentile(durations,.99),writeRpcCalls:metrics.writeRpcCalls-beforeWrites,databaseRowWrites:(await writeCount())-beforeRows});
  }
  const projections=[];
  for(const minutes of [1,2,5,10,30])for(const termCount of [1,3,6])for(const clients of [1,30,100,1000]) {
    const due=Array(termCount).fill(0),checked=Array(termCount).fill(0),queueDelays=[],screenDelays=[];let requests=0,writes=0;
    for(let at=0;at<86400;at+=minutes*60) {
      let selected=0;for(let i=1;i<termCount;i++)if(due[i]<due[selected])selected=i;
      if(due[selected]>at)continue;
      queueDelays.push(Math.max(0,at-due[selected]));screenDelays.push(at-checked[selected]+60);checked[selected]=at;due[selected]=at+300;requests++;
      if(requests%10===0)writes++; // explicitly modeled 10% changed responses
    }
    projections.push({model:'24-hour fair queue; all terms high priority; 10% changed responses; 60-second client poll',aggregateMinutes:minutes,termCount,clients,sourceRequests:requests,sourceBytes:requests*metrics.sourceBytes/Math.max(1,metrics.sourceRequests),clientManifestRequests:clients*1440,changedGenerations:writes,maxQueueDelaySeconds:Math.max(...queueDelays),estimatedWorstChangeToScreenSeconds:Math.max(...screenDelays),exceeds15MinuteFreshness:Math.max(...screenDelays)>900});
  }
  let savedReplay=null;
  if(process.argv[2]) {
    const raw=await readFile(process.argv[2],'utf8'),beforeCpu=process.cpuUsage(),before=performance.now(),prepared=await prepare(JSON.parse(raw));
    const cost=process.cpuUsage(beforeCpu);savedReplay={sourceBytes:Buffer.byteLength(raw),rows:prepared.rowCount,sections:prepared.sections.length,wallMs:performance.now()-before,cpuMs:(cost.user+cost.system)/1000,rssMiB:process.memoryUsage().rss/1048576,note:'In-process RSS includes PGlite/load harness; run npm run benchmark separately for the existing normalization gate.'};
  }
  if(savedReplay) for(const model of projections) {
    model.sourceBytes=model.sourceRequests*savedReplay.sourceBytes;
    model.estimatedNormalizationCpuMs=model.sourceRequests*savedReplay.cpuMs;
    model.transferBasis='saved Fall feed size; upstream ingress, not client egress; excludes daily term discovery';
  }
  const elapsed=process.cpuUsage(cpu);
  const report={generatedAt:new Date().toISOString(),network:'loopback only; external fetch denied',measured:{elapsedMs:performance.now()-started,cpuMs:(elapsed.user+elapsed.system)/1000,memory:process.memoryUsage(),databaseWrites:(await db.query("select * from benchmark.writes order by kind")).rows,...metrics,samples,loads,savedReplay},projections,recommendation:{aggregateSeconds:300,earlyTermTargetSeconds:300,laterTermTargetSeconds:1800,reason:'Keep existing collection ceiling. Multi-term queueing and campus NAT throttling require hosted observation before any increase. Projections are estimates, not PCC freshness or hosted capacity guarantees.'}};
  const output=new URL('../.local-benchmarks/',import.meta.url);await mkdir(output,{recursive:true});await writeFile(new URL('schedule.json',output),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify({output:'ignored .local-benchmarks/schedule.json',measured:report.measured,recommendation:report.recommendation},null,2));
} finally {server.closeAllConnections();await new Promise(resolve=>server.close(resolve));await db.close();globalThis.fetch=nativeFetch;}
