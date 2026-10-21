// Requires an already migrated, disposable local PostgreSQL database. Never uses
// production credentials, creates roles, or mutates a non-test database.
import {spawn} from 'node:child_process';
import assert from 'node:assert/strict';
const address=process.env.BYE_TEST_PG_URL;
if(!address){console.error('Set BYE_TEST_PG_URL to a disposable loopback database named bye_schedule_test.');process.exit(2)}
const url=new URL(address);
if(!['localhost','127.0.0.1','[::1]'].includes(url.hostname)||url.pathname!=='/bye_schedule_test')throw new Error('Only loopback /bye_schedule_test is permitted');
const env={...process.env,PGHOST:url.hostname.replace(/[\[\]]/g,''),PGPORT:url.port||'5432',PGDATABASE:'bye_schedule_test',PGUSER:decodeURIComponent(url.username),PGPASSWORD:decodeURIComponent(url.password)};
delete env.BYE_TEST_PG_URL;
const psql=(sql)=>new Promise((resolve,reject)=>{
  const child=spawn(process.env.BYE_TEST_PSQL||'psql',['--no-psqlrc','--tuples-only','--no-align','--set=ON_ERROR_STOP=1'],{env,windowsHide:true,stdio:['pipe','pipe','pipe']});let output='',errors='';
  child.stdout.on('data',chunk=>{output+=chunk});child.stderr.on('data',chunk=>{errors+=chunk});child.on('error',reject);child.on('close',code=>code===0?resolve(output.trim()):reject(new Error('Local PostgreSQL test failed; inspect the disposable database.')));child.stdin.end(sql);
});
await psql("do $$begin if current_database()<>'bye_schedule_test' or to_regclass('public.reviews') is not null then raise exception 'Unsafe database';end if;end$$;update bye_schedule.state set enabled=true,listed=true,lock_token=null,lock_until=null,next_fetch='-infinity' where term='202670';update bye_schedule.collection_control set lock_token=null,lock_until=null,next_fetch='-infinity';");
const query="select public.bye_schedule_backend('claim','{\"mode\":\"owner\",\"term\":\"202670\"}')::text;";
const responses=await Promise.all(Array.from({length:12},()=>psql(query)));
assert.equal(responses.filter(value=>JSON.parse(value).token).length,1);
assert.equal(responses.filter(value=>['LOCKED','COOLDOWN'].includes(JSON.parse(value).skipped)).length,11);
console.log('PASS: twelve independent PostgreSQL sessions acquire exactly one shared collection lease');
