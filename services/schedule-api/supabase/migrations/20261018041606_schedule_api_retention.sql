do $retention$
declare definition text; a integer; b integer;
begin
 select pg_get_functiondef('bye_schedule.command(text,jsonb)'::regprocedure) into definition;
 a:=strpos(definition,$find$elsif op='rollback' then$find$);
 b:=strpos(definition,$find$elsif op='cleanup' then$find$);
 if a=0 or b<=a then raise exception 'Unexpected command definition'; end if;
 definition:=left(definition,a-1)||$replacement$elsif op='rollback' then
   select * into strict s from bye_schedule.state where term='202670' for update;
   if s.lock_until>now() then raise exception 'Worker active'; end if;
   if args->>'target'='catalog' then
     if s.previous_catalog is null then raise exception 'No previous catalog'; end if;
     update bye_schedule.state set catalog=s.previous_catalog,previous_catalog=s.catalog,checked_at=null,enabled=false where term=s.term;
   else
     if s.previous_availability is null then raise exception 'No previous availability'; end if;
     update bye_schedule.availability set value=previous,previous=value,evidence=previous_evidence,previous_evidence=evidence,generation=s.previous_availability where rollback_member;
     update bye_schedule.state set availability=s.previous_availability,previous_availability=s.availability,checked_at=null,enabled=false where term=s.term;
   end if;
   return jsonb_build_object('rolledBack',true,'stale',true,'enabled',false,'target',coalesce(args->>'target','availability'));
 $replacement$||substr(definition,b);
 definition:=replace(definition,$before$elsif op='cleanup' then$before$,$after$elsif op='cleanup' then
   if to_regclass('cron.job_run_details') is not null then
     execute $history$delete from cron.job_run_details where jobid in(select jobid from cron.job where jobname='bye-schedule-sync') and end_time<now()-interval '7 days'$history$;
   end if;
 $after$);
 definition:=replace(definition,$before$new_catalog:=args->>'catalogHash'; new_availability:=args->>'availabilityHash';$before$,$after$new_catalog:=args->>'catalogHash'; new_availability:=args->>'availabilityHash';
   if (args->>'retrievedAt')::timestamptz>now()+interval '1 minute' or (args->>'retrievedAt')::timestamptz<s.checked_at then raise exception 'Stale or future source timestamp'; end if;
 $after$);
 execute definition;
end $retention$;
