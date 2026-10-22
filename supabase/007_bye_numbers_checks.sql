-- Manual 007 checks. Run individual blocks with the indicated role.
-- MUTATING TESTS ARE FOR A DISPOSABLE LOCAL DATABASE ONLY. Production fixture creation,
-- claims, owner assignment or cleanup each require separate explicit approval.
-- Use fictional accounts only. The offline runner creates the UUIDs below.
-- Expected errors need separate transactions; ROLLBACK after an expected error.

-- A. postgres: inspect security. Both functions: postgres, security definer, empty search_path.
select p.proname, pg_get_userbyid(p.proowner) as owner, p.prosecdef, p.proconfig
from pg_proc p where p.oid in ('public.claim_bye_number()'::regprocedure,'public.bye_number_count()'::regprocedure);
select relrowsecurity from pg_class where oid='private.bye_numbers'::regclass; -- true
select has_function_privilege('anon','public.claim_bye_number()','EXECUTE') as anon_claim, -- false
 has_function_privilege('authenticated','public.claim_bye_number()','EXECUTE') as student_claim, -- true
 has_function_privilege('anon','public.bye_number_count()','EXECUTE') as anon_count; -- true
select r, has_table_privilege(r,'private.bye_numbers','SELECT,INSERT,UPDATE,DELETE') as table_access,
 has_sequence_privilege(r,'private.bye_number_seq','USAGE,SELECT,UPDATE') as sequence_access
from (values ('anon'),('authenticated')) roles(r); -- all false

-- B. anon: count succeeds (0 on fresh DB); claim separately fails 42501.
begin; set local role anon; select public.bye_number_count(); rollback;
begin; set local role anon; select * from public.claim_bye_number(); -- permission denied
rollback;

-- C. authenticated as fictional student 2 (must exist and be confirmed PCC).
-- Fresh DB: first returns (2,1); repeat returns (2,1). After other tests, expect same number, current count.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
select * from public.claim_bye_number();
select * from public.claim_bye_number();
commit;
-- Repeat with fictional student 3: fresh DB returns (3,2).
-- With runner fixture users 4 (non-PCC), 5 (unconfirmed), 6 (plus alias): expect 42501 each.
-- Use a separate BEGIN/SET ROLE/set_config/claim/ROLLBACK for each rejected account.

-- D. authenticated: run each denial separately. All expect 42501, even for own row.
begin; set local role authenticated; select * from private.bye_numbers;
rollback;
begin; set local role authenticated; update private.bye_numbers set number=1;
rollback;
begin; set local role authenticated; select nextval('private.bye_number_seq');
rollback;

-- E. postgres: use the commented OWNER SQL in 007, with a fictional eligible account.
-- Check number 1, repeat unchanged, and moving an existing holder to 1.
-- A different existing holder of 1 must fail without changes. A missing/ineligible account must fail.
-- Verify next ordinary claim advances the sequence, never yields 1.
select number from private.bye_numbers order by number;
select last_value, is_called from private.bye_number_seq;

-- F. Two independent SQL connections (automated in scripts/bye-numbers/rehearsal.mjs):
-- Session A: BEGIN, authenticated + fresh fixture uid, claim; leave transaction open.
-- Session B: same uid, claim; must wait. Commit A: B returns A's number; commit B.
-- Different fresh uids concurrently: distinct numbers. Sequence gaps are acceptable.
-- Re-run 007 as postgres; rows and sequence state must remain unchanged.

-- G. postgres: fixture-only RESTRICT and narrowly scoped cleanup.
-- First statement must fail 23503 if this fixture holds a number.
delete from auth.users where id='00000000-0000-4000-8000-000000000002';
-- After verifying this UUID is ONLY the disposable fixture, delete child before parent:
begin;
delete from private.bye_numbers where user_id='00000000-0000-4000-8000-000000000002';
delete from auth.users where id='00000000-0000-4000-8000-000000000002';
commit;
-- Never reset the sequence, delete all rows, or reuse this cleanup for real accounts.

-- H. Production G1 ONLY after explicit approval: inspect actual event triggers and helper definitions.
-- 003 revokes function permissions; it does NOT contain rls_auto_enable's implementation.
select e.evtname,e.evtenabled,pg_get_functiondef(e.evtfoid) from pg_event_trigger e;
select pg_get_functiondef('private.is_pcc_student()'::regprocedure);
-- Confirm exposed API schemas in the approved Data API settings view. This setting alone may be NULL:
select current_setting('pgrst.db_schemas',true);
-- NULL is not evidence that private is unexposed. Record dashboard/config evidence in G1.
