-- BYE review database, schema v1 (run in Supabase SQL Editor on Oct 16, 2026).
-- Read side only: tables, RLS read policies, hidden author_id, counts view.
-- The write side (submit_review, auto-hide on 3 reports) comes in a later file.

-- ================= 1. TABLES =================

create table public.professors (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  first_name  text not null,
  last_name   text not null,
  department  text,
  rmp_id      text unique
);

create table public.courses (
  id     bigint generated always as identity primary key,
  code   text not null unique,          -- e.g. 'CS 002'
  title  text not null
);

create table public.reviews (
  id            uuid primary key default gen_random_uuid(),
  professor_id  bigint not null references public.professors(id),
  course_id     bigint not null references public.courses(id),
  author_id     uuid not null default auth.uid()
                  references auth.users(id) on delete cascade,
  created_at    timestamptz not null default now(),
  quality       smallint not null check (quality between 1 and 5),
  difficulty    smallint not null check (difficulty between 1 and 5),
  body          text check (char_length(body) <= 2000),
  is_hidden     boolean not null default false,
  unique (author_id, professor_id, course_id)
);

create table public.review_dimensions (
  review_id  uuid not null references public.reviews(id) on delete cascade,
  dimension  text not null,             -- 'grading', 'workload', ...
  value      smallint not null check (value between -1 and 1),
  primary key (review_id, dimension)
);

create table public.reports (
  id           bigint generated always as identity primary key,
  review_id    uuid not null references public.reviews(id) on delete cascade,
  reporter_id  uuid not null default auth.uid()
                 references auth.users(id) on delete cascade,
  reason       text check (char_length(reason) <= 500),
  created_at   timestamptz not null default now(),
  unique (review_id, reporter_id)
);

-- Fast lookup: visible reviews for one professor, newest first
create index reviews_visible_by_professor
  on public.reviews (professor_id, created_at desc)
  where not is_hidden;

-- ================= 2. SECURITY (RLS) =================

alter table public.professors        enable row level security;
alter table public.courses           enable row level security;
alter table public.reviews           enable row level security;
alter table public.review_dimensions enable row level security;
alter table public.reports           enable row level security;

create policy "Anyone can read professors"
  on public.professors for select to anon, authenticated using (true);

create policy "Anyone can read courses"
  on public.courses for select to anon, authenticated using (true);

create policy "Anyone can read visible reviews"
  on public.reviews for select to anon, authenticated using (not is_hidden);

create policy "Anyone can read dimensions of visible reviews"
  on public.review_dimensions for select to anon, authenticated
  using (exists (select 1 from public.reviews r where r.id = review_id));

-- Keep reviewers anonymous: the app can never read author_id
revoke select on public.reviews from anon, authenticated;
grant select (id, professor_id, course_id, created_at,
              quality, difficulty, body, is_hidden)
  on public.reviews to anon, authenticated;

-- ================= 3. COUNTS VIEW (for Fisher's test) =================

create view public.professor_dimension_counts
with (security_invoker = true) as
select r.professor_id,
       d.dimension,
       count(*) filter (where d.value =  1) as high_count,
       count(*) filter (where d.value = -1) as low_count,
       count(*)                             as answered
from public.reviews r
join public.review_dimensions d on d.review_id = r.id
where not r.is_hidden
group by r.professor_id, d.dimension;
