begin;
alter table bye_schedule.state drop constraint state_term_check;
alter table bye_schedule.state add constraint state_term_check check(term ~ '^[0-9]{6}$');
alter table bye_schedule.state add column listed boolean not null default true,
 add column official_start date, add column official_end date, add column date_reference text,
 add constraint verified_term_dates check((official_start is null and official_end is null and date_reference is null) or (official_start is not null and official_end is not null and official_start<=official_end and length(date_reference)>0));
alter table bye_schedule.availability add column term text not null default '202670' references bye_schedule.state(term);
alter table bye_schedule.availability alter column term drop default;
alter table bye_schedule.availability drop constraint availability_pkey;
alter table bye_schedule.availability add primary key(term,crn);
create table bye_schedule.collection_control(id integer primary key check(id=1), next_fetch timestamptz not null default '-infinity',lock_token uuid,lock_until timestamptz,discovery_checked_at timestamptz,discovery_next_fetch timestamptz not null default '-infinity',failures integer not null default 0);
insert into bye_schedule.collection_control(id,next_fetch,lock_token,lock_until) select 1,next_fetch,lock_token,lock_until from bye_schedule.state where term='202670';
alter table bye_schedule.collection_control enable row level security;
revoke all on bye_schedule.collection_control from public,anon,authenticated,service_role;
create index state_due on bye_schedule.state(next_fetch) where enabled and listed;
create or replace function bye_schedule.schedule_command(op text, args jsonb) returns jsonb
language plpgsql security definer set search_path=pg_catalog,bye_schedule as $$
#variable_conflict use_variable
declare s bye_schedule.state; token uuid; item jsonb; meta jsonb; result jsonb; n integer;
 new_catalog text; new_availability text; expected integer; daily boolean; stale boolean;
 school_date date:=(now() at time zone 'America/Los_Angeles')::date; requested text:=coalesce(args->>'term','202670'); g bye_schedule.collection_control; interval_seconds integer; ident text; bucket timestamptz; counter integer; crns text[];
