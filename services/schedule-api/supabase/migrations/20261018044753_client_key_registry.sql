begin;
create table bye_schedule.owners(user_id uuid primary key references auth.users(id), created_at timestamptz not null default now(), request_minute timestamptz, request_count integer not null default 0);
create table bye_schedule.client_keys(
 id uuid primary key, digest text not null unique check(digest ~ '^[a-f0-9]{64}$'),
 label text not null check(length(label) between 1 and 80), client_type text not null check(client_type in ('windows','mac','website','other')),
 mask text not null check(length(mask)<=40), created_at timestamptz not null default now(),
 status text not null default 'active' check(status in ('active','disabled','revoked')),
 retire_at timestamptz, rotated_from uuid, rotated_to uuid, last_used_at timestamptz,
 revoked_at timestamptz, revision integer not null default 1
);
create table bye_schedule.key_audit(id bigint generated always as identity primary key, at timestamptz not null default now(), actor uuid not null, action text not null, key_id uuid, details jsonb not null);
create table bye_schedule.key_receipts(actor uuid not null, request_id uuid not null, fingerprint text not null, result jsonb not null, at timestamptz not null default now(), primary key(actor,request_id));
create index on bye_schedule.key_audit(at);
create index on bye_schedule.key_receipts(at);
alter table bye_schedule.owners enable row level security;
alter table bye_schedule.client_keys enable row level security;
alter table bye_schedule.key_audit enable row level security;
alter table bye_schedule.key_receipts enable row level security;
revoke all on bye_schedule.owners,bye_schedule.client_keys,bye_schedule.key_audit,bye_schedule.key_receipts from public,anon,authenticated,service_role;
revoke all on all sequences in schema bye_schedule from public,anon,authenticated,service_role;

-- Deliberately separate from worker clock and never accepts a caller-supplied time.
create function bye_schedule.key_clock() returns timestamptz language sql volatile set search_path=pg_catalog as $$select clock_timestamp()$$;
revoke all on function bye_schedule.key_clock() from public,anon,authenticated,service_role;
create function bye_schedule.key_view(k bye_schedule.client_keys) returns jsonb language sql stable set search_path=pg_catalog as $$
 select to_jsonb(k)-'digest' || jsonb_build_object('effective_status',case when k.status='revoked' then 'revoked' when k.retire_at<=bye_schedule.key_clock() then 'expired' when k.status='disabled' then 'disabled' when k.retire_at is not null then 'retiring' else 'active' end)
$$;
revoke all on function bye_schedule.key_view(bye_schedule.client_keys) from public,anon,authenticated,service_role;

