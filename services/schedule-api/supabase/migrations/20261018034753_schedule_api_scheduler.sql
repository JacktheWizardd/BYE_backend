begin;
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
-- Generate the machine credential in Postgres. Its plaintext never enters
-- source control, CLI output, desktop clients, or migration parameters.
do $$begin
 if not exists(select 1 from vault.secrets where name='bye_schedule_cron') then
  perform vault.create_secret(replace(gen_random_uuid()::text||gen_random_uuid()::text,'-',''),'bye_schedule_cron','Standalone BYE schedule worker only');
 end if;
end$$;
-- Installed inactive. Activate only after offline and hosted verification.
select cron.schedule('bye-schedule-sync','*/5 * * * *',
 $job$select net.http_post(
   url:='https://nahvhampsxtasfwvvfei.supabase.co/functions/v1/bye-schedule-sync',
   headers:=jsonb_build_object('Content-Type','application/json','x-bye-job-token',(select decrypted_secret from vault.decrypted_secrets where name='bye_schedule_cron')),
   body:='{"action":"scheduled"}'::jsonb,timeout_milliseconds:=145000
 );$job$);
select cron.alter_job((select jobid from cron.job where jobname='bye-schedule-sync'),active:=false);
commit;
