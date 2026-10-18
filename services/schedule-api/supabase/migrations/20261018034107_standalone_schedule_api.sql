begin;
create schema bye_schedule;
revoke all on schema bye_schedule from public, anon, authenticated, service_role;
create table bye_schedule.state (
 term text primary key check(term='202670'), enabled boolean not null default false,
 catalog text, previous_catalog text, availability text, previous_availability text, previous_availability_catalog text,
 checked_at timestamptz, changed_at timestamptz, source_hash text, row_count integer,
 daily_date date, active_until timestamptz, renewed_at timestamptz,
 next_fetch timestamptz not null default '-infinity', lock_token uuid, lock_until timestamptz,
 failures integer not null default 0, metadata jsonb not null default '{}'
);
insert into bye_schedule.state(term) values('202670');
create table bye_schedule.catalogs(hash text primary key, created_at timestamptz not null default now(), courses jsonb not null, source_count integer not null);
create table bye_schedule.sections(catalog text references bye_schedule.catalogs on delete cascade, crn text, course_key text not null, body jsonb not null, primary key(catalog,crn));
create index sections_course on bye_schedule.sections(catalog,course_key);
create table bye_schedule.raw_rows(catalog text references bye_schedule.catalogs on delete cascade, ordinal integer, payload jsonb not null, primary key(catalog,ordinal));
create table bye_schedule.availability(crn text primary key, value jsonb, previous jsonb, evidence jsonb, previous_evidence jsonb, generation text, rollback_member boolean not null default false, changed_at timestamptz not null default now());
create table bye_schedule.staging(token uuid, kind text check(kind in ('courses','sections','availability','raw')), part integer check(part>=0 and part<1000), payload jsonb not null check(jsonb_typeof(payload)='array'), created_at timestamptz not null default now(), primary key(token,kind,part));
create table bye_schedule.events(id bigint generated always as identity primary key, at timestamptz not null default now(), kind text not null, details jsonb not null);
create table bye_schedule.limits(identity text primary key, minute timestamptz not null, count integer not null);

-- Private implementation. The sole gateway below is executable only by the
-- server role; clients never receive that credential or schema/table grants.
create function bye_schedule.command(op text, args jsonb) returns jsonb
language plpgsql security definer set search_path=pg_catalog,bye_schedule as $$
#variable_conflict use_variable
declare s bye_schedule.state; token uuid; item jsonb; meta jsonb; result jsonb; n integer;
 new_catalog text; new_availability text; expected integer; daily boolean; stale boolean;
 ident text; bucket timestamptz; counter integer; crns text[];
