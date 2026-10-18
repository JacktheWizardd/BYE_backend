do $cadence$
declare definition text;
begin
 if to_regclass('cron.job') is not null then
   perform cron.alter_job((select jobid from cron.job where jobname='bye-schedule-sync'),schedule:='* * * * *');
 end if;
 select pg_get_functiondef('bye_schedule.command(text,jsonb)'::regprocedure) into definition;
 definition:=replace(definition,$old$delete from cron.job_run_details where jobid in(select jobid from cron.job where jobname='bye-schedule-sync') and end_time<now()-interval '7 days'$old$,$new$delete from cron.job_run_details where jobid in(select jobid from cron.job where jobname='bye-schedule-sync') and end_time is not null and (end_time<now()-interval '7 days' or runid in(select runid from cron.job_run_details where jobid in(select jobid from cron.job where jobname='bye-schedule-sync') and end_time is not null order by runid desc offset 2500))$new$);
 execute definition;
end $cadence$;
