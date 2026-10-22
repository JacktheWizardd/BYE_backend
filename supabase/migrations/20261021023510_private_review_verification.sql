-- PREPARE ONLY. Requires existing schema.sql, 002, 003, 006. No hosted execution authorized.
-- The separate cutover migration replaces foreign keys and disables legacy writes.
begin;
create role bye_review_owner nologin nosuperuser nocreatedb nocreaterole noinherit nobypassrls;
create role bye_review_gateway login nosuperuser nocreatedb nocreaterole noinherit nobypassrls;
-- Set the gateway password through an approved secure provisioning operation, never in this file.
grant bye_review_owner to postgres;
create schema review_private authorization bye_review_owner;
revoke all on schema review_private from public, anon, authenticated;
grant usage on schema review_private to bye_review_gateway;
alter default privileges for role bye_review_owner in schema review_private revoke execute on functions from public;

create table review_private.config (
  singleton boolean primary key default true check (singleton),
  key_fingerprint text check (key_fingerprint ~ '^[0-9a-f]{64}$'),
  cutover_at timestamptz,
  ready boolean not null default false
);
insert into review_private.config(singleton) values(true);
create table review_private.identities (
  id uuid primary key default gen_random_uuid(),
  mailbox text unique check (mailbox ~ '^[0-9a-f]{64}$'),
  verified_at timestamptz,
  legacy_updated_at timestamptz,
  banned_at timestamptz
);
-- NULL mailbox preserves historical ineligible authors without granting a new sign-in.
create table review_private.challenges (
  digest text primary key check (digest ~ '^[0-9a-f]{64}$'),
  mailbox text not null unique check (mailbox ~ '^[0-9a-f]{64}$'),
  code_mac text not null check (code_mac ~ '^[0-9a-f]{64}$'),
  attempts smallint not null default 0 check (attempts between 0 and 5),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default clock_timestamp()+interval '10 minutes'
);
create table review_private.sessions (
  digest text primary key check (digest ~ '^[0-9a-f]{64}$'),
  identity_id uuid not null references review_private.identities(id),
  expires_at timestamptz not null default clock_timestamp()+interval '1 hour'
);
create index sessions_identity on review_private.sessions(identity_id);
create index sessions_expiry on review_private.sessions(expires_at);
create index challenges_expiry on review_private.challenges(expires_at);
create table review_private.rate_limits (
  bucket text primary key,
  attempts integer not null,
  expires_at timestamptz not null
);
create index rates_expiry on review_private.rate_limits(expires_at);
create table review_private.moderation_audit (
  id bigint generated always as identity primary key,
  identity_id uuid not null references review_private.identities(id),
  action text not null check (action in ('ban','unban')),
  reason text not null check (char_length(reason) between 1 and 500),
  review_ids uuid[] not null,
  administrator text not null,
  created_at timestamptz not null default clock_timestamp()
);
alter table review_private.config owner to bye_review_owner;
alter table review_private.identities owner to bye_review_owner;
alter table review_private.challenges owner to bye_review_owner;
alter table review_private.sessions owner to bye_review_owner;
alter table review_private.rate_limits owner to bye_review_owner;
alter table review_private.moderation_audit owner to bye_review_owner;
alter table review_private.config enable row level security;
alter table review_private.identities enable row level security;
alter table review_private.challenges enable row level security;
alter table review_private.sessions enable row level security;
alter table review_private.rate_limits enable row level security;
alter table review_private.moderation_audit enable row level security;

-- The non-login function owner has only the public-table privileges its functions need.
grant usage on schema public to bye_review_owner;
grant select on public.reviews,public.reports,public.courses,public.professors,public.dimensions,public.review_dimensions to bye_review_owner;
grant insert on public.reviews,public.review_dimensions,public.reports to bye_review_owner;
grant update(is_hidden) on public.reviews to bye_review_owner;
grant usage,select on sequence public.reports_id_seq to bye_review_owner;
create policy review_private_reviews_read on public.reviews for select to bye_review_owner using(true);
create policy review_private_reviews_insert on public.reviews for insert to bye_review_owner with check(true);
create policy review_private_reviews_hide on public.reviews for update to bye_review_owner using(true) with check(true);
create policy review_private_reports_read on public.reports for select to bye_review_owner using(true);
create policy review_private_reports_insert on public.reports for insert to bye_review_owner with check(true);
create policy review_private_dimensions_insert on public.review_dimensions for insert to bye_review_owner with check(true);
create policy review_private_dimensions_read on public.review_dimensions for select to bye_review_owner using(true);
create policy review_private_catalog_courses on public.courses for select to bye_review_owner using(true);
create policy review_private_catalog_professors on public.professors for select to bye_review_owner using(true);
create policy review_private_questions on public.dimensions for select to bye_review_owner using(true);

