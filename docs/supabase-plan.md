# BYE Review Database: Status and Plan

Oct 16, 2026 · handoff for Claude Code / Codex

## Ground rules (from Jack)

- **Privacy:** no cloud AI, no credentials in the app, minimal requests to RMP.
- **RMP risk:** stay free, link back, rate-limited. The review DB exists so BYE can eventually stop depending on RMP.
- **Explain every change in plain language.** Jack designs, tests and decides; agents write the code.
- **Ask before big or risky changes**, especially anything that writes to the live database or changes security rules.
- Follow `AGENTS.md`: claim work with `scripts/agents.py`, run `./scripts/build-test-app.sh` after Mac app changes.

## Where things stand

### Done

1. **Supabase project "BYE"** (free tier, `main` branch = production).
2. **Schema v1 is live.** It's saved in [`supabase/schema.sql`](../supabase/schema.sql) and was run once in the SQL Editor.
   - **Tables:**
     - `professors` and `courses` (the lists)
     - `reviews` (1–5 quality and difficulty, text up to 2,000 characters, `is_hidden`, one review per student per professor per course)
     - `review_dimensions` (one row per answered question, value −1/0/1)
     - `reports`
   - **Security:** RLS is on for every table. Anyone can read professors, courses, visible reviews and their dimensions. Confirmed PCC users can submit reviews through `submit_review` and insert reports through the restricted reporting policy. App users cannot read `reports` or modify the other tables directly.
   - **Anonymity:** column privileges hide `reviews.author_id` from the app.
   - **Counts view:** `professor_dimension_counts` (`security_invoker = true`) returns `high_count`, `low_count` and `answered` per professor per dimension, counting visible reviews only.
   - **Index:** `reviews (professor_id, created_at desc) where not is_hidden`, which serves both the counts and the newest-first review lists.
3. **Seed script written:** [`scripts/pcc_seed.py`](../scripts/pcc_seed.py). (Rewritten on Oct 16 after the original was lost in the machine move.)
   - It reads PCC's public schedule API (`prod-apiweb.pasadena.edu`), the same source the app already uses. It makes zero RMP requests.
   - It writes `pcc_seed.sql` with `courses` and `professors` inserts. It's safe to re-run, because existing rows are skipped.
   - It never connects to Supabase. Jack pastes the SQL into the SQL Editor.
   - Surname particles (De La, van, Mc, St.) and suffixes (III, Jr.) stay on the last name. Names that may hide a double surname or middle name are listed for a hand check.
   - Retries slow PCC responses (120-second limit) and trusts the macOS certificate bundle, so it works with python.org's Python.
4. **PCC data loaded (Oct 16):** Jack ran the seed in the SQL Editor. It came from all 10 published terms (Winter 2025 to Spring 2027): about 1,531 courses and 1,425 professors.

### Key design decisions

| Decision | Why |
| --- | --- |
| Fisher's exact test and Benjamini–Hochberg run **in Swift, on the Mac** | Free, instant, deterministic, unit-testable. The server only counts. |
| Dimensions come from **structured form questions**, not detected from review text | Counting becomes a cheap query, and results stay deterministic. |
| Denominator is `answered`, not total reviews | Skipped questions don't count as "not strict." |
| `security_invoker` view and a hidden `author_id` | The view obeys RLS, and one student's reviews can't be linked together. |
| No caching or materialized view yet | Counting two professors through the index takes milliseconds at PCC scale. Revisit only if it gets slow. |
| Course titles kept in PCC's capitals | Title case breaks acronyms ("CALCULUS II" → "Calculus Ii"). Format in the app instead. |

## Plan

Each step ends with something Jack can test. Steps marked ⚠️ change the live database or its security, so show Jack the SQL and explain it before he runs it.

### Step 1: Load PCC data (phase 2) ✅ done Oct 16

