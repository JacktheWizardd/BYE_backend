-- Fall 2026 pilot. Additive; no public review objects are changed.
-- Apply once as the database owner. This schema is NOT a PostgREST exposed schema.
begin;
create schema pcc_schedule;
revoke all on schema pcc_schedule from public, anon, authenticated, service_role;
alter default privileges in schema pcc_schedule revoke all on tables from public, anon, authenticated, service_role;
alter default privileges in schema pcc_schedule revoke all on functions from public, anon, authenticated, service_role;
alter default privileges in schema pcc_schedule revoke all on sequences from public, anon, authenticated, service_role;

create table pcc_schedule.terms (
  term_code text primary key check (term_code = '202670'),
  name text not null,
  metadata jsonb not null check (jsonb_typeof(metadata) = 'object'),
  active_import_id uuid,
  previous_import_id uuid
);
create table pcc_schedule.import_runs (
  id uuid primary key,
  term_code text not null references pcc_schedule.terms,
  status text not null default 'staging' check (status in ('staging','published','failed','unchanged')),
  created_at timestamptz not null default now(),
  retrieved_at timestamptz not null,
  source_url text not null check (source_url = 'https://prod-apiweb.pasadena.edu/api/classSchedule/202670'),
  terms_url text not null,
  raw_sha256 text not null check (raw_sha256 ~ '^[a-f0-9]{64}$'),
  content_sha256 text not null check (content_sha256 ~ '^[a-f0-9]{64}$'),
  source_row_count integer not null check (source_row_count > 0),
  expected_counts jsonb not null,
  report jsonb not null,
  published_at timestamptz,
  changes jsonb,
  error_code text
);
alter table pcc_schedule.terms add foreign key (active_import_id) references pcc_schedule.import_runs;
alter table pcc_schedule.terms add foreign key (previous_import_id) references pcc_schedule.import_runs;

create table pcc_schedule.courses (
  import_id uuid not null references pcc_schedule.import_runs,
  course_key text not null,
  subject text not null check (subject <> ''),
  number text not null check (number <> ''),
  title text not null,
  titles jsonb not null,
  notes jsonb not null,
  primary key (import_id, course_key),
  unique (import_id, subject, number)
);
create table pcc_schedule.sections (
  import_id uuid not null,
  crn text not null check (crn ~ '^[0-9]{5}$'),
  course_key text not null,
  status_code text,
  enrolled integer,
  capacity integer,
  seats_available integer,
  waitlist_count integer,
  waitlist_capacity integer,
  waitlist_available integer,
  units text,
  information jsonb not null,
  content_sha256 text not null,
  primary key (import_id, crn),
  foreign key (import_id, course_key) references pcc_schedule.courses
);
create table pcc_schedule.meetings (
  import_id uuid not null,
  crn text not null,
  meeting_key text not null,
  start_date date,
  end_date date,
  days text[] not null,
  begin_time text,
  end_time text,
  format_code text,
  format_description text,
  campus text,
  building text,
  room text,
  source_fields jsonb not null,
  primary key (import_id, crn, meeting_key),
  foreign key (import_id, crn) references pcc_schedule.sections,
  check (start_date is null or end_date is null or start_date <= end_date)
);
create table pcc_schedule.instructor_assignments (
  import_id uuid not null,
  crn text not null,
  assignment_key text not null,
  role text not null check (role in ('primary','secondary')),
  name text,
  email text,
  primary key (import_id, crn, assignment_key),
  foreign key (import_id, crn) references pcc_schedule.sections
);
create table pcc_schedule.source_rows (
  import_id uuid not null,
  ordinal integer not null check (ordinal > 0),
  crn text not null,
  course_key text not null,
  meeting_key text not null,
  assignment_keys text[] not null,
  row_sha256 text not null,
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  primary key (import_id, ordinal),
  foreign key (import_id, crn) references pcc_schedule.sections,
  foreign key (import_id, course_key) references pcc_schedule.courses,
  foreign key (import_id, crn, meeting_key) references pcc_schedule.meetings
);
create index import_runs_term_hash on pcc_schedule.import_runs(term_code, content_sha256);
create index sections_course on pcc_schedule.sections(import_id, course_key);
create index source_rows_crn on pcc_schedule.source_rows(import_id, crn);

-- Only owners use these functions. Uploads may span requests; only publication
-- switches the active pointer, under a per-term row lock, after full validation.
create function pcc_schedule.publish_import(target uuid) returns jsonb
language plpgsql set search_path = pg_catalog, pcc_schedule as $$
declare run pcc_schedule.import_runs; term pcc_schedule.terms; old_run pcc_schedule.import_runs;
  result jsonb; actual jsonb; before_id uuid;
