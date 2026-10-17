-- BYE review database, part 2: write side and moderation.
-- Run once in the Supabase SQL Editor, after schema.sql. Everything runs in one
-- transaction: if any statement fails, nothing is changed.
--
-- What this adds:
--   1. dimensions table: the 7 review questions and their low/high labels.
--   2. private.is_pcc_student(): "signed in with a confirmed @go.pasadena.edu email".
--   3. submit_review(...): the only way to add a review (and its answers).
--   4. Reports: PCC students can report a visible review, once each.
--   5. Auto-hide: a review with 3 reports is hidden.
--   6. Lock-down: the app can't insert, edit or delete any table directly.

begin;

-- ================= 1. REVIEW QUESTIONS =================

create table public.dimensions (
  name        text primary key,
  low_label   text not null,      -- meaning of -1
  high_label  text not null,      -- meaning of +1
  sort_order  smallint not null unique
);

insert into public.dimensions (name, low_label, high_label, sort_order) values
  ('grading',        'lenient',            'strict',              1),
  ('workload',       'light',              'heavy',               2),
  ('attendance',     'optional',           'required',            3),
  ('clarity',        'unclear',            'clear',               4),
  ('feedback_speed', 'slow',               'fast',                5),
  ('test_alignment', 'rarely match class', 'closely match class', 6),
  ('textbook',       'optional',           'required',            7);

alter table public.dimensions enable row level security;
grant select on public.dimensions to anon, authenticated;

create policy "Anyone can read dimensions"
  on public.dimensions for select to anon, authenticated using (true);

-- Answers may only use names from the list above. A skipped question has no row.
alter table public.review_dimensions
  add constraint review_dimensions_dimension_fkey
  foreign key (dimension) references public.dimensions (name);

-- ================= 2. WHO COUNTS AS A PCC STUDENT =================

-- A schema the API can't reach, for helpers the app should never call directly.
create schema if not exists private;
grant usage on schema private to authenticated;

-- True when the caller is signed in with a confirmed @go.pasadena.edu email.
-- Reads auth.users (not the login token), so it always sees the current email.
create function private.is_pcc_student()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from auth.users u
    where u.id = (select auth.uid())
      and u.email_confirmed_at is not null
      and lower(u.email) like '%@go.pasadena.edu'
  );
$$;

revoke all on function private.is_pcc_student() from public, anon;
grant execute on function private.is_pcc_student() to authenticated;

-- ================= 3. SUBMIT A REVIEW =================

-- p_answers is a JSON object of question -> -1, 0 or 1, for example
-- {"grading": 1, "workload": -1}. Leave a question out to skip it.
-- Returns the new review's id.
create function public.submit_review(
  p_professor_id  bigint,
  p_course_id     bigint,
  p_quality       int,
  p_difficulty    int,
  p_body          text  default null,
  p_answers       jsonb default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_review_id uuid;
  v_bad       text;
begin
  if not private.is_pcc_student() then
    raise exception 'Sign in with your @go.pasadena.edu email to post a review.'
      using errcode = '42501';
  end if;

  if p_quality is null or p_quality not between 1 and 5
     or p_difficulty is null or p_difficulty not between 1 and 5 then
    raise exception 'Quality and difficulty must each be 1 to 5.' using errcode = '22023';
  end if;

  p_answers := coalesce(p_answers, '{}');
  if jsonb_typeof(p_answers) <> 'object' then
    raise exception 'Answers must be a JSON object.' using errcode = '22023';
  end if;

  select string_agg(a.key, ', ' order by a.key) into v_bad
  from jsonb_each(p_answers) a
  where not exists (select 1 from public.dimensions d where d.name = a.key)
     or case when jsonb_typeof(a.value) = 'number'
             then (a.value #>> '{}')::numeric not in (-1, 0, 1)
             else true end;
  if v_bad is not null then
    raise exception 'Unknown question or answer not -1, 0 or 1: %', v_bad using errcode = '22023';
  end if;

  begin
    insert into public.reviews (professor_id, course_id, author_id, quality, difficulty, body)
    values (p_professor_id, p_course_id, (select auth.uid()), p_quality, p_difficulty,
            nullif(btrim(p_body), ''))
    returning id into v_review_id;
  exception
    when unique_violation then
      raise exception 'You already reviewed this professor for this course.' using errcode = '23505';
    when foreign_key_violation then
      raise exception 'That professor or course doesn''t exist.' using errcode = '23503';
  end;

  insert into public.review_dimensions (review_id, dimension, value)
  select v_review_id, a.key, (a.value #>> '{}')::numeric::smallint  -- accepts 1 and 1.0
  from jsonb_each(p_answers) a;

  return v_review_id;
end;
$$;

revoke all on function public.submit_review(bigint, bigint, int, int, text, jsonb) from public, anon;
grant execute on function public.submit_review(bigint, bigint, int, int, text, jsonb) to authenticated;

-- ================= 4. REPORTS =================

-- Students send only review_id and reason. reporter_id always comes from the
-- default auth.uid(), so nobody can report in someone else's name.
revoke all on public.reports from anon, authenticated;
grant insert (review_id, reason) on public.reports to authenticated;

create policy "PCC students can report visible reviews"
  on public.reports for insert to authenticated
  with check (
    reporter_id = (select auth.uid())
    and (select private.is_pcc_student())
    and exists (select 1 from public.reviews r where r.id = review_id)  -- visible ones only (RLS)
  );

-- ================= 5. AUTO-HIDE AT 3 REPORTS =================

create function private.hide_reported_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Lock the review first, so two reports arriving at once both see each other.
  perform 1 from public.reviews where id = new.review_id for update;

  update public.reviews r
  set is_hidden = true
  where r.id = new.review_id
    and not r.is_hidden
    and (select count(*) from public.reports p where p.review_id = new.review_id) >= 3;

  return null;
end;
$$;

revoke all on function private.hide_reported_review() from public, anon, authenticated;

create trigger reports_auto_hide
  after insert on public.reports
  for each row execute function private.hide_reported_review();

-- ================= 6. LOCK-DOWN =================

-- RLS already blocks these (no write policies), but remove the privileges too,
-- so a future policy mistake can't open a write path by accident.
revoke insert, update, delete, truncate, references, trigger
  on public.professors, public.courses, public.reviews,
     public.review_dimensions, public.dimensions
  from anon, authenticated;

commit;