create function bye_schedule.manage_keys(action text,args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path=pg_catalog,bye_schedule as $$
#variable_conflict use_variable
declare actor uuid:=auth.uid(); k bye_schedule.client_keys; replacement bye_schedule.client_keys;
 result jsonb; saved bye_schedule.key_receipts; request_id uuid; fingerprint text; t timestamptz:=bye_schedule.key_clock(); deadline timestamptz; page integer;
begin
 if actor is null or not exists(select 1 from bye_schedule.owners where user_id=actor) then return '{"error":"FORBIDDEN"}'; end if;
 if pg_column_size(args)>8192 then return '{"error":"INVALID_QUERY"}'; end if;
 -- One bounded owner lock also protects the registry cap and cross-key rotation.
 perform pg_advisory_xact_lock(88421093);
 update bye_schedule.owners set request_count=case when request_minute=date_trunc('minute',t) then request_count+1 else 1 end, request_minute=date_trunc('minute',t) where user_id=actor;
 if (select request_count from bye_schedule.owners where user_id=actor)>240 then return '{"error":"RATE_LIMITED"}'; end if;
 delete from bye_schedule.key_receipts where at<t-interval '24 hours';
 delete from bye_schedule.key_audit where at<t-interval '90 days' or id in(select id from bye_schedule.key_audit order by id desc offset 2500);
 delete from bye_schedule.client_keys where revoked_at<t-interval '90 days';
 if action='session' then return jsonb_build_object('owner',actor); end if;
 if action in ('list','audit') then
   page:=coalesce((args->>'offset')::integer,0);
   if page<0 or page>1000000 then return '{"error":"INVALID_QUERY"}'; end if;
   if action='list' then
     select jsonb_build_object('items',coalesce(jsonb_agg(bye_schedule.key_view(x)),'[]'), 'offset',page,'limit',25,'total',(select count(*) from bye_schedule.client_keys)) into result from (select * from bye_schedule.client_keys order by created_at desc,id limit 25 offset page) x;
   else
     select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(x)),'[]'),'offset',page,'limit',25,'total',(select count(*) from bye_schedule.key_audit)) into result from (select * from bye_schedule.key_audit order by id desc limit 25 offset page) x;
   end if;
   return result;
 end if;
 if action not in ('create','rotate','extend','disable','enable','revoke') then return '{"error":"INVALID_QUERY"}'; end if;
 if args->>'requestedAt' is null or (args->>'requestedAt')::timestamptz<t-interval '24 hours' or (args->>'requestedAt')::timestamptz>t+interval '1 minute' then return '{"error":"REQUEST_EXPIRED"}'; end if;
 request_id:=(args->>'requestId')::uuid;
 if request_id is null then return '{"error":"INVALID_QUERY"}'; end if;
 fingerprint:=encode(sha256(convert_to(action || (args-'digest'-'newId'-'mask')::text,'UTF8')),'hex');
 select * into saved from bye_schedule.key_receipts r where r.actor=actor and r.request_id=request_id;
 if found then
   if saved.fingerprint<>fingerprint then return '{"error":"IDEMPOTENCY_CONFLICT"}'; end if;
   return saved.result || '{"replayed":true,"keyRecoverable":false}';
 end if;
 if (select count(*) from bye_schedule.key_receipts)>=2500 then return '{"error":"RATE_LIMITED"}'; end if;
 if action<>'create' then
   select * into k from bye_schedule.client_keys where id=(args->>'id')::uuid for update;
   if not found then return '{"error":"NOT_FOUND"}'; end if;
   if k.revision is distinct from (args->>'revision')::integer then return '{"error":"CONFLICT"}'; end if;
   if k.status='revoked' then return '{"error":"REVOKED"}'; end if;
 end if;
 if action in ('create','rotate') then
   if (select count(*) from bye_schedule.client_keys where status<>'revoked')>=100 then return '{"error":"REGISTRY_FULL"}'; end if;
   if action='rotate' and k.rotated_to is not null then return '{"error":"CONFLICT"}'; end if;
   if coalesce(args->>'label','') !~ '\S' or length(args->>'label')>80 or coalesce(args->>'clientType','') not in ('windows','mac','website','other') or coalesce(args->>'digest','') !~ '^[a-f0-9]{64}$' or args->>'newId' is null or args->>'mask' is null then return '{"error":"INVALID_QUERY"}'; end if;
   insert into bye_schedule.client_keys(id,digest,label,client_type,mask,created_at,rotated_from) values((args->>'newId')::uuid,args->>'digest',trim(args->>'label'),args->>'clientType',args->>'mask',t,case when action='rotate' then k.id end) returning * into replacement;
   if action='rotate' then
     update bye_schedule.client_keys set retire_at=t+interval '30 days', rotated_to=replacement.id,revision=revision+1 where id=k.id returning * into k;
   end if;
   result:=jsonb_build_object('key',bye_schedule.key_view(replacement),'previous',case when action='rotate' then bye_schedule.key_view(k) end);
 else
   if action='extend' then
     if k.retire_at is null then return '{"error":"NOT_RETIRING"}'; end if;
     if k.retire_at<=t and coalesce((args->>'confirmRestore')::boolean,false) is not true then return '{"error":"CONFIRM_RESTORE"}'; end if;
     deadline:=coalesce((args->>'retireAt')::timestamptz,greatest(k.retire_at,t)+interval '30 days');
     if deadline<=greatest(k.retire_at,t) or deadline>t+interval '3660 days' then return '{"error":"INVALID_QUERY"}'; end if;
     update bye_schedule.client_keys set retire_at=deadline,revision=revision+1 where id=k.id returning * into k;
   elsif action='revoke' then
     if coalesce((args->>'confirm')::boolean,false) is not true then return '{"error":"CONFIRM_REVOKE"}'; end if;
     update bye_schedule.client_keys set status='revoked',revoked_at=t,revision=revision+1 where id=k.id returning * into k;
   else
     update bye_schedule.client_keys set status=case when action='disable' then 'disabled' else 'active' end,revision=revision+1 where id=k.id returning * into k;
   end if;
   result:=jsonb_build_object('key',bye_schedule.key_view(k));
 end if;
 insert into bye_schedule.key_receipts values(actor,request_id,fingerprint,result,t);
 insert into bye_schedule.key_audit(at,actor,action,key_id,details) values(t,actor,action,coalesce(replacement.id,k.id),result);
 delete from bye_schedule.key_audit where id in(select id from bye_schedule.key_audit order by id desc offset 2500);
 return result || '{"replayed":false}';
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow or numeric_value_out_of_range then return '{"error":"INVALID_QUERY"}';
end $$;
revoke all on function bye_schedule.manage_keys(text,jsonb) from public,anon,service_role;
grant usage on schema bye_schedule to authenticated;
grant execute on function bye_schedule.manage_keys(text,jsonb) to authenticated;
create function public.bye_key_management(action text,args jsonb default '{}') returns jsonb language sql security invoker set search_path=pg_catalog as $$select bye_schedule.manage_keys(action,args)$$;
revoke all on function public.bye_key_management(text,jsonb) from public,anon,service_role;
grant execute on function public.bye_key_management(text,jsonb) to authenticated;