1. Jack runs `python3 scripts/pcc_seed.py` in his own Terminal. Agent sandboxes can't reach PCC.
2. Review the "Check how these names were split" output. Fix bad splits in `pcc_seed.sql` by hand.
3. ⚠️ Jack runs `pbcopy < pcc_seed.sql`, then pastes and runs it in the SQL Editor.
4. **Test:** Table Editor shows rows. Switch the role dropdown to **anon** and confirm the rows are still readable.
5. Commit `supabase/schema.sql`, `scripts/pcc_seed.py` and this doc. Don't commit `pcc_seed.sql`, because it's regenerated each semester. Add it to `.gitignore`.

### Step 2: Decide the review questions ✅ decided Oct 16

Each question is answered low (−1), neutral (0) or high (+1). The list lives in a small `dimensions` table, so the form, the app and the sentence templates all read the same names and labels.

| `dimension` | Low (−1) | High (+1) |
| --- | --- | --- |
| `grading` | lenient | strict |
| `workload` | light | heavy |
| `attendance` | optional | required |
| `clarity` | unclear | clear |
| `feedback_speed` | slow | fast |
| `test_alignment` | rarely match class | closely match class |
| `textbook` | optional | required |

- **Keep `quality` and `difficulty` (1–5).** Students know them from RMP, and they're already in the live schema.
- **A skipped question is stored as nothing (no row).** 0 means a real "in the middle" answer, and the math counts only answered questions.

### Step 3: Write side and moderation ⚠️ (finishes phase 1)

**Applied and core behavior verified by Jack on Oct 16:** [`supabase/002_write_side.sql`](../supabase/002_write_side.sql), with hand checks in [`supabase/002_write_side_checks.sql`](../supabase/002_write_side_checks.sql). The applied migration also:
- Adds the step 2 `dimensions` table, which answers must reference.
- Keeps the PCC email rule in one helper, `private.is_pcc_student()`. It reads `auth.users` and requires a confirmed email, and it lives in a schema the API doesn't expose.
- Lets students send only `review_id` and `reason` when reporting, so `reporter_id` always comes from the login.
- Removes insert, update and delete privileges from the app on every other table.

Jack’s initial read-only check returned `false` for both `dimensions` and `submit_review`. He then ran the migration successfully and verified all seven questions. The live tables were also empty, despite the earlier handoff reporting the seed as loaded. Jack ran the existing seed and confirmed 1,425 professors and 1,531 courses. Do not recreate or reset these tables.

The manual checks now use permitted review columns, target the saved test UUID, and test duplicate reporting before the third report hides the review. The migration explicitly grants read access to the new dimensions table.

**Local validation (Codex, Oct 16):** 51 checks passed in an isolated PGlite PostgreSQL engine using the actual schema and migration, with mocked Supabase auth users/roles/default grants. Covered eligibility (including unconfirmed and misleading-domain emails), validation, atomic failures, hidden author IDs, denied direct writes, counts, reporting, auto-hide, and cascading test-user cleanup. This does not replace live Supabase checks or test concurrent reporting; these local checks made no live database changes.

- **`submit_review(...)` function.** One call saves a review and its dimension answers atomically.
  - `security definer`, with `set search_path = ''`.
  - Checks the caller’s current confirmed `@go.pasadena.edu` email in `auth.users`, using `private.is_pcc_student()`.
  - Validates dimension names against the step 2 list.
  - Inserts with `author_id = auth.uid()`.
  - No direct insert policies on `reviews` or `review_dimensions`, so this function is the only way in.
