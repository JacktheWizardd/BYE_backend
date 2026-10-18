-- Validate the actual JSONB source text before selecting any active snapshot.
-- This catches Windows console/connector encoding damage before publication.
begin;
create function pcc_schedule.verify_active_source() returns trigger
language plpgsql set search_path = pg_catalog, pcc_schedule as $$
declare run pcc_schedule.import_runs; actual text;
begin
  if NEW.active_import_id is null then return NEW; end if;
  select * into strict run from pcc_schedule.import_runs where id=NEW.active_import_id;
  if run.term_code <> NEW.term_code or run.status <> 'published' then
    raise exception 'Active snapshot must be a published import of the same term';
  end if;
  select md5(string_agg(md5(payload::text),'|' order by ordinal)) into actual
    from pcc_schedule.source_rows where import_id=NEW.active_import_id;
  if run.report->>'source_jsonb_md5' is null or actual is distinct from run.report->>'source_jsonb_md5' then
    raise exception 'Source content checksum mismatch; snapshot not selected';
  end if;
  return NEW;
end $$;
revoke all on function pcc_schedule.verify_active_source() from public,anon,authenticated,service_role;
create trigger verify_active_source before insert or update of active_import_id on pcc_schedule.terms
  for each row execute function pcc_schedule.verify_active_source();
commit;
