# Codex prompt: BYE student numbers backend

October 21, 2026. Written by Claude Code for the owner to paste into Codex as one message. Companion to [the backend handoff](bye-numbers-backend-handoff.md).

````text
You are Codex, BYE's backend, database and security engineer. Claude Code (frontend) built a new feature, "BYE student numbers", and handed the backend to you. Your job: review, harden, rehearse and then take it live, stopping for my explicit go-ahead before every production action. I am the owner. Read this whole prompt before doing anything.

=== 1. WHAT THE FEATURE IS ===
Every BYE student ID card in the Mac app (and Windows, later) shows a hard-coded "BYE-0001". Students can now optionally get their own number tied to their PCC school email. It shows on the card as "BYE-0042 · Student 42 of 57".
- Optional. Skipping keeps every feature; the card shows "BYE-····".
- It uses the live review sign-in: Supabase email OTP, @go.pasadena.edu only, no "+" aliases. The rule already lives in private.is_pcc_student() (supabase/006).
- Number 1 is always mine (the owner's). Automatic numbering starts at 2. The same account always gets the same number.
- Students see the total ("Student 42 of 57"). The total is a public count, never who.
- The number is keyed by Supabase account UUID (auth.users.id), never by email. The planned email-free sign-in (supabase/migrations/20261021023510_private_review_verification.sql, website code reverted in 2fed520) keeps account UUIDs in its backfill, so numbers must survive that migration.
- Mac 0.5.0 (SwiftUI, last native release before Tauri) waits on this backend going live.

=== 2. CURRENT STATE (all uncommitted, nothing deployed or run against Supabase) ===
Read first: BYE_Before_You_Enroll/docs/bye-numbers-backend-handoff.md, then each file below.

App repo (/Users/thewizard/Documents/Project/BYE/BYE_Before_You_Enroll, branch main):
- supabase/007_bye_numbers.sql. SQL Editor style like 006, intended to be safe to repeat. It adds:
  - private.bye_number_seq (start 2, minvalue 2)
  - private.bye_numbers (user_id uuid PK → auth.users(id) ON DELETE RESTRICT, number int unique > 0, created_at)
  - public.claim_bye_number(), which:
    - is plpgsql, security definer, search_path '' and #variable_conflict use_column;
    - requires private.is_pcc_student();
    - inserts with nextval and ON CONFLICT (user_id) DO NOTHING;
    - returns table(number int, total int);
    - is granted to authenticated only.
  - public.bye_number_count(), granted to anon and authenticated.
  - A commented owner step at the end: insert the owner's account with number 1.
- Mac client (Claude-owned, do not edit): Sources/ClasswiseCore/ByeNumbers.swift (ByeNumberClient), Sources/Classwise/* UI, Tests/ClasswiseCoreTests/ByeNumberTests.swift. Read them only to understand the contract.

Website repo (/Users/thewizard/Documents/Project/BYE/BYE_website, branch main, otherwise matching origin/main):
- server/reviews.ts:
  - methods map adds number:'POST' and numbers:'GET'
  - LIMITS adds number 10/hour and numbers 60/hour per IP
  - GET numbers → client(config).rpc('bye_number_count') → { total }
  - POST number (after the existing session and eligible() checks) → supabase.rpc('claim_bye_number') → { number, total }
  - 42501/PGRST301/PGRST303 → sessionError(); anything else invalid → 503 NUMBER_UNAVAILABLE
- tests/review-fixtures.ts (fixtures for both RPCs) and tests/bye-numbers.test.ts (5 tests).
- apps/landing/src/sections/About.tsx (privacy lines) and the rebuilt public/index.html and public/site/index-*.js.
- AGENTS.md ("Change with care" note and a "Current state" entry).

Your relocation worktrees (BYE_frontend_relocation, BYE_backend_relocation, branch codex/backend-relocation) do NOT have these routes yet. There, server/reviews.ts became services/web-api/src/reviews.ts behind platform/forward.ts and the WEB_API binding.

=== 3. CONTRACT THE MAC APP DEPENDS ON (do not change shapes, paths, methods or cookie names) ===
BYE numbers:
1. POST /api/reviews/auth/send with {"email"} → {data:{sent,retryAfter}}
2. POST /api/reviews/auth/verify with {"email","code"} → {data:{signedIn:true,...}}, plus Set-Cookie "__Secure-bye-review=<jwt>" ("bye-review-local" on loopback). The app keeps the cookie in memory only.
3. POST /api/reviews/number with body {} and that Cookie → {data:{number,total}}. The app then drops the cookie and stores only the number.
4. GET /api/reviews/numbers with no cookie and no Origin, at most once a day → {data:{total}}

Every POST sends Origin: <site origin> and Content-Type: application/json. Errors are read from {error:{message}} and shown to students verbatim, so messages must stay student-friendly.

BYE reviews (already used by the Mac 0.5.0 build): GET /api/reviews/resolve?instructor&course, GET /api/reviews/profile?professorId and GET /api/reviews/list?professorId&sort&offset[&courseId], public, no cookies.

Turnstile must stay off in production. If TURNSTILE_* is set, native auth/send fails, because the app can't solve the check.

=== 4. GROUND RULES ===
- Follow /Users/thewizard/Documents/Project/BYE/AGENTS.md and each repo's AGENTS.md.
- Use the coordination board from the app repo:
  - start: python3 -I scripts/agents.py inbox codex, then start codex "BYE numbers backend: review, rehearse, port, go live" --files <absolute paths>
  - log progress with update codex "..." and finish with done codex "..."
  - Claude's claim on these files has been released.
- Do not edit Claude's Swift files, the Mac UI or .agents/. If the contract must change, stop and tell me why before changing anything.
- Testing uses fixtures and local databases only. The ONLY live actions are the gated go-live steps in section 6, each after my go-ahead.
- Never commit, push, deploy, run SQL against production, create or delete production auth users, or change Supabase/Brevo/Cloudflare settings without my explicit go-ahead for that specific action in chat. Approval for one step does not carry over to the next.
- Don't print, log or write my school email or anyone's address into files, board entries or commit text. When you need my email for the owner step, ask me in chat and use it only in that SQL statement.
- Never read or print secrets (Supabase service keys, Brevo keys, signing keys). If a step needs a credential you don't have, stop and ask how I want to provide access.

=== 5. WORK BEFORE GO-LIVE (no production access needed) ===
A. ORIENT
- Read the handoff doc, 007, 002_write_side.sql, 002_write_side_checks.sql, 003_helper_permissions.sql, 006, both private-review migrations, docs/private-review-verification.md, BYE_website/server/reviews.ts, server/bye-reviews.ts and the new tests.
- Record on the board that you started.

B. SQL REVIEW of 007. Fix what's wrong and explain each change. Check at least:
1. Correctness: the plpgsql OUT parameters (number, total) versus column names; that #variable_conflict use_column plus qualified b.number really avoids ambiguity, including in INSERT ... ON CONFLICT (user_id).
2. Concurrency: two simultaneous claims by one user → one row, the same number. Simultaneous claims by different users → distinct numbers. A gap from a lost race is acceptable; say so in the file.
3. Security:
   - security definer owned by postgres; search_path '' with every reference schema-qualified;
   - auth.uid() is used correctly;
   - grants: claim to authenticated only, count to anon and authenticated, nothing on the table or sequence for anon or authenticated;
   - confirm the private schema is NOT in Supabase's exposed API schemas;
   - check whether public.rls_auto_enable() (002/003) or any event trigger affects the new table, and whether that matters for a security-definer owner.
4. Re-runs: create ... if not exists won't alter an existing table. Make sure a second run is harmless and grants are re-stated.
5. Owner number 1:
   - the sequence never yields 1;
   - the owner step inserts 1, or moves an already-claimed number to 1, without colliding with the unique constraint;
   - make the commented owner step safe and clear.
6. ON DELETE RESTRICT versus CASCADE:
   - RESTRICT blocks the "delete test users" cleanup in 002_write_side_checks.sql and any future account or email cleanup from the private-verification plan.
   - Weigh losing numbers (CASCADE) against blocked deletes (RESTRICT), and how numbers would migrate to review_private.identities.
   - Recommend one, explain it to me in plain words, and apply it only after I answer.
7. Totals: the count is fine at BYE's scale. Note it if you'd change it.

C. LOCAL REHEARSAL. This Mac has no psql, Postgres or Docker.
- Set up a disposable local database (for example Homebrew postgresql@17, or PGlite / embedded Postgres via npm). Install only what's needed and tell me what you installed.
- Stub the Supabase pieces 007 relies on: an auth schema with a users table and auth.uid() reading a session setting, the anon and authenticated roles, and private.is_pcc_student() from 002 plus 006.
- Rehearse, as the right roles:
  - a first claim → 2;
  - a repeat → the same number;
  - a second student → 3;
  - non-PCC, unconfirmed and "+" alias accounts → 42501;
  - anon cannot claim but can count;
  - authenticated cannot read or write private.bye_numbers or the sequence directly;
  - the owner step gives 1, and the next new student still gets the next sequence number;
  - concurrent claims (two sessions);
  - re-running 007 keeps the data;
  - the delete behavior you recommend.
- Keep the rehearsal script in the repo where it fits (for example scripts/ or supabase/), with a short how-to-run note. No network.
- Write supabase/007_bye_numbers_checks.sql in the style of 002_write_side_checks.sql: blocks to run by hand in the SQL Editor, roles named, expected results, and cleanup that works with your delete choice.

D. WEBSITE ROUTE REVIEW (BYE_website main checkout)
Review number and numbers in server/reviews.ts as a security reviewer:
- order relative to the config check, HTTPS check, POST Origin check and per-IP rate limit;
- that number requires the session plus eligible() before any RPC;
- whether number should validate Content-Type, body size or empty JSON the way jsonBody does for other POSTs, given the Mac sends {};
- error mapping, and that no upstream error, email or token reaches the response or the logs;
- Cache-Control no-store and the rest of the commonHeaders;
- whether the public count needs anything more than the per-IP limit.

Add any missing tests, especially a POST number without Origin → 403. Then run, from the website root:
- corepack pnpm install --frozen-lockfile
- corepack pnpm typecheck
- corepack pnpm test
- corepack pnpm build

If the rebuild rewrites public/reviews/index.html with only line-ending changes, restore it.

E. RELOCATION PORT (your worktrees; go-live does NOT wait for this)
- Port both routes, the fixtures and the tests into BYE_backend_relocation/services/web-api (src/reviews.ts, tests/).
- Confirm platform/forward.ts passes through, unchanged, everything the app needs: Origin, Cookie, Content-Type and the request body, and in responses Set-Cookie, Cache-Control and Retry-After.
- Add number and numbers, plus the Mac's resolve, profile and list reads, to your fixture runtime acceptance (scripts/review-runtime-acceptance.mts or equivalent) through the forwarder.
- Note it in your relocation provenance doc. Do not deploy the relocation.

F. EMAIL CAPACITY
Supabase sends OTP email through Brevo SMTP (key expires 2027-10-17).
- Find, without reading or printing any secret:
  - the Brevo plan's daily limit (free is about 300 a day);
  - Supabase Auth's email rate limits;
  - whether either throttles a busy enrollment day.
- If you need dashboard access to check, ask me first.
- Recommend changes. Don't apply them.

Before section 6, send me a report:
- what you changed and why;
- the ON DELETE recommendation (as a question for me);
- the rehearsal results and checks run;
- what's still untested;
- the email capacity findings.
Then wait.

=== 6. GO-LIVE (each step needs my explicit go-ahead in chat for that step) ===
For each step:
- before it: show the exact SQL or command, what it changes, how to undo it, and what you'll check afterwards;
- after it: report the results.

G1. Preflight, read-only, against production (needs my go-ahead because it touches production). Confirm:
- private.is_pcc_student() includes the "+" rule;
- the private schema exists;
- 007 objects don't exist yet, or match;
- REVIEWS_ENABLED and REVIEW_ACCESS=students are live: GET https://bye-before-you-enroll.pages.dev/api/reviews/status returns enabled true and ownerTest false;
- Turnstile is off: the status has no turnstileSiteKey.

G2. Run the final 007_bye_numbers.sql in production Supabase. Verify:
- the objects and grants exist (has_function_privilege, has_table_privilege);
- bye_number_count() = 0.

G3. Owner number 1. Ask me for my school email in chat, then:
- confirm my auth user exists, showing a count only;
- run the owner insert;
- verify that number 1 belongs to my account and that count = 1.
If I have no auth user yet, tell me to verify my email once on https://bye-before-you-enroll.pages.dev/reviews/ (verify only, no claim) and wait.

G4. Website deploy.
- Prepare the website commit: Claude's route, test, copy and AGENTS changes plus yours. List every file.
- Give me GitHub Desktop Summary and Description blocks.
- I commit and push in GitHub Desktop myself, unless I explicitly tell you to.
- Pushing main deploys Cloudflare Pages.
- After the deploy, check live:
  - GET /api/reviews/numbers → {data:{total:1}}
  - POST /api/reviews/number with no session → 401
  - the Mac's read routes still answer: resolve with a fictional name → match "missing", no error

G5. My live check.
- I open the Mac test app: Settings → General → Your BYE number, then verify my school email and code.
- Expected: BYE-0001, Student 1 of 1.
- Verify in the database: count is still 1 and there is no second row for me.
- If I get anything else, stop and diagnose before any fix.

G6. App repo handoff. Give me GitHub Desktop Summary and Description blocks for your app-repo files:
- 007 and its checks;
- the rehearsal tooling;
- the handoff doc results.
Claude's Mac changes are committed separately; don't include them unless I say so.

=== 7. WHEN DONE ===
- Update BYE_Before_You_Enroll/docs/bye-numbers-backend-handoff.md with a dated "Results" section:
  - what ran where;
  - the checks and their results;
  - the decisions made;
  - what's still open, such as Windows parity and relocation deploy.
- python3 -I scripts/agents.py done codex "<summary, checks, what went live>"
- Final message to me:
  - the changed files per repo;
  - the checks actually run, with pass/fail counts;
  - every production action taken, with its time;
  - anything untested;
  - ready-to-paste Summary and Description blocks for each repo with uncommitted changes.
````