- **Report insert policy.** Signed-in PCC users can insert into `reports` with `reporter_id = auth.uid()`. The table is already unique per review per reporter.
- **Auto-hide trigger.** After an insert on `reports`, if the review has 3 or more reports, set `reviews.is_hidden = true`. Use a `security definer` function with an empty `search_path`.
- **Auth settings** (dashboard, not SQL):
  - Configure the email template for one-time codes (`{{ .Token }}`), keep email confirmation enabled, and verify real delivery. Jack reported saving Resend SMTP and both code templates, then completed a real website submission. The email-confirmation setting still needs explicit review.
  - Configure a delivery provider for student emails: Supabase’s default email service only sends to project-team addresses. See [Supabase SMTP documentation](https://supabase.com/docs/guides/auth/auth-smtp). **Done October 17, 2026:** custom SMTP now uses Brevo (`smtp-relay.brevo.com:587`, sender `BYE` <byebeforeyouenroll@gmail.com>, free plan 300 emails/day; SMTP key expires 2027-10-17 or after 90 days without sending). Jack received a production code through it. Details: [Review launch record](review-launch-record.md).
  - Block sign-ups from non-PCC domains if Supabase offers a hook for it. The domain check in `submit_review` is the real guarantee either way.
- **Test:** use the role dropdown and a test PCC account.
  - A submission works, and a second one for the same professor and course is rejected.
  - A non-PCC email is rejected.
  - 3 reports hide the review, and it disappears from the counts view.
- **Security Advisor reviewed:** the two `rls_auto_enable` warnings were fixed by `003_helper_permissions.sql`. The remaining authenticated `submit_review` warning is intentional and reviewed. Do not revoke that function’s app access merely to silence the warning.

### Step 4: Fisher's exact test in Swift (no database needed)

Put this in `ClasswiseCore`, as a self-contained file such as `Significance.swift`. It's a good one for Jack to write himself.

- `fisherExactTwoSided(a: k1, n1, b: k2, n2) -> Double`, computed from the hypergeometric formula with log-factorials.
- `benjaminiHochberg(pValues:alpha:) -> [Bool]`.
- Test each pole separately: strict A vs B, then lenient A vs B.
- **Unit tests against scipy values:**

  | A | B | p |
  | --- | --- | --- |
  | 1/2 | 0/3 | 0.40 |
  | 8/20 | 1/15 | 0.048 |
  | 6/20 | 2/15 | 0.42 |
  | 10/20 | 2/20 | 0.014 |

- **Sentence rules:**
  - Keep rows visible when p is above the cutoff, and drop only the verdict sentence.
  - Write "no clear difference," never "equally strict."
  - Start with a 0.05 cutoff plus Benjamini–Hochberg.

### Step 5: Read the counts in the Mac app

- Add a small Supabase reader: plain `URLSession` against the REST endpoint, or the `supabase-swift` package. Ask Jack which before adding a dependency.
  - It ships only the project URL and the **publishable/anon key**. That key is meant to be public, because RLS protects the data.
  - **Never** put the `service_role` / secret key in the app or the repo.
- One request per comparison: `professor_dimension_counts?professor_id=in.(A,B)`. Cache the result per session.
- Keep RMP data as-is for now. If Supabase is unreachable, the app still works.
- **Test:** seed a few fake reviews in a test setup, compare two professors, and check that the sentences match the Fisher tests.

### Step 6 onward (later phases)

- **Phase 3:** the website form and BYE reading/reporting integration are implemented locally using Pages Functions and school-email sessions. Hosted rollout remains pending; owner-only mutations do not require a site-wide Cloudflare Access gate.
- **Phase 4:** reviews from BYE's own database shown in the Mac app, next to the RMP data.
- **Phase 5:** posters and student government outreach.
- **Later:**
  - Fill in `rmp_id` to link each professor to their RMP page.
  - Show fewer RMP reviews as BYE's own reviews grow.
  - An admin moderation queue and an auto-filter for personal info.

## Open questions for Jack

1. ~~The dimension list and its poles~~ Decided in step 2.
2. ~~Keep `quality` and `difficulty`?~~ Kept.
3. ~~Store a skipped question as 0, or leave it out?~~ Left out.
4. Two professors with the same full name are merged by the seed script. Is that acceptable for now?
5. `supabase-swift` package or plain `URLSession` for step 5?


## Live validation follow-up (Oct 16, Codex + Jack)

Jack ran the checks in the Supabase dashboard and reported these results:

- PCC test user submitted a review with grading +1, workload -1 and clarity 0.
- A duplicate submission and invalid answers were rejected.
- Direct review updates and reads of author_id were denied for authenticated users.
- Public review fields and the three answers were readable; dimension counts matched.
- A non-PCC test user could neither submit nor report a review.
- First report succeeded; a repeated report by the same user was rejected.
- Review remained visible with two distinct reports; three distinct reports hid it.
- Hidden review, its answers, and its counts disappeared from authenticated reads.
- postgres confirmed is_hidden=true and exactly three reports.
- Jack deleted the four temporary users and confirmed the test review, answers and reports were gone.

Security Advisor reported two warnings for public.rls_auto_enable() and the expected authenticated submit_review warning. Jack supplied the helper definition: it enables RLS on newly created public tables through an event trigger. Jack approved removing app execute permissions. The prepared follow-up is supabase/003_helper_permissions.sql; Jack ran it successfully and refreshed Security Advisor. Both helper warnings disappeared; only the reviewed, intentional authenticated `submit_review` warning remains. Four isolated PGlite checks passed: anon/authenticated cannot execute after revocation, the owner retains access, and automatic RLS still works on a newly created table.

Email-code login remains the intended simple flow: enter a PCC email, receive a code, enter it in BYE. No student password, profile page, or account-management screens are required. Supabase maintains the user identity behind the scenes. This verifies control of a school mailbox, not current enrollment or attendance in a particular class. The sibling website repository now has a locally implemented owner-only `/reviews/` form and same-origin Pages API. The UI uses real email-code authentication, short-lived HttpOnly cookies, catalog searches and the existing submit_review RPC. Local fixture tests passed, and Jack completed a real email-code submission. Administrator cleanup confirmation and hosted preview deployment remain pending. Dashboard template/settings have not been changed by the agent. See `BYE_website/docs/REVIEW_SUBMISSION.md` for setup and `REVIEW_VERIFICATION.md` for evidence.


## Plain language guide

See [BYE review database explained](review-database-explained.md) for what the database does, the email-code login plan, privacy limits, completed checks, and remaining work. The database and permission tests are complete, and local website login/submission succeeded. Hosted rollout, cleanup confirmation, and Mac integration remain pending.


## Website review submission follow-up

Implemented locally in the sibling website repo on Oct 16: `/reviews/` with email-code verification, explicit course/professor selection, the seven optional questions, final confirmation and a receipt; server-only Supabase SDK with owner-email restriction; Secure HttpOnly access-token sessions; input/origin validation and no automatic submission retries. The existing database schema and policies were reused. 61 website unit tests, review/browser fixture acceptance and local Cloudflare runtime checks passed; a read-only real-catalog probe returned the expected 1,425 professors, 1,531 courses and seven questions. Email-delivery configuration, real owner submission/cleanup and hosted preview acceptance remain unverified. No deployment, native app changes or commit occurred.


### Real website test result (Oct 16)

Jack completed the local website sign-in and submission flow and supplied the
receipt ID. Read-only checks found that exact temporary review and all seven
answers; the professor counts matched, including neutral answers. The test label
was present. Cleanup of that one review is prepared but not yet confirmed. Keep
Jack’s real school account. Hosted deployment and confirmation-setting review
remain pending. No code, password, token, or review comment was recorded here.


### Full website integration follow-up

The website now connects live PCC browsing with separate BYE and RMP review
sections, BYE quality/difficulty averages, course filters, paginated reading,
verified form prefilling and owner-only reporting. Existing SQL and permissions
are reused; no migration or live write was made for this integration. AI summaries
and statistical comparisons remain disabled. Real local PCC reads and BYE catalog
reads passed; RMP access and hosted rollout remain pending. The earlier test review
is no longer publicly visible; administrator confirmation of its deletion is
still needed. See the website repo’s docs/LIVE_APP_PREVIEW.md.
