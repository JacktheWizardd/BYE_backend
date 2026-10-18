do $guard$
declare definition text;
begin
 select pg_get_functiondef('bye_schedule.command(text,jsonb)'::regprocedure) into definition;
 definition:=replace(definition,'if token is distinct from s.lock_token or s.lock_until<=now()','if token is null or s.lock_token is null or token is distinct from s.lock_token or s.lock_until<=now()');
 definition:=replace(definition,$before$e->'payload'->>'termCode'<>'202670' or e->'payload'->>'crn' !~$before$,$after$(e->'payload'->>'termCode') is distinct from '202670' or coalesce(e->'payload'->>'crn','') !~$after$);
 execute definition;
end $guard$;
