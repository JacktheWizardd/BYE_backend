-- BYE review database: Security Advisor follow-up.
-- Jack approved this permission change after inspecting the live function.
-- Run as postgres after 002_write_side.sql, where public.rls_auto_enable() exists.
-- This helper is an event-trigger function for automatic RLS on new tables.
-- Remove app access while retaining the function and its event trigger.
-- Safe to repeat. Does not change submit_review or any table data.

begin;

revoke execute on function public.rls_auto_enable()
  from public, anon, authenticated;

commit;
