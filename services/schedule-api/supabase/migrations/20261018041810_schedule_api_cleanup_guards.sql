begin;
do $cleanup$
declare definition text;
begin
 select pg_get_functiondef('bye_schedule.command(text,jsonb)'::regprocedure) into definition;
 definition:=replace(definition,$before$and token is distinct from s.lock_token;$before$,$after$and staging.token is distinct from s.lock_token;$after$);
 definition:=replace(definition,$before$if s.lock_until>now() then return '{"skipped":"LOCKED"}'; end if;$before$,$after$
   if s.lock_until>now() then return '{"skipped":"LOCKED"}'; end if;
   if s.lock_token is not null and s.lock_until<=now() then
     update bye_schedule.state set lock_token=null,lock_until=null,failures=failures+1,next_fetch=greatest(next_fetch,now()+case when failures>=2 then interval '30 minutes' else interval '5 minutes' end) where term=s.term;
     insert into bye_schedule.events(kind,details) values('worker_expired','{}');
     return '{"skipped":"RECOVERED_EXPIRED_WORKER"}';
   end if;
 $after$);
 execute definition;
end $cleanup$;
create function bye_schedule.trim_events() returns trigger language plpgsql security invoker set search_path=pg_catalog as $trim$
begin
 delete from bye_schedule.events where at<now()-interval '7 days' or id in(select id from bye_schedule.events order by id desc offset 2500);
 return null;
end $trim$;
revoke all on function bye_schedule.trim_events() from public,anon,authenticated,service_role;
create trigger trim_events after insert on bye_schedule.events for each statement execute function bye_schedule.trim_events();
commit;