begin
 if op in ('discover-claim','discover-publish','discover-fail','claim','publish','fail','rollback','enable') then
   select * into strict g from bye_schedule.collection_control where id=1 for update;
 end if;
 if op='discover-claim' then
   if g.discovery_next_fetch>now() then return '{"skipped":"DISCOVERY_BACKOFF"}'; end if;
   if g.discovery_checked_at > now()-interval '1 day' then return '{"skipped":"DISCOVERED"}'; end if;
   if g.lock_until>now() or g.next_fetch>now() then return '{"skipped":"COOLDOWN"}'; end if;
   token:=gen_random_uuid();
   update bye_schedule.collection_control set lock_token=token,lock_until=now()+interval '140 seconds',next_fetch=now()+interval '5 minutes' where id=1;
   return jsonb_build_object('token',token);
 elsif op='discover-publish' then
   if g.lock_token is null or (args->>'token')::uuid is distinct from g.lock_token or g.lock_until<=now() then raise exception 'Expired discovery lock'; end if;
   if jsonb_typeof(args->'terms') is distinct from 'array' or jsonb_array_length(args->'terms') not between 1 and 32 then raise exception 'Invalid discovery'; end if;
   if exists(select 1 from jsonb_array_elements(args->'terms') t where coalesce(t->>'termCode','') !~ '^[0-9]{6}$' or coalesce(t->>'termName','')='' or t->>'termDisplayControl' is distinct from 'Y') then raise exception 'Invalid discovery'; end if;
   if (select count(distinct t->>'termCode') from jsonb_array_elements(args->'terms') t)<>jsonb_array_length(args->'terms') then raise exception 'Duplicate term'; end if;
   update bye_schedule.state set listed=false where not exists(select 1 from jsonb_array_elements(args->'terms') t where t->>'termCode'=state.term);
   for item in select t from jsonb_array_elements(args->'terms') t loop
     -- Only the published source selects semesters; no synthesized season codes.
     -- Previously imported terms are retained even when older or no longer listed.
     if left(item->>'termCode',4)::integer>=extract(year from school_date) or exists(select 1 from bye_schedule.state where term=item->>'termCode') then
       insert into bye_schedule.state(term,enabled,metadata,listed) values(item->>'termCode',true,item,true)
       on conflict(term) do update set metadata=excluded.metadata,listed=true;
     end if;
   end loop;
   update bye_schedule.collection_control set discovery_checked_at=now(),discovery_next_fetch='-infinity',lock_token=null,lock_until=null,failures=0 where id=1;
   return '{"discovered":true}';
 elsif op='discover-fail' then
   if (args->>'token')::uuid is distinct from g.lock_token then return '{"ignored":true}'; end if;
   update bye_schedule.collection_control set lock_token=null,lock_until=null,failures=failures+1,discovery_next_fetch=now()+make_interval(secs=>greatest(1800,least(86400,coalesce((args->>'retrySeconds')::integer,0)))),next_fetch=greatest(next_fetch,now()+make_interval(secs=>least(86400,greatest(0,coalesce((args->>'retrySeconds')::integer,0))))) where id=1;
   insert into bye_schedule.events(kind,details) values('discovery_failed',jsonb_build_object('code',args->>'code'));
   return '{"previousRetained":true}';
 elsif op='claim' and args->>'mode'='scheduled' and args->>'term' is null then
   select term into requested from bye_schedule.state where enabled and listed and next_fetch<=now() and (official_end is null or official_end>=school_date)
   order by next_fetch,checked_at nulls first,term limit 1;
   if requested is null then return '{"skipped":"IDLE"}'; end if;
 end if;
 select * into s from bye_schedule.state where term=requested;
 if not found then return '{"error":"UNSUPPORTED_TERM"}'; end if;
 interval_seconds:=case when s.official_start is not null and school_date>=s.official_start+30 then 1800 else 300 end;
 if op<>'read' and coalesce(s.active_until,'-infinity')<=now() then
   interval_seconds:=case when s.official_start is not null and school_date>=s.official_start+30 then 86400 else 1800 end;
 end if;

 if op='read' then
   ident:=args->>'identity';
   if ident is null or ident !~ '^[a-f0-9]{64}$' then raise exception 'Invalid rate identity'; end if;
   bucket:=date_trunc('minute',clock_timestamp());
   delete from bye_schedule.limits where minute<bucket-interval '1 minute';
   if not exists(select 1 from bye_schedule.limits where identity=ident) and (select count(*) from bye_schedule.limits)>=2000 then return '{"error":"RATE_LIMITED"}'; end if;
   insert into bye_schedule.limits values(ident,bucket,1) on conflict(identity) do update set minute=excluded.minute,count=case when limits.minute=excluded.minute then limits.count+1 else 1 end returning count into counter;
   if counter>120 then return '{"error":"RATE_LIMITED"}'; end if;
   update bye_schedule.state set active_until=now()+interval '10 minutes',renewed_at=now(),next_fetch=case when coalesce(active_until,'-infinity')<=now() and failures=0 then least(next_fetch,now()) else next_fetch end where term=s.term and (renewed_at is null or renewed_at<=now()-interval '5 minutes');
   if s.catalog is null and args->>'route'<>'terms' then return '{"error":"NOT_READY"}'; end if;
   stale:=not s.listed or s.checked_at is null or s.checked_at<=now()-interval '15 minutes';
   meta:=jsonb_build_object('term',s.term,'catalogVersion',s.catalog,'availabilityVersion',s.availability,'sourceCheckedAt',s.checked_at,'availabilityChangedAt',s.changed_at,'stale',stale,'source', 'PCC published schedule','collectionTargetSeconds',300,'refreshPolicy',jsonb_build_object('targetSeconds',interval_seconds,'aggregateMinimumSeconds',300,'nextEligibleAt',(select next_fetch from bye_schedule.state where term=s.term),'published',s.listed,'datesVerified',s.date_reference is not null));
   if args->>'route'='terms' then select coalesce(jsonb_agg(jsonb_build_object('termCode',t.term,'name',t.metadata->>'termName','published',t.listed) order by t.term desc),'[]') into result from bye_schedule.state t where t.catalog is not null;
   elsif args->>'route'='manifest' then result:=jsonb_build_object('apiVersion','v1','catalogVersion',s.catalog,'availabilityVersion',s.availability,'sourceCheckedAt',s.checked_at,'availabilityChangedAt',s.changed_at,'stale',stale,'capabilities',jsonb_build_object('conditionalReads',true,'maxAvailabilityCrns',100,'suggestionLimit',20,'clientPollSeconds',60));
   elsif args->>'route' in ('catalog','courses') then
     select courses into result from bye_schedule.catalogs where hash=s.catalog;
     select jsonb_build_object('term',s.term,'catalogVersion',s.catalog,'catalogPublishedAt',created_at) into meta from bye_schedule.catalogs where hash=s.catalog;
   elsif args->>'route'='sections' then
     if not exists(select 1 from bye_schedule.sections where catalog=s.catalog and course_key=args->>'courseKey') then return '{"error":"NOT_FOUND"}'; end if;
     select coalesce(jsonb_agg(d.body||jsonb_build_object('availability',case when stale then null else a.value end) order by d.crn),'[]') into result from bye_schedule.sections d left join bye_schedule.availability a on a.term=s.term and a.crn=d.crn where d.catalog=s.catalog and d.course_key=args->>'courseKey';
   elsif args->>'route'='availability' then
     select array_agg(value) into crns from jsonb_array_elements_text(args->'crns');
     if coalesce(cardinality(crns),0) not between 1 and 100 or exists(select 1 from unnest(crns) c where c !~ '^[0-9]{5}$') then return '{"error":"INVALID_QUERY"}'; end if;
     if exists(select 1 from unnest(crns) c where not exists(select 1 from bye_schedule.sections where catalog=s.catalog and crn=c)) then return '{"error":"NOT_FOUND"}'; end if;
     select jsonb_agg(jsonb_build_object('crn',c,'availability',case when stale then null else a.value end) order by c) into result from (select distinct unnest(crns) c) x left join bye_schedule.availability a on a.term=s.term and a.crn=x.c;
   else return '{"error":"NOT_FOUND"}'; end if;
   return jsonb_build_object('data',result,'meta',meta);
 elsif op='term-dates' then
   if coalesce(args->>'reference','') !~ '^https://([a-zA-Z0-9-]+\.)*pasadena\.edu/' then raise exception 'Official calendar reference required'; end if;
   if coalesce(args->>'startDate','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or coalesce(args->>'endDate','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Explicit calendar dates required'; end if;
   update bye_schedule.state set official_start=(args->>'startDate')::date,official_end=(args->>'endDate')::date,date_reference=args->>'reference' where term=s.term;
   return '{"configured":true}';
 elsif op='state' then
   return to_jsonb(s)-'lock_token';
 elsif op='values' then
   return coalesce((select jsonb_agg(jsonb_build_object('crn',crn,'value',value)) from bye_schedule.availability where term=s.term),'[]');
 elsif op='bootstrap_source' then
   if s.catalog is not null then raise exception 'Already initialized'; end if;
   return (select jsonb_build_object('rows',jsonb_agg(r.payload order by r.ordinal),'retrievedAt',min(i.retrieved_at),'term',min(t.metadata::text)::jsonb) from pcc_schedule.terms t join pcc_schedule.import_runs i on i.id=t.active_import_id join pcc_schedule.source_rows r on r.import_id=i.id where t.term_code='202670');
 elsif op='claim' then
   select * into strict s from bye_schedule.state where term=requested for update;
   if g.lock_until>now() then return '{"skipped":"LOCKED"}'; end if;
   if s.lock_token is not null and s.lock_until<=now() then
     update bye_schedule.state set lock_token=null,lock_until=null,failures=failures+1,next_fetch=greatest(next_fetch,now()+case when failures>=2 then interval '30 minutes' else interval '5 minutes' end) where term=s.term;
     update bye_schedule.collection_control set lock_token=null,lock_until=null,next_fetch=greatest(next_fetch,now()+interval '5 minutes') where id=1;
     insert into bye_schedule.events(kind,details) values('worker_expired',jsonb_build_object('term',s.term));
     return '{"skipped":"RECOVERED_EXPIRED_WORKER"}';
   end if;
   if s.lock_until>now() then return '{"skipped":"LOCKED"}'; end if;
   if args->>'mode'='bootstrap' then
     if s.catalog is not null then return '{"skipped":"INITIALIZED"}'; end if;
   else
     if args->>'mode'='scheduled' and not s.enabled then return '{"skipped":"DISABLED"}'; end if;
     if g.next_fetch>now() or s.next_fetch>now() then return '{"skipped":"COOLDOWN"}'; end if;
     daily:=s.daily_date is null or s.daily_date<(now()-interval '10 hours')::date;
     if not s.listed or (s.official_end is not null and s.official_end<school_date) then return '{"skipped":"IDLE"}'; end if;
   end if;
   token:=gen_random_uuid();
   update bye_schedule.state set lock_token=token,lock_until=now()+interval '140 seconds',next_fetch=case when args->>'mode'='bootstrap' then next_fetch else now()+interval '5 minutes' end where term=s.term;
   update bye_schedule.collection_control set lock_token=token,lock_until=now()+interval '140 seconds',next_fetch=case when args->>'mode'='bootstrap' then next_fetch else now()+interval '5 minutes' end where id=1;
   return jsonb_build_object('term',s.term,'metadata',s.metadata,'token',token,'daily',coalesce(daily,false),'catalog',s.catalog,'availability',s.availability);
 elsif op='stage' then
   token:=(args->>'token')::uuid;
   if token is null or s.lock_token is null or token is distinct from s.lock_token or s.lock_until<=now() then raise exception 'Expired lock'; end if;
   if pg_column_size(args)>2*1024*1024 or jsonb_array_length(args->'payload')>500 then raise exception 'Stage too large'; end if;
   insert into bye_schedule.staging(token,kind,part,payload) values(token,args->>'kind',(args->>'part')::integer,args->'payload') on conflict on constraint staging_pkey do update set payload=excluded.payload;
   return '{"staged":true}';
 elsif op='publish' then
   select * into strict s from bye_schedule.state where term=requested for update;
   token:=(args->>'token')::uuid;
   if token is null or s.lock_token is null or token is distinct from s.lock_token or s.lock_until<=now() then raise exception 'Expired lock'; end if;
   new_catalog:=args->>'catalogHash'; new_availability:=args->>'availabilityHash';
   if args->>'retrievedAt' is null or (args->>'retrievedAt')::timestamptz>now()+interval '1 minute' or (args->>'retrievedAt')::timestamptz<s.checked_at then raise exception 'Stale or future timestamp'; end if;
   if new_catalog !~ '^[a-f0-9]{64}$' or new_availability !~ '^[a-f0-9]{64}$' or args->>'sourceHash' !~ '^[a-f0-9]{64}$' then raise exception 'Invalid hashes'; end if;
   if (args->>'rowCount')::integer not between 1 and 25000 or (args->>'sectionCount')::integer<1 then raise exception 'Invalid source counts'; end if;
   if s.catalog is distinct from new_catalog then
     select count(*) into n from bye_schedule.staging st cross join lateral jsonb_array_elements(st.payload) e where st.token=token and st.kind='raw';
     if n<>(args->>'rowCount')::integer then raise exception 'Incomplete raw source'; end if;
     if exists(select 1 from bye_schedule.staging st cross join lateral jsonb_array_elements(st.payload) e where st.token=token and st.kind='raw' and ((e->'payload'->>'termCode') is distinct from s.term or coalesce(e->'payload'->>'crn','') !~ '^[0-9]{5}$')) then raise exception 'Invalid source term or CRN'; end if;
     select count(*) into n from bye_schedule.staging st cross join lateral jsonb_array_elements(st.payload) e where st.token=token and st.kind='sections';
     if n<>(args->>'sectionCount')::integer then raise exception 'Incomplete definitions'; end if;
     insert into bye_schedule.catalogs(hash,courses,source_count) select new_catalog, jsonb_agg(e order by e->>'key'),(args->>'rowCount')::integer from bye_schedule.staging st cross join lateral jsonb_array_elements(st.payload) e where st.token=token and st.kind='courses' on conflict(hash) do nothing;
     insert into bye_schedule.sections select new_catalog,e->>'crn',e->>'courseKey',e->'body' from bye_schedule.staging st cross join lateral jsonb_array_elements(st.payload) e where st.token=token and st.kind='sections' on conflict do nothing;
     insert into bye_schedule.raw_rows select new_catalog,(e->>'ordinal')::integer,e->'payload' from bye_schedule.staging st cross join lateral jsonb_array_elements(st.payload) e where st.token=token and st.kind='raw' on conflict do nothing;
     if exists(select 1 from bye_schedule.raw_rows r where catalog=new_catalog and not exists(select 1 from bye_schedule.sections d where d.catalog=new_catalog and d.crn=r.payload->>'crn' and d.course_key=(r.payload->>'subjCode')||' '||(r.payload->>'courseNumbDisplay'))) then raise exception 'Source reconciliation failed'; end if;
     update bye_schedule.state set previous_catalog=catalog,catalog=new_catalog where term=s.term;
   end if;
   if s.availability is distinct from new_availability then
     -- Only rows from the previous change generation carry rollback evidence.
     update bye_schedule.availability set previous=null,previous_evidence=null,rollback_member=false where term=s.term and rollback_member;
     for item in select e from bye_schedule.staging st cross join lateral jsonb_array_elements(st.payload) e where st.token=token and st.kind='availability' loop
       if item->>'crn' !~ '^[0-9]{5}$' or jsonb_typeof(item->'value') not in ('object','null') or jsonb_typeof(item->'evidence')<>'array' then raise exception 'Invalid availability'; end if;
       insert into bye_schedule.availability(term,crn,value,evidence,generation,rollback_member) values(s.term,item->>'crn',nullif(item->'value','null'::jsonb),item->'evidence',new_availability,true)
       on conflict(term,crn) do update set previous=availability.value,previous_evidence=availability.evidence,value=excluded.value,evidence=excluded.evidence,generation=new_availability,rollback_member=true,changed_at=now()
       where availability.value is distinct from excluded.value;
     end loop;
     if exists(select 1 from bye_schedule.sections d where d.catalog=new_catalog and not exists(select 1 from bye_schedule.availability a where a.term=s.term and a.crn=d.crn and a.value is not null)) then raise exception 'Incomplete availability'; end if;
     update bye_schedule.state set previous_availability=availability,previous_availability_catalog=s.catalog,availability=new_availability,changed_at=now() where term=s.term;
   end if;
   update bye_schedule.state set checked_at=(args->>'retrievedAt')::timestamptz,source_hash=args->>'sourceHash',row_count=(args->>'rowCount')::integer, failures=0, lock_token=null,lock_until=null,
     daily_date=case when coalesce((args->>'daily')::boolean,false) then (now()-interval '10 hours')::date else daily_date end,
     metadata=coalesce(args->'metadata',metadata), next_fetch=now()+make_interval(secs=>interval_seconds) where term=s.term;
   update bye_schedule.collection_control set lock_token=null,lock_until=null where id=1 and lock_token=token;
   insert into bye_schedule.events(kind,details) values('published',jsonb_build_object('term',s.term,'catalogChanged',s.catalog is distinct from new_catalog,'availabilityChanged',s.availability is distinct from new_availability,'sourceHash',args->>'sourceHash','rowCount',args->'rowCount'));
   delete from bye_schedule.staging where staging.token=token;
   return jsonb_build_object('published',true,'catalogVersion',new_catalog,'availabilityVersion',new_availability);
 elsif op='fail' then
   if (args->>'token')::uuid is distinct from s.lock_token then return '{"ignored":true}'; end if;
   update bye_schedule.state set lock_token=null,lock_until=null,failures=failures+1,next_fetch=greatest(next_fetch,now()+make_interval(secs=>least(86400,greatest(case when failures>=2 then 1800 else 300*(2^failures)::integer end,coalesce((args->>'retrySeconds')::integer,0))))) where term=s.term;
   update bye_schedule.collection_control set lock_token=null,lock_until=null,next_fetch=greatest(next_fetch,now()+make_interval(secs=>least(86400,greatest(0,coalesce((args->>'retrySeconds')::integer,0))))) where id=1 and lock_token=s.lock_token;
   delete from bye_schedule.staging where staging.token=s.lock_token;
   insert into bye_schedule.events(kind,details) values('failed',jsonb_build_object('term',s.term,'sourceStatus',args->'sourceStatus','code',left(coalesce(args->>'code','SOURCE_UNAVAILABLE'),80)));
   return '{"retainedPrevious":true}';
 elsif op='enable' then
   update bye_schedule.state set enabled=coalesce((args->>'enabled')::boolean,false) where term=s.term;
   return jsonb_build_object('enabled',coalesce((args->>'enabled')::boolean,false));
 elsif op='rollback' then
   select * into strict s from bye_schedule.state where term=requested for update;
   if s.lock_until>now() then raise exception 'Worker active'; end if;
   if args->>'target'='catalog' then
     if s.previous_catalog is null then raise exception 'No previous catalog'; end if;
     update bye_schedule.state set catalog=s.previous_catalog,previous_catalog=s.catalog,checked_at=null,enabled=false where term=s.term;
   else
     if s.previous_availability is null then raise exception 'No previous availability'; end if;
     update bye_schedule.availability set value=previous,previous=value,evidence=previous_evidence,previous_evidence=evidence,generation=s.previous_availability where term=s.term and rollback_member;
     update bye_schedule.state set availability=s.previous_availability,previous_availability=s.availability,checked_at=null,enabled=false where term=s.term;
   end if;
   return jsonb_build_object('rolledBack',true,'stale',true,'enabled',false,'target',coalesce(args->>'target','availability'));
 elsif op='cleanup' then
   if to_regclass('cron.job_run_details') is not null then
     execute $history$delete from cron.job_run_details where jobid in(select jobid from cron.job where jobname='bye-schedule-sync') and end_time is not null and (end_time<now()-interval '7 days' or runid in(select runid from cron.job_run_details where jobid in(select jobid from cron.job where jobname='bye-schedule-sync') and end_time is not null order by runid desc offset 2500))$history$;
   end if;

   delete from bye_schedule.staging where created_at<now()-interval '30 minutes' and not exists(select 1 from bye_schedule.state x where x.lock_token=staging.token and x.lock_until>now());
   delete from bye_schedule.events where at<now()-interval '7 days' or id in(select id from bye_schedule.events order by id desc offset 2500);
   delete from bye_schedule.limits where minute<now()-interval '2 minutes';
   delete from bye_schedule.catalogs where not exists(select 1 from bye_schedule.state x where hash=x.catalog or hash=x.previous_catalog);
   delete from bye_schedule.availability a where not exists(select 1 from bye_schedule.sections d join bye_schedule.state x on x.catalog=d.catalog or x.previous_catalog=d.catalog where x.term=a.term and d.crn=a.crn);
   return '{"cleaned":true}';
 else raise exception 'Unsupported operation'; end if;
end $$;

revoke all on function bye_schedule.schedule_command(text,jsonb) from public,anon,authenticated,service_role;
commit;
