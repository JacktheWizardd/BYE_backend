-- Checks for 002_write_side.sql. Run each block by hand in the SQL Editor,
-- one statement at a time (select the statement, then Run), with the role shown.
-- Expected errors must be run separately so they do not roll back earlier tests.
--
-- Setup (dashboard, Authentication -> Users -> Add user -> "Auto Confirm User"):
--   test1@go.pasadena.edu, test2@go.pasadena.edu, test3@go.pasadena.edu, test@example.com
-- These users are for testing; no email delivery is needed for these checks. Deleting the users at the end also
-- deletes their test reviews and reports (on delete cascade).

-- ---- A. Role: postgres --------------------------------------------------
-- Expect 7 rows, grading first.
select * from public.dimensions order by sort_order;

-- ---- B. Role: authenticated, impersonating test1@go.pasadena.edu --------
-- B1. Expect a uuid back. SAVE IT. Replace every PASTE_TEST_REVIEW_UUID below
-- with this UUID before running the later statements. Do not submit B1 again.
select public.submit_review(
  (select min(id) from public.professors),
  (select min(id) from public.courses),
  4, 3, 'Test review, please ignore.',
  '{"grading": 1, "workload": -1, "clarity": 0}'
);

-- B2. Same again. Expect: "You already reviewed this professor for this course."
select public.submit_review(
  (select min(id) from public.professors),
  (select min(id) from public.courses),
  4, 3, null, '{}'
);

-- B3. Expect: "Unknown question or answer not -1, 0 or 1: grading, vibes"
select public.submit_review(
  (select max(id) from public.professors),
  (select min(id) from public.courses),
  4, 3, null, '{"grading": 2, "vibes": 1}'
);

-- B4. Direct writes. Expect "permission denied" for each.
insert into public.reviews (professor_id, course_id, quality, difficulty)
  values ((select min(id) from public.professors), (select min(id) from public.courses), 5, 1);
update public.reviews set is_hidden = true;
delete from public.professors;

-- B5. Expect the test review with 3 answers. Public queries must name the
-- allowed columns: SELECT * would also request the private author_id.
select id, professor_id, course_id, created_at, quality, difficulty, body, is_hidden
from public.reviews
where id = 'PASTE_TEST_REVIEW_UUID'::uuid;
select * from public.review_dimensions
where review_id = 'PASTE_TEST_REVIEW_UUID'::uuid;
select * from public.professor_dimension_counts;

-- B6. Expect permission denied: reviewer identities must stay private.
select author_id from public.reviews;

-- ---- C. Role: authenticated, impersonating test@example.com -------------
-- Expect: "Sign in with your @go.pasadena.edu email to post a review."
select public.submit_review(
  (select max(id) from public.professors),
  (select min(id) from public.courses),
  3, 3, null, '{}'
);

-- Expect "new row violates row-level security policy" (not a PCC student).
insert into public.reports (review_id, reason)
  values ('PASTE_TEST_REVIEW_UUID'::uuid, 'test');

-- ---- D. Reports: run in the exact order below --------------------------
-- D1. authenticated, impersonating test1@go.pasadena.edu. Expect success.
insert into public.reports (review_id, reason)
  values ('PASTE_TEST_REVIEW_UUID'::uuid, 'test');

-- D2. Still test1: expect duplicate key (one report per person).
-- Run BEFORE the review is hidden; hidden reviews cannot be reported.
insert into public.reports (review_id, reason)
  values ('PASTE_TEST_REVIEW_UUID'::uuid, 'test');

-- D3. authenticated, impersonating test2@go.pasadena.edu. Expect success.
insert into public.reports (review_id, reason)
  values ('PASTE_TEST_REVIEW_UUID'::uuid, 'test');

-- D4. Still test2: expect 1 visible review (two reports do not hide it).
select id from public.reviews where id = 'PASTE_TEST_REVIEW_UUID'::uuid;

-- D5. authenticated, impersonating test3@go.pasadena.edu. Expect success.
insert into public.reports (review_id, reason)
  values ('PASTE_TEST_REVIEW_UUID'::uuid, 'test');

-- D6. Still test3: expect 0 rows from the review and its answers.
select id from public.reviews where id = 'PASTE_TEST_REVIEW_UUID'::uuid;
select * from public.review_dimensions
where review_id = 'PASTE_TEST_REVIEW_UUID'::uuid;
-- With only this test review, expect 0 rows. Existing real reviews may still count.
select * from public.professor_dimension_counts
where professor_id = (select min(id) from public.professors);

-- ---- E. Role: postgres ---------------------------------------------------
-- Expect exactly the saved test review, is_hidden = true and 3 reports.
select r.id, r.is_hidden, count(p.id) as reports
from public.reviews r left join public.reports p on p.review_id = r.id
where r.id = 'PASTE_TEST_REVIEW_UUID'::uuid
group by r.id;

-- Cleanup: after Jack approves, delete ONLY the 4 test users in Authentication
-- -> Users. This cascades their test reviews, answers and reports.
-- Then expect 0 for each; real reviews are not part of these counts.
select count(*) from public.reviews
where id = 'PASTE_TEST_REVIEW_UUID'::uuid;
select count(*) from public.review_dimensions
where review_id = 'PASTE_TEST_REVIEW_UUID'::uuid;
select count(*) from public.reports
where review_id = 'PASTE_TEST_REVIEW_UUID'::uuid;
