-- CUTOVER: obtain explicit production authorization separately from prepare/backfill/deployment.
-- Run the website's private-review-admin.ts backfill tool first, with the stable identity secret.
-- This file never deletes Auth accounts. After cutover legacy JWTs cannot write reviews/reports.
begin;
lock table public.reviews,public.reports in access exclusive mode;
lock table auth.users in share mode;
do $$ begin
  if not exists(select 1 from review_private.config where key_fingerprint is not null and not ready and cutover_at is null) then raise exception 'Backfill must finish before cutover'; end if;
  if exists(select 1 from public.reviews r where not exists(select 1 from review_private.identities i where i.id=r.author_id))
    or exists(select 1 from public.reports r where not exists(select 1 from review_private.identities i where i.id=r.reporter_id)) then raise exception 'Identity backfill incomplete'; end if;
  -- A new legacy account during backfill requires another backfill before proceeding.
  if exists(select 1 from auth.users u where u.email_confirmed_at is not null
    and lower(btrim(u.email)) ~ '^[a-z0-9.!#$&''*/=?^_`{|}~-]+@go\.pasadena\.edu$'
    and not exists(select 1 from review_private.identities i where i.id=u.id and i.mailbox is not null and i.legacy_updated_at is not distinct from u.updated_at)) then raise exception 'New or changed confirmed accounts require backfill'; end if;
end $$;
alter table public.reviews drop constraint reviews_author_id_fkey;
alter table public.reports drop constraint reports_reporter_id_fkey;
alter table public.reviews alter column author_id drop default;
alter table public.reports alter column reporter_id drop default;
alter table public.reviews add constraint reviews_author_id_fkey foreign key(author_id) references review_private.identities(id);
alter table public.reports add constraint reports_reporter_id_fkey foreign key(reporter_id) references review_private.identities(id);
revoke execute on function public.submit_review(bigint,bigint,integer,integer,text,jsonb) from public,anon,authenticated;
revoke insert on public.reports from anon,authenticated;
revoke insert(review_id,reason) on public.reports from anon,authenticated;
drop policy "PCC students can report visible reviews" on public.reports;
update review_private.identities set legacy_updated_at=null;
update review_private.config set ready=true,cutover_at=clock_timestamp();
commit;
-- Supabase Cron is provisioned separately by the operator after approval:
-- select cron.schedule('bye-private-review-prune','*/15 * * * *','select review_private.prune()');
