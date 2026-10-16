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
   - **Security:** RLS is on for every table. So far there are only *read* policies: anyone can read professors, courses, visible reviews and their dimensions. Nobody can write through the API yet, and nobody can read `reports`.
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

### Step 2: Decide the review questions (Jack decides)

This step is a decision, not code. Jack lists the dimensions, about 5–10, each with a low and a high pole. For example:
- grading: lenient ↔ strict
- workload: light ↔ heavy
- attendance: optional ↔ required
- clarity: unclear ↔ clear

The list then gets enforced in the database (a `check` constraint or a small `dimensions` table) and reused by the form, the app and the sentence templates.

Also decide:
- Keep `quality` and `difficulty` (1–5)?
- Should a skipped question be stored as nothing, or as 0?

### Step 3: Write side and moderation ⚠️ (finishes phase 1)

Put this in a new file, `supabase/002_write_side.sql`.

- **`submit_review(...)` function.** One call saves a review and its dimension answers atomically.
  - `security definer`, with `set search_path = ''`.
  - Checks that the caller is signed in with an `@go.pasadena.edu` email (from `auth.jwt()`, lowercased).
  - Validates dimension names against the step 2 list.
  - Inserts with `author_id = auth.uid()`.
  - No direct insert policies on `reviews` or `review_dimensions`, so this function is the only way in.
- **Report insert policy.** Signed-in PCC users can insert into `reports` with `reporter_id = auth.uid()`. The table is already unique per review per reporter.
- **Auto-hide trigger.** After an insert on `reports`, if the review has 3 or more reports, set `reviews.is_hidden = true`. Use a `security definer` function with an empty `search_path`.
- **Auth settings** (dashboard, not SQL):
  - Turn on email one-time codes.
  - Block sign-ups from non-PCC domains if Supabase offers a hook for it. The domain check in `submit_review` is the real guarantee either way.
- **Test:** use the role dropdown and a test PCC account.
  - A submission works, and a second one for the same professor and course is rejected.
  - A non-PCC email is rejected.
  - 3 reports hide the review, and it disappears from the counts view.
- Re-run **Advisors → Security Advisor** and fix anything it flags.

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

- **Phase 3:** a review form on BYE_website (Cloudflare Workers, behind Cloudflare Access). It calls `submit_review`.
- **Phase 4:** reviews from BYE's own database shown in the Mac app, next to the RMP data.
- **Phase 5:** posters and student government outreach.
- **Later:**
  - Fill in `rmp_id` to link each professor to their RMP page.
  - Show fewer RMP reviews as BYE's own reviews grow.
  - An admin moderation queue and an auto-filter for personal info.

## Open questions for Jack

1. The dimension list and its poles (step 2).
2. Keep `quality` and `difficulty`?
3. Store a skipped question as 0, or leave it out?
4. Two professors with the same full name are merged by the seed script. Is that acceptable for now?
5. `supabase-swift` package or plain `URLSession` for step 5?