begin
 select * into strict s from bye_schedule.state where term='202670';
 if op='read' then
   if args->>'term' is not null and args->>'term'<>'202670' then return jsonb_build_object('error','UNSUPPORTED_TERM'); end if;
   ident:=args->>'identity';
   if ident is null or ident !~ '^[a-f0-9]{64}$' then raise exception 'Invalid rate identity'; end if;
   bucket:=date_trunc('minute',clock_timestamp());
   delete from bye_schedule.limits where minute<bucket-interval '1 minute';
   if not exists(select 1 from bye_schedule.limits where identity=ident) and (select count(*) from bye_schedule.limits)>=2000 then return '{"error":"RATE_LIMITED"}'; end if;
   insert into bye_schedule.limits values(ident,bucket,1) on conflict(identity) do update set minute=excluded.minute,count=case when limits.minute=excluded.minute then limits.count+1 else 1 end returning count into counter;
   if counter>120 then return '{"error":"RATE_LIMITED"}'; end if;
   update bye_schedule.state set active_until=now()+interval '10 minutes',renewed_at=now() where term=s.term and (renewed_at is null or renewed_at<=now()-interval '5 minutes');
   if s.catalog is null then return '{"error":"NOT_READY"}'; end if;
   stale:=s.checked_at is null or s.checked_at<now()-interval '15 minutes';
   meta:=jsonb_build_object('term',s.term,'catalogVersion',s.catalog,'availabilityVersion',s.availability,'sourceCheckedAt',s.checked_at,'availabilityChangedAt',s.changed_at,'stale',stale,'source', 'PCC published schedule','collectionTargetSeconds',300);
   if args->>'route'='terms' then result:=jsonb_build_array(jsonb_build_object('termCode',s.term,'name',coalesce(s.metadata->>'termName','Fall 2026')));
   elsif args->>'route'='manifest' then result:=jsonb_build_object('apiVersion','v1','catalogVersion',s.catalog,'availabilityVersion',s.availability,'sourceCheckedAt',s.checked_at,'availabilityChangedAt',s.changed_at,'stale',stale,'capabilities',jsonb_build_object('conditionalReads',true,'maxAvailabilityCrns',100,'suggestionLimit',20,'clientPollSeconds',60));
   elsif args->>'route' in ('catalog','courses') then
     select courses into result from bye_schedule.catalogs where hash=s.catalog;
     select jsonb_build_object('term',s.term,'catalogVersion',s.catalog,'catalogPublishedAt',created_at) into meta from bye_schedule.catalogs where hash=s.catalog;
   elsif args->>'route'='sections' then
     if not exists(select 1 from bye_schedule.sections where catalog=s.catalog and course_key=args->>'courseKey') then return '{"error":"NOT_FOUND"}'; end if;
     select coalesce(jsonb_agg(d.body||jsonb_build_object('availability',case when stale then null else a.value end) order by d.crn),'[]') into result from bye_schedule.sections d left join bye_schedule.availability a on a.crn=d.crn where d.catalog=s.catalog and d.course_key=args->>'courseKey';
   elsif args->>'route'='availability' then
     select array_agg(value) into crns from jsonb_array_elements_text(args->'crns');
     if coalesce(cardinality(crns),0) not between 1 and 100 or exists(select 1 from unnest(crns) c where c !~ '^[0-9]{5}$') then return '{"error":"INVALID_QUERY"}'; end if;
     if exists(select 1 from unnest(crns) c where not exists(select 1 from bye_schedule.sections where catalog=s.catalog and crn=c)) then return '{"error":"NOT_FOUND"}'; end if;
     select jsonb_agg(jsonb_build_object('crn',c,'availability',case when stale then null else a.value end) order by c) into result from (select distinct unnest(crns) c) x left join bye_schedule.availability a on a.crn=x.c;
   else return '{"error":"NOT_FOUND"}'; end if;
   return jsonb_build_object('data',result,'meta',meta);
 elsif op='state' then
   return to_jsonb(s)-'lock_token';
 elsif op='values' then
   return coalesce((select jsonb_agg(jsonb_build_object('crn',crn,'value',value)) from bye_schedule.availability),'[]');
 elsif op='bootstrap_source' then
   if s.catalog is not null then raise exception 'Already initialized'; end if;
   return (select jsonb_build_object('rows',jsonb_agg(r.payload order by r.ordinal),'retrievedAt',min(i.retrieved_at),'term',min(t.metadata::text)::jsonb) from pcc_schedule.terms t join pcc_schedule.import_runs i on i.id=t.active_import_id join pcc_schedule.source_rows r on r.import_id=i.id where t.term_code='202670');
 elsif op='claim' then
   select * into strict s from bye_schedule.state where term='202670' for update;
   if s.lock_until>now() then return '{"skipped":"LOCKED"}'; end if;
   if args->>'mode'='bootstrap' then
     if s.catalog is not null then return '{"skipped":"INITIALIZED"}'; end if;
   else
     if args->>'mode'='scheduled' and not s.enabled then return '{"skipped":"DISABLED"}'; end if;
     if s.next_fetch>now() then return '{"skipped":"COOLDOWN"}'; end if;
     daily:=s.daily_date is null or s.daily_date<(now()-interval '10 hours')::date;
     if args->>'mode'='scheduled' and not daily and coalesce(s.active_until,'-infinity')<=now() then return '{"skipped":"IDLE"}'; end if;
   end if;
   token:=gen_random_uuid();
   update bye_schedule.state set lock_token=token,lock_until=now()+interval '140 seconds',next_fetch=case when args->>'mode'='bootstrap' then next_fetch else now()+interval '5 minutes' end where term=s.term;
   return jsonb_build_object('token',token,'daily',coalesce(daily,false),'catalog',s.catalog,'availability',s.availability);
 elsif op='stage' then
   token:=(args->>'token')::uuid;
   if token is distinct from s.lock_token or s.lock_until<=now() then raise exception 'Expired lock'; end if;
   if pg_column_size(args)>2*1024*1024 or jsonb_array_length(args->'payload')>500 then raise exception 'Stage too large'; end if;
   insert into bye_schedule.staging(token,kind,part,payload) values(token,args->>'kind',(args->>'part')::integer,args->'payload') on conflict on constraint staging_pkey do update set payload=excluded.payload;
   return '{"staged":true}';
 elsif op='publish' then
   select * into strict s from bye_schedule.state where term='202670' for update;
   token:=(args->>'token')::uuid;
   if token is distinct from s.lock_token or s.lock_until<=now() then raise exception 'Expired lock'; end if;
   new_catalog:=args->>'catalogHash'; new_availability:=args->>'availabilityHash';
   if new_catalog !~ '^[a-f0-9]{64}$' or new_availability !~ '^[a-f0-9]{64}$' or args->>'sourceHash' !~ '^[a-f0-9]{64}$' then raise exception 'Invalid hashes'; end if;
   if (args->>'rowCount')::integer not between 1 and 25000 or (args->>'sectionCount')::integer<1 then raise exception 'Invalid source counts'; end if;
   if s.catalog is distinct from new_catalog then
     select count(*) into n from bye_schedule.staging st cross join lateral jsonb_array_elements(st.payload) e where st.token=token and st.kind='raw';
     if n<>(args->>'rowCount')::integer then raise exception 'Incomplete raw source'; end if;
     if exists(select 1 from bye_schedule.staging st cross join lateral jsonb_array_elements(st.payload) e where st.token=token and st.kind='raw' and (e->'payload'->>'termCode'<>'202670' or e->'payload'->>'crn' !~ '^[0-9]{5}$')) then raise exception 'Invalid source term or CRN'; end if;
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
     update bye_schedule.availability set previous=null,previous_evidence=null,rollback_member=false where rollback_member;
     for item in select e from bye_schedule.staging st cross join lateral jsonb_array_elements(st.payload) e where st.token=token and st.kind='availability' loop
       if item->>'crn' !~ '^[0-9]{5}$' or jsonb_typeof(item->'value') not in ('object','null') or jsonb_typeof(item->'evidence')<>'array' then raise exception 'Invalid availability'; end if;
       insert into bye_schedule.availability(crn,value,evidence,generation,rollback_member) values(item->>'crn',nullif(item->'value','null'::jsonb),item->'evidence',new_availability,true)
       on conflict(crn) do update set previous=availability.value,previous_evidence=availability.evidence,value=excluded.value,evidence=excluded.evidence,generation=new_availability,rollback_member=true,changed_at=now()
       where availability.value is distinct from excluded.value;
     end loop;
     if exists(select 1 from bye_schedule.sections d where d.catalog=new_catalog and not exists(select 1 from bye_schedule.availability a where a.crn=d.crn and a.value is not null)) then raise exception 'Incomplete availability'; end if;
     update bye_schedule.state set previous_availability=availability,previous_availability_catalog=s.catalog,availability=new_availability,changed_at=now() where term=s.term;
   end if;
   update bye_schedule.state set checked_at=(args->>'retrievedAt')::timestamptz,source_hash=args->>'sourceHash',row_count=(args->>'rowCount')::integer, failures=0, lock_token=null,lock_until=null,
     daily_date=case when coalesce((args->>'daily')::boolean,false) then (now()-interval '10 hours')::date else daily_date end,
     metadata=coalesce(args->'metadata',metadata) where term=s.term;
   insert into bye_schedule.events(kind,details) values('published',jsonb_build_object('catalogChanged',s.catalog is distinct from new_catalog,'availabilityChanged',s.availability is distinct from new_availability,'sourceHash',args->>'sourceHash','rowCount',args->'rowCount'));
   delete from bye_schedule.staging where staging.token=token;
   return jsonb_build_object('published',true,'catalogVersion',new_catalog,'availabilityVersion',new_availability);
 elsif op='fail' then
   if (args->>'token')::uuid is distinct from s.lock_token then return '{"ignored":true}'; end if;
   update bye_schedule.state set lock_token=null,lock_until=null,failures=failures+1,next_fetch=greatest(next_fetch,now()+make_interval(secs=>least(86400,greatest(case when failures>=2 then 1800 else 300*(2^failures)::integer end,coalesce((args->>'retrySeconds')::integer,0))))) where term=s.term;
   delete from bye_schedule.staging where staging.token=s.lock_token;
   insert into bye_schedule.events(kind,details) values('failed',jsonb_build_object('code',left(coalesce(args->>'code','SOURCE_UNAVAILABLE'),80)));
   return '{"retainedPrevious":true}';
 elsif op='enable' then
   update bye_schedule.state set enabled=coalesce((args->>'enabled')::boolean,false) where term=s.term;
   return jsonb_build_object('enabled',coalesce((args->>'enabled')::boolean,false));
 elsif op='rollback' then
   select * into strict s from bye_schedule.state where term='202670' for update;
   if s.lock_until>now() then raise exception 'Worker active'; end if;
   if s.previous_availability is null then raise exception 'No previous availability'; end if;
   update bye_schedule.availability set value=previous,previous=value,evidence=previous_evidence,previous_evidence=evidence,generation=s.previous_availability where rollback_member;
   update bye_schedule.state set catalog=s.previous_availability_catalog,previous_catalog=case when s.catalog is distinct from s.previous_availability_catalog then s.catalog else previous_catalog end,previous_availability_catalog=s.catalog,availability=s.previous_availability,previous_availability=s.availability,checked_at=null,enabled=false where term=s.term;
   return '{"rolledBack":true,"stale":true,"enabled":false}';
 elsif op='cleanup' then
   delete from bye_schedule.staging where created_at<now()-interval '30 minutes' and token is distinct from s.lock_token;
   delete from bye_schedule.events where at<now()-interval '7 days' or id in(select id from bye_schedule.events order by id desc offset 2500);
   delete from bye_schedule.limits where minute<now()-interval '2 minutes';
   delete from bye_schedule.catalogs where hash is distinct from s.catalog and hash is distinct from s.previous_catalog;
   delete from bye_schedule.availability a where not exists(select 1 from bye_schedule.sections d where d.crn=a.crn);
   return '{"cleaned":true}';
 else raise exception 'Unsupported operation'; end if;
end $$;
create function public.bye_schedule_backend(op text,args jsonb default '{}') returns jsonb
language sql security invoker set search_path=pg_catalog as $$select bye_schedule.command(op,args)$$;
revoke all on function bye_schedule.command(text,jsonb) from public,anon,authenticated;
revoke all on function public.bye_schedule_backend(text,jsonb) from public,anon,authenticated;
grant usage on schema bye_schedule to service_role;
grant execute on function bye_schedule.command(text,jsonb),public.bye_schedule_backend(text,jsonb) to service_role;
revoke all on all tables in schema bye_schedule from public,anon,authenticated,service_role;
revoke all on all sequences in schema bye_schedule from public,anon,authenticated,service_role;
do $$declare t text;begin foreach t in array array['state','catalogs','sections','raw_rows','availability','staging','events','limits'] loop execute format('alter table bye_schedule.%I enable row level security',t);end loop;end$$;
comment on schema bye_schedule is 'Private standalone schedule API read model. Server-only command gateway; no student review objects modified.';
commit;
