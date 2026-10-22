// Offline after npm ci; owns its cluster, never accepts a URL or production credentials.
import EmbeddedPostgres from 'embedded-postgres'
import {Client} from 'pg'
import {readFile,mkdtemp,rm} from 'node:fs/promises'
import {tmpdir} from 'node:os'
import {join} from 'node:path'
import {randomBytes} from 'node:crypto'
import {createServer} from 'node:net'
import assert from 'node:assert/strict'
const sql=await readFile(new URL('../../supabase/007_bye_numbers.sql',import.meta.url),'utf8')
const helper=await readFile(new URL('../../supabase/006_pcc_student_no_plus_alias.sql',import.meta.url),'utf8')
const owner=sql.split('-- BEGIN OWNER SQL\n')[1].split('-- END OWNER SQL')[0].replace(/^-- ?/gm,'')
const dir=await mkdtemp(join(tmpdir(),'bye-number-rehearsal-')), password=randomBytes(24).toString('hex')
const probe=createServer();await new Promise(r=>probe.listen(0,'127.0.0.1',r));const port=probe.address().port;await new Promise(r=>probe.close(r))
const pg=new EmbeddedPostgres({databaseDir:join(dir,'db'),user:'postgres',password,port,persistent:true,postgresFlags:['-h','127.0.0.1','-k',dir],onLog:()=>{},onError:()=>{}})
const clients=[];let started=false,passed=0
const check=async(name,fn)=>{await fn();passed++;console.log('PASS '+name)}
const uid=n=>`00000000-0000-4000-8000-${String(n).padStart(12,'0')}`
async function connect(){const c=new Client({host:'127.0.0.1',port,user:'postgres',password,database:'postgres',statement_timeout:10000});await c.connect();clients.push(c);return c}
async function as(c,role,id,q){await c.query('begin');try{await c.query('set local role '+role);await c.query("select set_config('request.jwt.claim.sub',$1,true)",[id??'']);const r=await c.query(q);await c.query('commit');return r}catch(e){await c.query('rollback');throw e}}
const claim=(c,n)=>as(c,'authenticated',uid(n),'select * from public.claim_bye_number()')
const denied=(fn,code='42501')=>assert.rejects(fn,e=>e.code===code)
try{
 await pg.initialise();await pg.start();started=true
 const db=await connect(),other=await connect()
 console.log('PostgreSQL '+(await db.query('show server_version')).rows[0].server_version)
 await db.query(`create role anon nologin;create role authenticated nologin;create schema auth;create schema private;
 grant usage on schema auth,private to authenticated;grant usage on schema public to anon,authenticated;
 create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz);
 create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 grant execute on function auth.uid() to authenticated;`)
 await db.query(helper)
 for(let n=1;n<=12;n++)await db.query('insert into auth.users values($1,$2,$3)',[uid(n),n===4?'fictional@example.invalid':n===6?'fictional+alias@go.pasadena.edu':`fictional${n}@go.pasadena.edu`,n===5?null:'2026-01-01'])
 await check('install',()=>db.query(sql))
 await check('public empty count',async()=>assert.equal((await as(db,'anon',null,'select public.bye_number_count() total')).rows[0].total,0))
 await check('first claim 2',async()=>assert.deepEqual((await claim(db,2)).rows,[{number:2,total:1}]))
 await check('repeat stable without sequence consumption',async()=>{assert.equal((await claim(db,2)).rows[0].number,2);assert.equal((await db.query('select last_value from private.bye_number_seq')).rows[0].last_value,'2')})
 await check('second student 3',async()=>assert.equal((await claim(db,3)).rows[0].number,3))
 for(const [n,label] of [[4,'non-PCC'],[5,'unconfirmed'],[6,'alias']])await check(label+' denied',()=>denied(()=>claim(db,n)))
 await check('missing uid denied',()=>denied(()=>as(db,'authenticated',null,'select * from public.claim_bye_number()')))
 await check('anon claim denied',()=>denied(()=>as(db,'anon',null,'select * from public.claim_bye_number()')))
 for(const role of ['anon','authenticated'])for(const [label,q] of [
 ['select','select * from private.bye_numbers'],['insert',`insert into private.bye_numbers values('${uid(7)}',100,now())`],
 ['update','update private.bye_numbers set number=100'],['delete','delete from private.bye_numbers'],
 ['sequence read','select * from private.bye_number_seq'],['nextval',"select nextval('private.bye_number_seq')"],['setval',"select setval('private.bye_number_seq',100)"]
 ])await check(role+' denied '+label,()=>denied(()=>as(db,role,uid(2),q)))
 const assign=n=>db.query(owner.replace('<your school email>',`fictional${n}@go.pasadena.edu`)).catch(async e=>{await db.query('rollback');throw e})
 await check('missing owner fails',()=>denied(()=>assign(99),'P0002'))
 await check('owner insert 1',async()=>{await assign(1);assert.equal((await claim(db,1)).rows[0].number,1)})
 await check('owner repeat idempotent',async()=>{await assign(1);assert.equal((await db.query('select count(*)::int n from private.bye_numbers')).rows[0].n,3)})
 await check('owner collision fails',()=>denied(()=>assign(3),'P0001'))
 await check('next student 4',async()=>assert.equal((await claim(db,7)).rows[0].number,4))
 await check('move existing owner to 1 preserves sequence',async()=>{
 await db.query('delete from private.bye_numbers where user_id=$1',[uid(1)])
 const seq=(await db.query('select * from private.bye_number_seq')).rows
 await assign(7);assert.equal((await claim(db,7)).rows[0].number,1);assert.deepEqual((await db.query('select * from private.bye_number_seq')).rows,seq)
 })
 await check('same-user race blocks then returns one number',async()=>{
 const pid=(await other.query('select pg_backend_pid() pid')).rows[0].pid
 await db.query('begin');await db.query('set local role authenticated');await db.query("select set_config('request.jwt.claim.sub',$1,true)",[uid(8)])
 const first=await db.query('select * from public.claim_bye_number()');const pending=claim(other,8)
 // Observe the actual lock using a third observer, not a timing-only Promise.all test.
 const observer=await connect();let waiting=false
 for(let i=0;i<100;i++){const r=await observer.query('select wait_event_type from pg_stat_activity where pid=$1',[pid]);if(r.rows[0]?.wait_event_type==='Lock'){waiting=true;break}await new Promise(r=>setTimeout(r,10))}
 assert.equal(waiting,true);await db.query('commit');assert.equal((await pending).rows[0].number,first.rows[0].number)
 assert.equal((await db.query('select count(*)::int n from private.bye_numbers where user_id=$1',[uid(8)])).rows[0].n,1)
 })
 await check('different-user concurrency unique',async()=>{const [a,b]=await Promise.all([claim(db,9),claim(other,10)]);assert.notEqual(a.rows[0].number,b.rows[0].number)})
 await check('rerun preserves data and sequence, repairs grants',async()=>{
 const rows=(await db.query('select * from private.bye_numbers order by number')).rows,seq=(await db.query('select * from private.bye_number_seq')).rows
 await db.query('grant all on private.bye_numbers to authenticated;grant execute on function public.claim_bye_number() to anon');await db.query(sql)
 assert.deepEqual((await db.query('select * from private.bye_numbers order by number')).rows,rows);assert.deepEqual((await db.query('select * from private.bye_number_seq')).rows,seq)
 await denied(()=>as(db,'anon',null,'select * from public.claim_bye_number()'));await denied(()=>as(db,'authenticated',uid(2),'select * from private.bye_numbers'))
 })
 await check('function owners, definer, search path and RLS',async()=>{
 const r=await db.query("select p.prosecdef,p.proconfig,pg_get_userbyid(p.proowner) owner from pg_proc p where p.oid in ('public.claim_bye_number()'::regprocedure,'public.bye_number_count()'::regprocedure)")
 assert.equal(r.rows.length,2);for(const p of r.rows){assert.equal(p.prosecdef,true);assert.equal(p.owner,'postgres');assert.deepEqual(p.proconfig,['search_path=""'])}
 assert.equal((await db.query("select relrowsecurity from pg_class where oid='private.bye_numbers'::regclass")).rows[0].relrowsecurity,true)
 })
 await check('RESTRICT blocks delete',()=>denied(()=>db.query('delete from auth.users where id=$1',[uid(2)]),'23503'))
 await check('scoped fixture cleanup allows delete',async()=>{await db.query('delete from private.bye_numbers where user_id=$1',[uid(2)]);await db.query('delete from auth.users where id=$1',[uid(2)])})
 await check('schema drift rejected',async()=>{await db.query('alter table private.bye_numbers drop constraint bye_numbers_number_check');await denied(()=>db.query(sql),'P0001');await db.query('rollback');await db.query('alter table private.bye_numbers add constraint bye_numbers_number_check check(number>0)');await db.query(sql)})
 console.log(`RESULT ${passed} passed, 0 failed; disposable local database only.`)
}finally{for(const c of clients)await c.end().catch(()=>{});if(started)await pg.stop();await rm(dir,{recursive:true,force:true})}
