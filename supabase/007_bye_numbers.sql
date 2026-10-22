-- BYE student numbers: one number per verified PCC student, shown on the app's student ID card.
-- Run as postgres in the Supabase SQL Editor, after 002_write_side.sql and 006. Safe to repeat.
--
-- What it adds:
--   private.bye_numbers      one row per Supabase account that asked for a number (account ID, number, date).
--                            No email is copied here; auth.users already holds the verified address.
--   claim_bye_number()       for a signed-in PCC student: returns their number, giving them the next one the
--                            first time. Repeating it always returns the same number.
--   bye_number_count()       for anyone: how many numbers have been given out ("Student 12 of 40").
-- Number 1 is the owner's and is never handed out automatically: the sequence starts at 2.
-- Future email-free sign-in must backfill number holders, move this FK to review_private.identities,
-- and adapt claim authentication BEFORE deleting Auth accounts. Matching UUIDs alone are insufficient.

begin;

create sequence if not exists private.bye_number_seq start with 2 minvalue 2;

create table if not exists private.bye_numbers (
  user_id    uuid primary key references auth.users (id) on delete restrict,
  number     int  not null unique check (number > 0),
  created_at timestamptz not null default pg_catalog.now()
);
-- IF NOT EXISTS does not repair schema drift. Abort rather than silently accept an incompatible table.
do $$
begin
  if (select pg_catalog.count(*) from pg_catalog.pg_attribute where attrelid='private.bye_numbers'::regclass and attnum>0 and not attisdropped) <> 3
    or not exists (select 1 from pg_catalog.pg_attribute where attrelid='private.bye_numbers'::regclass and attname='user_id' and atttypid='uuid'::regtype and attnotnull)
    or not exists (select 1 from pg_catalog.pg_attribute where attrelid='private.bye_numbers'::regclass and attname='number' and atttypid='integer'::regtype and attnotnull)
    or not exists (select 1 from pg_catalog.pg_attribute where attrelid='private.bye_numbers'::regclass and attname='created_at' and atttypid='timestamptz'::regtype and attnotnull)
    or not exists (select 1 from pg_catalog.pg_constraint where conrelid='private.bye_numbers'::regclass and contype='p' and pg_catalog.pg_get_constraintdef(oid)='PRIMARY KEY (user_id)')
    or not exists (select 1 from pg_catalog.pg_constraint where conrelid='private.bye_numbers'::regclass and contype='u' and pg_catalog.pg_get_constraintdef(oid)='UNIQUE (number)')
    or not exists (select 1 from pg_catalog.pg_constraint where conrelid='private.bye_numbers'::regclass and contype='c' and convalidated and pg_catalog.pg_get_constraintdef(oid)='CHECK ((number > 0))')
    or not exists (select 1 from pg_catalog.pg_constraint where conrelid='private.bye_numbers'::regclass and contype='f' and convalidated and pg_catalog.pg_get_constraintdef(oid)='FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE RESTRICT')
    or not exists (select 1 from pg_catalog.pg_attrdef d join pg_catalog.pg_attribute a on a.attrelid=d.adrelid and a.attnum=d.adnum where d.adrelid='private.bye_numbers'::regclass and a.attname='created_at' and pg_catalog.pg_get_expr(d.adbin,d.adrelid)='now()')
  then raise exception 'BYE number table differs from 007; inspect before proceeding.'; end if;
  if not exists (select 1 from pg_catalog.pg_sequence where seqrelid='private.bye_number_seq'::regclass and seqmin=2 and seqstart=2 and seqincrement=1 and not seqcycle)
  then raise exception 'BYE number sequence differs from 007; inspect before proceeding.'; end if;
end;
$$;
alter table private.bye_numbers owner to postgres;
alter sequence private.bye_number_seq owner to postgres;
alter table private.bye_numbers enable row level security;
-- No policies: only the postgres-owned, explicitly authorized functions access rows.
revoke all on table private.bye_numbers from public, anon, authenticated;
revoke all on sequence private.bye_number_seq from public, anon, authenticated;

-- Returns the caller's number and the current total. Concurrent calls by one student return one number;
-- a lost race may skip a sequence value, which only leaves a gap. Numbers can exceed the row count.
-- ON DELETE RESTRICT intentionally blocks accidental loss; fixture cleanup removes number rows first.
create or replace function public.claim_bye_number()
returns table (number int, total int)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_user uuid := (select auth.uid());
begin
  if v_user is null or not private.is_pcc_student() then
    raise exception 'Verify your @go.pasadena.edu email to get a BYE number.' using errcode = '42501';
  end if;
  if not exists (select 1 from private.bye_numbers b where b.user_id = v_user) then
    insert into private.bye_numbers (user_id, number)
    values (v_user, pg_catalog.nextval('private.bye_number_seq'::regclass))
    on conflict (user_id) do nothing;
  end if;
  return query
    select b.number, (select pg_catalog.count(*)::int from private.bye_numbers)
    from private.bye_numbers b where b.user_id = v_user;
end;
$$;

create or replace function public.bye_number_count()
returns int
language sql
stable
security definer
set search_path = ''
as $$ select pg_catalog.count(*)::int from private.bye_numbers; $$;

alter function public.claim_bye_number() owner to postgres;
alter function public.bye_number_count() owner to postgres;

-- create or replace keeps grants; restate them so a rerun can't widen access.
revoke all on function public.claim_bye_number() from public, anon;
grant execute on function public.claim_bye_number() to authenticated;
revoke all on function public.bye_number_count() from public;
grant execute on function public.bye_number_count() to anon, authenticated;

commit;

-- OWNER STEP: separately approved, run as postgres. Replace the placeholder ONLY in the SQL Editor.
-- Never save the real address in source, logs or handoff notes. Requires exactly one eligible account.
-- Lock prevents competing owner assignments; UPSERT also moves an existing number to 1.
-- A different holder of 1 raises an error and rolls back. Sequence state is never reset.
-- BEGIN OWNER SQL
-- begin;
-- lock table private.bye_numbers in share row exclusive mode;
-- do $owner$
-- declare v_owner uuid;
-- begin
--   select u.id into strict v_owner from auth.users u
--   where pg_catalog.lower(u.email)=pg_catalog.lower('<your school email>')
--     and u.email_confirmed_at is not null
--     and pg_catalog.lower(u.email) like '%@go.pasadena.edu'
--     and pg_catalog.strpos(pg_catalog.split_part(u.email,'@',1),'+')=0;
--   if exists(select 1 from private.bye_numbers b where b.number=1 and b.user_id<>v_owner) then
--     raise exception 'Owner number is already assigned; inspect before proceeding.';
--   end if;
--   insert into private.bye_numbers(user_id,number) values(v_owner,1)
--   on conflict(user_id) do update set number=excluded.number;
-- end;
-- $owner$;
-- commit;
-- END OWNER SQL
