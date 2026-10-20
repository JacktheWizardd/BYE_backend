-- BYE review database: block "+" aliases of a school address.
-- Run as postgres in the Supabase SQL Editor, after 002_write_side.sql. Safe to repeat.
--
-- Why: PCC mail is Google Workspace, which delivers jdoe+1@go.pasadena.edu to jdoe@go.pasadena.edu.
-- Each alias signs in as a separate Supabase user, so one person could post several reviews of the
-- same professor and course, or reach the 3 reports that auto-hide a review alone.
-- Workspace usernames can't contain "+", so no real PCC address is excluded.
--
-- What changes: private.is_pcc_student() also requires no "+" before the @. submit_review and the
-- reports policy both use it, so neither accepts a plus-tagged account. Existing reviews and reports
-- are not changed or deleted. The website rejects these addresses too (server/reviews.ts).
--
-- Before running, count existing plus-tagged accounts (shows a number only, no addresses):
--   select count(*) from auth.users where split_part(email, '@', 1) like '%+%';

begin;

create or replace function private.is_pcc_student()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from auth.users u
    where u.id = (select auth.uid())
      and u.email_confirmed_at is not null
      and lower(u.email) like '%@go.pasadena.edu'
      and position('+' in split_part(u.email, '@', 1)) = 0
  );
$$;

-- create or replace keeps the existing grants; restate them so a rerun can't widen access.
revoke all on function private.is_pcc_student() from public, anon;
grant execute on function private.is_pcc_student() to authenticated;

commit;

-- Check afterwards (expect one row, ending with "= 0)"):
--   select pg_get_functiondef('private.is_pcc_student()'::regprocedure);