-- Keep the existing schedule transaction intact, but put registry auth in front.
-- Verified against the deployed v4 key digest before this migration. Public key
-- material is not stored; registration and auth switch share this transaction.
insert into bye_schedule.client_keys(id,digest,label,client_type,mask) values(gen_random_uuid(),'9e2d5a9b55a2399204d2b2946290a96f062b7c6f4f072caedca6a2b359b0bcc7','Existing BYE key','other','existing …NYl');
alter function bye_schedule.command(text,jsonb) rename to schedule_command;
revoke all on function bye_schedule.schedule_command(text,jsonb) from public,anon,authenticated,service_role;
create function bye_schedule.command(op text,args jsonb default '{}') returns jsonb
language plpgsql security definer set search_path=pg_catalog,bye_schedule as $$
#variable_conflict use_variable
declare k bye_schedule.client_keys; t timestamptz:=bye_schedule.key_clock(); result jsonb; uid uuid;
begin
 if op='read' then
   select * into k from bye_schedule.client_keys where digest=args->>'keyDigest';
   if not found or k.status<>'active' or k.retire_at<=t then return '{"error":"UNAUTHORIZED"}'; end if;
   result:=bye_schedule.schedule_command(op,case when args->>'route'='openapi' then jsonb_set(args,'{route}','"terms"') else args end);
   if not (result ? 'error') then
     update bye_schedule.client_keys set last_used_at=t where id=k.id and (last_used_at is null or last_used_at<=t-interval '5 minutes');
   end if;
   return result;
 elsif op in ('owner-add','owner-remove') then
   uid:=(args->>'userId')::uuid;
   perform pg_advisory_xact_lock(88421093);
   if op='owner-add' then
     if not exists(select 1 from auth.users where id=uid and email_confirmed_at is not null and deleted_at is null) then return '{"error":"CONFIRMED_USER_REQUIRED"}'; end if;
     if (select count(*) from bye_schedule.owners)>=20 then return '{"error":"OWNER_LIMIT"}'; end if;
     insert into bye_schedule.owners(user_id) values(uid) on conflict do nothing;
   else
     if (select count(*) from bye_schedule.owners)<=1 then return '{"error":"LAST_OWNER"}'; end if;
     delete from bye_schedule.owners where user_id=uid;
   end if;
   insert into bye_schedule.key_audit(actor,action,details) values(uid,op,jsonb_build_object('machine',true));
   return jsonb_build_object('userId',uid,'action',op);
 elsif op='register-key' then
   perform pg_advisory_xact_lock(88421093);
   if (select count(*) from bye_schedule.client_keys where status<>'revoked')>=100 then return '{"error":"REGISTRY_FULL"}'; end if;
   -- Migration-only registration cannot restore disabled/revoked records.
   insert into bye_schedule.client_keys(id,digest,label,client_type,mask) values(gen_random_uuid(),args->>'digest','Existing BYE key','other','existing …') on conflict(digest) do nothing;
   return '{"registered":true}';
 elsif op='cleanup' then
   perform pg_advisory_xact_lock(88421093);
   delete from bye_schedule.key_receipts where at<t-interval '24 hours';
   delete from bye_schedule.key_audit where at<t-interval '90 days' or id in(select id from bye_schedule.key_audit order by id desc offset 2500);
   delete from bye_schedule.client_keys where revoked_at<t-interval '90 days';
 end if;
 return bye_schedule.schedule_command(op,args);
end $$;
revoke all on function bye_schedule.command(text,jsonb) from public,anon,authenticated;
grant execute on function bye_schedule.command(text,jsonb) to service_role;
commit;