-- Returns a delay rather than raising: rejected attempts must COMMIT their counters.
create function review_private.consume(p_bucket text,p_max integer,p_seconds integer)
returns integer language plpgsql set search_path='' as $$
declare v_count integer; v_until timestamptz; v_now timestamptz:=clock_timestamp();
begin
  insert into review_private.rate_limits as r(bucket,attempts,expires_at)
  values(p_bucket,1,v_now+make_interval(secs=>p_seconds))
  on conflict(bucket) do update set
    attempts=case when r.expires_at<=v_now then 1 else least(r.attempts+1,p_max+1) end,
    expires_at=case when r.expires_at<=v_now then excluded.expires_at else r.expires_at end
  returning attempts,expires_at into v_count,v_until;
  return case when v_count>p_max then greatest(1,ceil(extract(epoch from v_until-v_now))::integer) else 0 end;
end $$;
alter function review_private.consume(text,integer,integer) owner to bye_review_owner;

create function review_private.gateway(p_operation text,p jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_mailbox text:=p->>'mailbox'; v_challenge review_private.challenges;
  v_identity review_private.identities; v_identity_id uuid; v_review uuid;
  v_delay integer; v_max integer; v_seconds integer; v_route text;
  v_answers jsonb; v_bad text; v_now timestamptz:=clock_timestamp();
begin
  if not exists(select 1 from review_private.config where ready and key_fingerprint=p->>'keyFingerprint') then
    return '{"ok":false,"code":"REVIEWS_DISABLED"}'::jsonb;
  end if;
  if p_operation='rate' then
    if coalesce(p->>'subject','') !~ '^[0-9a-f]{64}$' then return '{"ok":false,"code":"INVALID_INPUT"}'; end if;
    v_route:=p->>'route';
    select x.m,x.s into v_max,v_seconds from (values('auth/send',5,600),('auth/verify',20,600),('submit',10,3600),('report',20,3600)) x(r,m,s) where x.r=v_route;
    if v_max is null then return '{"ok":false,"code":"INVALID_INPUT"}'; end if;
    v_delay:=review_private.consume('ip:'||v_route||':'||(p->>'subject'),v_max,v_seconds);
    if v_delay>0 then return jsonb_build_object('ok',false,'code','RATE_LIMITED','retryAfter',v_delay); end if;
    return '{"ok":true}';
  end if;
  if p_operation in ('begin','verify') then
    if coalesce(v_mailbox,'') !~ '^[0-9a-f]{64}$' or coalesce(p->>'challenge','') !~ '^[0-9a-f]{64}$' or coalesce(p->>'code','') !~ '^[0-9a-f]{64}$' then return '{"ok":false,"code":"INVALID_INPUT"}'; end if;
    -- All operations on a mailbox serialize, including resends and concurrent verifications.
    perform pg_advisory_xact_lock(hashtextextended(v_mailbox,0));
    if p_operation='begin' then
      v_delay:=review_private.consume('email:send:'||v_mailbox,4,1800);
      if v_delay=0 then v_delay:=review_private.consume('email:cooldown:'||v_mailbox,1,60); end if;
      if v_delay>0 then return jsonb_build_object('ok',false,'code','RATE_LIMITED','retryAfter',v_delay); end if;
      -- Hard bound the shared free-tier send budget, with no automatic retries.
      v_delay:=review_private.consume('delivery:daily',300,86400);
      if v_delay>0 then return jsonb_build_object('ok',false,'code','RATE_LIMITED','retryAfter',v_delay); end if;
      delete from review_private.challenges where mailbox=v_mailbox;
      insert into review_private.challenges(digest,mailbox,code_mac) values(p->>'challenge',v_mailbox,p->>'code');
      return '{"ok":true}';
    end if;
    v_delay:=review_private.consume('email:verify:'||v_mailbox,10,900);
    if v_delay>0 then return jsonb_build_object('ok',false,'code','RATE_LIMITED','retryAfter',v_delay); end if;
    if coalesce(p->>'session','') !~ '^[0-9a-f]{64}$' then return '{"ok":false,"code":"INVALID_INPUT"}'; end if;
    select * into v_challenge from review_private.challenges where digest=p->>'challenge' and mailbox=v_mailbox for update;
    if not found or v_challenge.expires_at<=clock_timestamp() or v_challenge.attempts>=5 then return '{"ok":false,"code":"INVALID_CODE"}'; end if;
    update review_private.challenges set attempts=attempts+1 where digest=v_challenge.digest;
    if v_challenge.code_mac<>p->>'code' then return '{"ok":false,"code":"INVALID_CODE"}'; end if;
    delete from review_private.challenges where digest=v_challenge.digest;
    insert into review_private.identities(mailbox,verified_at) values(v_mailbox,v_now)
      on conflict(mailbox) do nothing;
    select * into v_identity from review_private.identities where mailbox=v_mailbox for update;
    -- Recheck expiry after acquiring the author lock; a concurrent ban may have made us wait.
    if v_challenge.expires_at<=clock_timestamp() then return '{"ok":false,"code":"INVALID_CODE"}'; end if;
    if v_identity.banned_at is not null then return '{"ok":false,"code":"ACCOUNT_RESTRICTED"}'; end if;
    insert into review_private.sessions(digest,identity_id) values(p->>'session',v_identity.id);
    return '{"ok":true}';
  end if;
  if p_operation='cancel' then
    delete from review_private.challenges where digest=p->>'challenge';
    return '{"ok":true}';
  end if;
  if p_operation='signout' then delete from review_private.challenges where digest=p->>'challenge'; end if;
  -- Lock identity BEFORE the session. Ban, verification, signout and writes follow this order.
  select identity_id into v_identity_id from review_private.sessions where digest=p->>'session';
  if v_identity_id is not null then
    select * into v_identity from review_private.identities where id=v_identity_id for update;
  end if;
  if p_operation='signout' then
    delete from review_private.sessions where digest=p->>'session';
    return '{"ok":true}';
  end if;
  if v_identity_id is null or not exists(select 1 from review_private.sessions where digest=p->>'session' and expires_at>clock_timestamp()) then return '{"ok":false,"code":"SESSION_EXPIRED"}'; end if;
  if v_identity.banned_at is not null then return '{"ok":false,"code":"ACCOUNT_RESTRICTED"}'; end if;
  if p_operation='session' then return '{"ok":true}'; end if;
  -- Also limit per author, so copied sessions or rotating addresses do not bypass write bounds.
  if p_operation in ('submit','report') then
    v_delay:=review_private.consume('author:'||p_operation||':'||v_identity_id::text,case when p_operation='submit' then 10 else 20 end,3600);
    if v_delay>0 then return jsonb_build_object('ok',false,'code','RATE_LIMITED','retryAfter',v_delay); end if;
  end if;
  if p_operation='report' then
    if coalesce(p->>'reason','')='' or char_length(p->>'reason')>500 then return '{"ok":false,"code":"INVALID_INPUT"}'; end if;
    -- Review lock also serializes the three-distinct-report auto-hide trigger.
    perform 1 from public.reviews where id=(p->>'reviewId')::uuid and not is_hidden for update;
    if not found then return '{"ok":false,"code":"REVIEW_UNAVAILABLE"}'; end if;
    begin
      insert into public.reports(review_id,reporter_id,reason) values((p->>'reviewId')::uuid,v_identity_id,p->>'reason');
    exception when unique_violation then return '{"ok":false,"code":"DUPLICATE_REPORT"}'; end;
    return '{"ok":true}';
  end if;
  if p_operation='submit' then
    if jsonb_typeof(p->'quality')<>'number' or jsonb_typeof(p->'difficulty')<>'number'
      or (p->>'quality')::numeric not in (1,2,3,4,5) or (p->>'difficulty')::numeric not in (1,2,3,4,5)
      or p->>'quality' is null or p->>'difficulty' is null then return '{"ok":false,"code":"INVALID_INPUT"}'; end if;
    v_answers:=coalesce(p->'answers','{}'::jsonb);
    if jsonb_typeof(v_answers)<>'object' then return '{"ok":false,"code":"INVALID_INPUT"}'; end if;
    select string_agg(a.key,',') into v_bad from jsonb_each(v_answers) a
    where not exists(select 1 from public.dimensions d where d.name=a.key)
      or case when jsonb_typeof(a.value)='number' then (a.value#>>'{}')::numeric not in (-1,0,1) else true end;
    if v_bad is not null then return '{"ok":false,"code":"INVALID_INPUT"}'; end if;
    begin
      insert into public.reviews(author_id,professor_id,course_id,quality,difficulty,body)
      values(v_identity_id,(p->>'professorId')::bigint,(p->>'courseId')::bigint,(p->>'quality')::numeric::integer,(p->>'difficulty')::numeric::integer,nullif(btrim(p->>'body'),'')) returning id into v_review;
      insert into public.review_dimensions(review_id,dimension,value)
      select v_review,a.key,(a.value#>>'{}')::numeric::smallint from jsonb_each(v_answers) a;
    exception
      when unique_violation then return '{"ok":false,"code":"DUPLICATE_REVIEW"}';
      when foreign_key_violation or check_violation or not_null_violation then return '{"ok":false,"code":"INVALID_INPUT"}';
    end;
    return jsonb_build_object('ok',true,'id',v_review);
  end if;
  return '{"ok":false,"code":"INVALID_INPUT"}';
end $$;
alter function review_private.gateway(text,jsonb) owner to bye_review_owner;
revoke all on function review_private.gateway(text,jsonb) from public,anon,authenticated;
grant execute on function review_private.gateway(text,jsonb) to bye_review_gateway;
revoke all on function review_private.consume(text,integer,integer) from public,anon,authenticated,bye_review_gateway;

-- Admin-only operation. No public HTTP endpoint or runtime-role grant.
create function review_private.moderate(p_review uuid,p_action text,p_reason text,p_hide uuid[] default '{}')
returns void language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
  if p_action not in ('ban','unban') or p_action is null or nullif(btrim(p_reason),'') is null or char_length(p_reason)>500 or p_hide is null then raise exception 'Invalid moderation request'; end if;
  select author_id into strict v_id from public.reviews where id=p_review;
  perform 1 from review_private.identities where id=v_id for update;
  if p_action='unban' and cardinality(p_hide)>0 then raise exception 'Unban does not restore or hide reviews'; end if;
  if exists(select 1 from unnest(p_hide) x where not exists(select 1 from public.reviews r where r.id=x and r.author_id=v_id)) then raise exception 'Selected reviews must belong to the same author'; end if;
  update review_private.identities set banned_at=case when p_action='ban' then clock_timestamp() else null end where id=v_id;
  if p_action='ban' then
    delete from review_private.sessions where identity_id=v_id;
    update public.reviews set is_hidden=true where id=any(p_hide);
  end if;
  insert into review_private.moderation_audit(identity_id,action,reason,review_ids,administrator)
  values(v_id,p_action,btrim(p_reason),p_hide,session_user);
end $$;
alter function review_private.moderate(uuid,text,text,uuid[]) owner to bye_review_owner;
revoke all on function review_private.moderate(uuid,text,text,uuid[]) from public,anon,authenticated,bye_review_gateway;
-- postgres owns the rollout and operator commands; the owner role cannot be assumed by the website.
grant usage on schema review_private to postgres;
grant all on all tables in schema review_private to postgres;
grant execute on all functions in schema review_private to postgres;

create function review_private.prune() returns void language sql security definer set search_path='' as $$
  delete from review_private.challenges where expires_at<=clock_timestamp();
  delete from review_private.sessions where expires_at<=clock_timestamp();
  delete from review_private.rate_limits where expires_at<=clock_timestamp();
$$;
alter function review_private.prune() owner to bye_review_owner;
revoke all on function review_private.prune() from public,anon,authenticated,bye_review_gateway;
grant execute on function review_private.prune() to postgres;
commit;