begin
  select * into strict run from pcc_schedule.import_runs where id = target;
  select * into strict term from pcc_schedule.terms where term_code = run.term_code for update;
  if run.status = 'published' and term.active_import_id = target then return run.changes; end if;
  if run.status <> 'staging' then raise exception 'Import is not staging'; end if;
  if coalesce((run.report->>'valid')::boolean, false) is not true then raise exception 'Invalid report'; end if;
  select jsonb_build_object(
    'source_rows', (select count(*) from pcc_schedule.source_rows where import_id = target),
    'courses', (select count(*) from pcc_schedule.courses where import_id = target),
    'sections', (select count(*) from pcc_schedule.sections where import_id = target),
    'meetings', (select count(*) from pcc_schedule.meetings where import_id = target),
    'instructor_assignments', (select count(*) from pcc_schedule.instructor_assignments where import_id = target)
  ) into actual;
  if actual <> run.expected_counts or (actual->>'source_rows')::integer <> run.source_row_count then
    raise exception 'Incomplete import: expected %, actual %', run.expected_counts, actual;
  end if;
  if exists(select 1 from pcc_schedule.source_rows r where r.import_id = target and (
    r.payload->>'termCode' is distinct from run.term_code or
    r.payload->>'crn' is distinct from r.crn or
    r.payload->>'subjCode' || ' ' || (r.payload->>'courseNumbDisplay') is distinct from r.course_key or
    not exists(select 1 from pcc_schedule.sections s where s.import_id = target and s.crn = r.crn and s.course_key = r.course_key) or
    cardinality(r.assignment_keys) = 0 or exists(
      select 1 from unnest(r.assignment_keys) k where not exists(
        select 1 from pcc_schedule.instructor_assignments a where a.import_id = target and a.crn = r.crn and a.assignment_key = k))
  )) then raise exception 'Source reconciliation failed'; end if;
  if exists(select 1 from pcc_schedule.sections s where s.import_id = target and not exists(
    select 1 from pcc_schedule.source_rows r where r.import_id = target and r.crn = s.crn)) or
    exists(select 1 from pcc_schedule.meetings m where m.import_id = target and not exists(
    select 1 from pcc_schedule.source_rows r where r.import_id = target and r.crn = m.crn and r.meeting_key = m.meeting_key)) then
    raise exception 'Unaccounted normalized record';
  end if;
  before_id := term.active_import_id;
  select * into old_run from pcc_schedule.import_runs where id = before_id;
  if old_run.retrieved_at > run.retrieved_at then raise exception 'Older import cannot replace newer data'; end if;
  if old_run.content_sha256 = run.content_sha256 then
    result := jsonb_build_object('unchanged', true, 'active_import_id', before_id);
    update pcc_schedule.import_runs set status = 'unchanged', changes = result where id = target;
    return result;
  end if;
  select jsonb_build_object(
    'added', coalesce(jsonb_agg(n.crn order by n.crn) filter (where o.crn is null), '[]'),
    'removed', coalesce(jsonb_agg(o.crn order by o.crn) filter (where n.crn is null), '[]'),
    'changed', coalesce(jsonb_agg(n.crn order by n.crn) filter (where o.crn is not null and n.crn is not null and n.content_sha256 <> o.content_sha256), '[]')
  ) into result from (select * from pcc_schedule.sections where import_id = target) n
    full join (select * from pcc_schedule.sections where import_id = before_id) o using (crn);
  update pcc_schedule.import_runs set status = 'published', published_at = now(), changes = result where id = target;
  update pcc_schedule.terms set previous_import_id = before_id, active_import_id = target where term_code = run.term_code;
  return result;
end $$;

create function pcc_schedule.select_previous() returns uuid
language plpgsql set search_path = pg_catalog, pcc_schedule as $$
declare term pcc_schedule.terms;
begin
  select * into strict term from pcc_schedule.terms where term_code = '202670' for update;
  if term.previous_import_id is null or not exists(select 1 from pcc_schedule.import_runs
    where id = term.previous_import_id and term_code = term.term_code and status = 'published') then
    raise exception 'No previous successful snapshot';
  end if;
  update pcc_schedule.terms set active_import_id = term.previous_import_id,
    previous_import_id = term.active_import_id where term_code = term.term_code;
  return term.previous_import_id;
end $$;

-- Published snapshots are immutable. A new import is the only update path.
create function pcc_schedule.protect_snapshot() returns trigger
language plpgsql set search_path = pg_catalog, pcc_schedule as $$
declare run_id uuid;
begin
  if TG_OP = 'DELETE' then run_id := OLD.import_id; else run_id := NEW.import_id; end if;
  if exists(select 1 from pcc_schedule.import_runs where id = run_id and status <> 'staging') or
     (TG_OP = 'UPDATE' and OLD.import_id is distinct from NEW.import_id) then
    raise exception 'Snapshot is immutable';
  end if;
  if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
end $$;
do $$ declare item text; begin
  foreach item in array array['terms','import_runs','courses','sections','meetings','instructor_assignments','source_rows'] loop
    execute format('alter table pcc_schedule.%I enable row level security', item);
  end loop;
  foreach item in array array['courses','sections','meetings','instructor_assignments','source_rows'] loop
    execute format('create trigger protect_snapshot before insert or update or delete on pcc_schedule.%I for each row execute function pcc_schedule.protect_snapshot()', item);
  end loop;
end $$;
revoke all on all tables in schema pcc_schedule from public, anon, authenticated, service_role;
revoke all on all functions in schema pcc_schedule from public, anon, authenticated, service_role;
revoke all on all sequences in schema pcc_schedule from public, anon, authenticated, service_role;
comment on schema pcc_schedule is 'Owner-only Fall 2026 dated schedule snapshots. No public API or automatic refresh.';
commit;
