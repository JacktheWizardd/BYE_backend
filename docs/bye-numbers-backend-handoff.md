# Handoff to Codex: BYE student numbers backend

October 21, 2026. From Claude Code (frontend) to Codex (backend).

The owner's request, in their words: "create a file and handoff to codex to run backend".

Nothing here is deployed or run against Supabase yet. Every change in both repositories is uncommitted.

## What the feature is

Each PCC student can get their own BYE number on the app's student ID card (`BYE-0042`, "Student 42 of 57"). Today every card shows a hard-coded `BYE-0001`.

Owner decisions:
- **Optional:** students can skip it.
- **Sign-in:** reuses the live review sign-in (Supabase email code, `@go.pasadena.edu`, no `+` aliases).
- **Number 1:** always the owner's.
- **Count:** shown to students.
- **Release:** ships in Mac 0.5.0, which waits on this backend.

The number is linked to the Supabase account ID, never the email. If the reverted email-free sign-in (`supabase/migrations/20261021023510_*`) ships later, its backfill keeps account UUIDs, but number holders and their foreign key/authentication must also migrate before Auth cleanup (see Results).

## Files already written (uncommitted)

**App repository (`BYE_Before_You_Enroll`)**
- `supabase/007_bye_numbers.sql`: SQL Editor style like `006`, safe to repeat. It adds:
  - `private.bye_numbers` (`user_id` → `auth.users`, unique `number`, `created_at`);
  - `private.bye_number_seq`, which starts at 2;
  - `public.claim_bye_number()`: `security definer`, requires `private.is_pcc_student()`, idempotent, returns `(number, total)`, granted to `authenticated`;
  - `public.bye_number_count()`: granted to `anon` and `authenticated`.

  A commented owner step at the end assigns 1 to the owner's account.
- Mac client: `Sources/ClasswiseCore/ByeNumbers.swift` (`ByeNumberClient`) and its tests in `Tests/ClasswiseCoreTests/ByeNumberTests.swift`.

**Website repository (`BYE_website`)**
- `server/reviews.ts`:
  - `POST /api/reviews/number` needs a verified review session and calls `rpc('claim_bye_number')`, returning `{ number, total }`.
  - `GET /api/reviews/numbers` is public and calls `rpc('bye_number_count')`, returning `{ total }`.
  - Both routes are in the `methods` map, with `LIMITS` of 10 claims and 60 counts an hour per IP.
- `tests/review-fixtures.ts` gains the two RPC fixtures; `tests/bye-numbers.test.ts` has 5 tests.
- `apps/landing/src/sections/About.tsx` gains the privacy line; `public/index.html` and `public/site/*` are the rebuilt output.
- `AGENTS.md` gets a "Change with care" note and a "Current state" entry.

## How the Mac app calls it (contract to keep)

1. `POST /api/reviews/auth/send` with `{ "email": "<school email>" }`.
2. `POST /api/reviews/auth/verify` with `{ "email", "code" }`. The app reads `Set-Cookie` (`__Secure-bye-review`, or `bye-review-local` on loopback) and keeps it in memory only.
3. `POST /api/reviews/number` with `{}` and that cookie, which returns `{ data: { number, total } }`. The app then drops the cookie and stores only the number.
4. `GET /api/reviews/numbers`, at most once a day with no cookie, which returns `{ data: { total } }`.

**Request details:**
- Every POST sends `Origin: <site origin>` and `Content-Type: application/json`, to pass the existing origin check (verified against a real URLSession on loopback).
- Errors are read from `{ error: { message } }` and shown to the student as is.

**Constraint:** Turnstile is off in production. If it is enabled, native `auth/send` fails. Keep it off, or add an app path first.

## What we need from you (Codex)

1. **Review** `007_bye_numbers.sql`. In particular:
   - the `#variable_conflict use_column` / OUT-parameter naming;
   - `on conflict` under concurrent claims;
   - the grants;
   - that 1 is never auto-assigned;
   - `on delete restrict` interacting with any account-cleanup plans.
2. **Rehearse it** against a local or disposable Postgres with the earlier schema files, using the existing `pnpm test:reviews:db` approach where it fits. Record the result.
3. **Review** the two routes in `server/reviews.ts` (security-sensitive: session, rate limits, error shapes) and carry them through your backend relocation (`BYE_frontend_relocation` / `BYE_backend_relocation`, `functions/api/reviews/[[route]].ts` forwarding) without changing the contract above.
4. **Run against production only with the owner's explicit confirmation at that time**, per AGENTS.md. Each of these is a separate approval:
   - run `007_bye_numbers.sql` in the Supabase SQL Editor;
   - after the owner verifies their own school email once, run the owner step so their account becomes number 1;
   - the website commit and push (Pages deploys the routes);
   - check live: `GET /api/reviews/numbers` returns `{ total: 1 }`, then the owner claims in the app and sees BYE-0001.
5. **Email limits:** confirm the Brevo daily sending limit (free plan about 300 a day) is acceptable for sign-in codes, or tell the owner.

## Checks already run (by Claude Code)

- Website: `pnpm typecheck`; `pnpm test` 92/92; `pnpm build`, which ends with `verify:static`. The About copy was checked in the preview at 127.0.0.1:8790.
- Mac: `swift test` 255/255, covering:
  - the email rule;
  - no request for a bad email;
  - the send → verify → claim cookie flow;
  - the session dropped after verifying;
  - the count sent without a cookie;
  - the email never stored;
  - the once-a-day total refresh.
- Not run: the SQL against any database, and any live end-to-end flow. Testing against live services isn't allowed, and `pnpm dev:api` talks to the real Supabase.

## When done

- Log the outcome on the board with `python3 -I scripts/agents.py done codex "..."`.
- Update this file with the results.
- Give the owner GitHub Desktop Summary and Description blocks for each repository you change.
- Do not commit, push, deploy or run production SQL without the owner's explicit go-ahead for that action.

## Results — October 21, 2026 (Codex; local only)

**Ready for an owner-reviewed G1 preflight, not yet live.** No production reads,
SQL, accounts, emails, dashboard access, configuration changes, commits, pushes or
deployments were performed. There are no production-action timestamps to report.
Swift source and Mac UI were not changed or rebuilt by Codex.

### Changes and decisions

- Owner approved keeping `ON DELETE RESTRICT`. This prevents accidental account
  cleanup from silently deleting numbers. Disposable cleanup removes the precise
  fixture number row before its Auth account; it never resets the sequence.
- 007 explicitly assigns postgres ownership, enables RLS without client policies,
  revokes table/sequence access and restates RPC grants. Definer functions keep an
  empty search path and qualified references. `auth.uid()` plus the current 006
  helper checks the actual confirmed Auth account, not user-editable metadata.
- Reruns validate column types/nullability/default, required constraints and sequence
  bounds/increment/cycle before proceeding. Incompatible definitions abort instead
  of being silently accepted by IF NOT EXISTS. Compatible reruns retain all rows and
  sequence state; no automatic repair/reseed of existing data occurs.
- `#variable_conflict use_column` remains; qualified `b.number` avoids the OUT
  variable, and `ON CONFLICT(user_id)` resolves correctly. Repeat claims skip nextval;
  concurrent first claims may consume a losing sequence value. This is acceptable:
  the ID is not a rank, so a number can exceed the current total. Count remains an
  ordinary exact count appropriate to this scale; no cached counter was introduced.
- The commented owner transaction checks exactly one eligible account, inserts or
  moves it to 1, blocks a competing holder and does not alter the sequence. Real
  owner details must be supplied only at G3 and never saved in project files.
- The future email-free migration is **not automatically compatible** just because
  UUIDs survive. Before Auth deletion, backfill every number holder (including
  accounts without reviews), preserve number/UUID/created_at, rebind the FK to
  `review_private.identities`, and implement claim authentication for that system.
  Existing prepare/cutover migrations were not changed or run.
- Website claims now require `{}` through the existing JSON/content-type/16 KiB
  parser after session eligibility and before the RPC. Exactly one RPC row with
  positive safe integers is accepted; count requires a nonnegative safe integer.
  Student-friendly errors, no-store/noindex/nosniff/Vary headers and all Mac
  request/response/cookie contracts remain intact. No upstream errors are logged.
- Guard order remains method, POST Origin, HTTPS, config, per-IP brake, then route
  handling; claims additionally require session and eligible user. Count stays
  public without Cookie or Origin. Current 10/hour claim and 60/hour count limits
  are in-memory/per-isolate and depend on Cloudflare's client IP header. They are
  not a global quota; direct public RPC calls also bypass the website brake.
  No new service, paid quota, cache or Turnstile setting was introduced.

### Verification actually run

| Check | Result |
| --- | --- |
| Disposable PostgreSQL 17.10 rehearsal | 37 checks passed, 0 failed |
| Website `corepack pnpm install --frozen-lockfile` | Passed; already installed; optional pnpm update-metadata fetch warned in sandbox |
| Website `corepack pnpm typecheck` | Passed |
| Website `corepack pnpm test` | 100 passed, 0 failed |
| Website `corepack pnpm build` | Passed, including static/noindex/release-path and client-secret checks |
| Backend relocation typecheck | Passed |
| Backend relocation tests | 55 passed, 0 failed |
| Backend relocation build check | Passed; Wrangler dry-runs only |
| Backend relocation runtime acceptance | Both source and review suites passed; no real upstream requests |
| Git whitespace/diff checks | Passed for affected repositories/worktree |

Installed only the isolated `scripts/bye-numbers` npm toolchain: embedded-postgres
17.10.0-beta.17, PostgreSQL 17.10, pg 8.23.1, with a committed-to-be lockfile.
No global service was installed. The runner uses a disposable loopback cluster,
random temporary credentials and fictional data, then stops/removes its cluster.
Installation needs registry access; execution is offline. A first sandbox attempt
was blocked from opening loopback; the approved local execution succeeded.

The rehearsal exercised first/repeat/second claims, eligibility and null UID,
role-specific table/sequence denials, owner insert/repeat/move/collision/missing
account, same-user contention observed through a separate connection, different-user
concurrency, grant restoration, rerun persistence, schema drift, RLS and RESTRICT.
See `../scripts/bye-numbers/README.md` and `../supabase/007_bye_numbers_checks.sql`.
Manual checks are authored for a disposable environment; they were not run in a
hosted SQL Editor. The automated runner executes the actual owner SQL from 007.

Website regression coverage includes missing Origin → 403 before upstream access,
wrong methods/origin, HTTPS/config/session gates, invalid content type/body/fields/
size, RPC errors/malformed results, public zero count, sequence gaps, privacy headers,
and both route rate limits with Retry-After. The generated reviews HTML was restored
to its exact pre-build bytes after verifying only CR/LF differences. Build warnings
about existing large chunks remain non-fatal; release assets were not edited.

### Relocation handoff

Ported the two routes, fixture additions and tests into
`BYE_backend_relocation/services/web-api`, changing only repository import paths.
Updated its provenance with working-tree source and destination hashes, without
misrepresenting these additions as part of the baseline commit.

Its runtime test compiles the actual frontend Pages functions and binds WEB_API to
its compiled backend worker. Send/verify/claim/repeat/count and public
resolve/profile/list pass through the real forwarder. Origin, JSON content type,
request body, cookie, Set-Cookie, Cache-Control and Retry-After are verified.
The frontend forwarder itself required no edits. Run from the backend worktree:

```sh
corepack pnpm test:runtime /Users/thewizard/Documents/Project/BYE/BYE_frontend_relocation
```

Relocation deployment is not part of this launch and remains pending.

### Email capacity (published facts versus account state)

The shared project note records Brevo Free as of October 17; no account dashboard
was accessed to reconfirm it. [Brevo's published Free limit](https://help.brevo.com/hc/en-us/articles/208580669-FAQs-What-are-the-limits-of-the-Free-plan)
is 300 emails/day, without rollover. Excess transactional messages may queue (up to
1,000), so delivered codes can arrive too late. A send is not a unique student:
retries, reviews and any other shared traffic reduce the available sign-ins.
For example, 150 students requesting two codes use all 300 sends, before other mail.

[Supabase's published Auth limits](https://supabase.com/docs/guides/auth/rate-limits)
make the custom-SMTP project email limit configurable; the built-in-provider 2/hour
limit is not evidence of this project's configuration. Published defaults include
60 seconds between OTP sends per user, and 30 requests per five minutes for
sign-in/sign-up and verification per IP. Server-side proxy egress can become a
shared bottleneck; do not assume every student's IP reaches Supabase. BYE also has
its own 5 sends/10 minutes per IP and 4/30 minutes per address brakes, which can
throttle students sharing campus Wi-Fi. These existing controls were not weakened.

Recommendation: before broad enrollment-day promotion, obtain separate permission
to inspect only the plan/quota and Auth rate-limit screens, then estimate peak
students × code attempts plus other mail. Keep launch demand below confirmed daily
and burst headroom; if demand exceeds that, propose capacity changes with costs for
approval. Do not turn on Turnstile or add privileged keys to solve proxy limits.
Actual configured quotas, remaining sends and peak delivery are still unknown.

Public Supabase changelog/docs were reviewed. Its October 12 TLS deprecation
removes old CBC suites from HTTP APIs no earlier than November 10; no change to
this modern server-side fetch integration is indicated, but hosted TLS was not
probed. [Notice](https://supabase.com/changelog/cbc-tls-ciphers-deprecated).

### Still open and approval gates

- G1: actual deployed helper, object state/ownership/grants, postgres role behavior,
  event-trigger definitions, private schema exposure and live status/Turnstile.
  `003_helper_permissions.sql` only revokes helper privileges: the deployed
  `rls_auto_enable()` implementation is absent from these source files. Local
  explicit RLS works with the definer owner; deployment-specific triggers are unverified.
- G2: production SQL install and count zero; G3: owner account/reservation and count one.
- G4: owner-controlled website commit/push/deploy and approved live route checks.
- G5: real email, Mac test app and database confirmation. No live native acceptance yet.
- G6: final production results and separate app backend commit handoff.
- Windows parity, hosted PostgREST behavior, production concurrency/load/delivery,
  future private identity migration and relocation deployment remain untested/pending.

Stop before G1. Each gate needs its own exact command/SQL, impact, recovery and
post-check description followed by explicit approval. If data exists unexpectedly,
stop; never reset numbering. Rollback after enrollment preserves numbers and sequence
state, normally by disabling the routes/restoring website code rather than dropping
objects. No existing approval in this handoff authorizes any production action.

## Production G1 partial results — October 22, 2026

Owner authorized starting setup after the backend merge. Read-only G1 began at
2026-10-22 07:31:45 America/Los_Angeles (14:31:45 UTC).

- Connected project: BYE (`nahvhampsxtasfwvvfei`), PostgreSQL 17.
- `private` exists; 006's helper requires a confirmed PCC account and excludes plus aliases.
- Number table, sequence, claim RPC and count RPC are all absent. This explains the
  deployed number route's failure after successful email verification.
- Live `/api/reviews/status` returned enabled true, ownerTest false, no Turnstile site key.
- Deployed `ensure_rls` calls `public.rls_auto_enable()` and enforces RLS only on public
  tables. 007 separately enables RLS on its private table. PostgREST DDL watchers exist.
- API schema exposure remains unverified: the session and role metadata did not
  report `pgrst.db_schemas`. NULL is not evidence that private is excluded.
- No student records or credentials were read. No SQL writes, owner reservation,
  settings changes or service deployments were performed. G2 and G3 await separate approval.

Next: request permission to view only the Supabase Data API exposed-schema setting,
or have the owner provide that non-secret list, before completing G1.

### G1 completed — October 22, 2026

After the owner authorized dashboard inspection and signed in, the Data API Settings
schema menu visibly checked only `public` and `graphql_public`. `private`,
`bye_schedule` and `pcc_schedule` were unchecked. No settings were changed.
Together with the read-only SQL and status checks above, G1 passes.
G2 remains pending separate approval to run the reviewed 007 transaction; owner
reservation remains G3. The dashboard's automatic new-table exposure is on, making
007's explicit table/sequence revocations and post-install privilege checks important.

## G2 production installation — October 22, 2026

Owner approved G2 and remaining setup ("sure do all"). The Supabase migration tool
applied the exact reviewed 007 file as `bye_student_numbers_007` between 07:48:16
and 07:48:21 America/Los_Angeles (14:48:16–14:48:21 UTC). This adds a hosted migration
history entry; do not blindly run db push against the older SQL-Editor history.
SQL SHA-256: `0234fe800e1e446fda303acd5f877fcea4259f206550e794928f0e8b3e585f95`.

Post-install checks passed: count 0; postgres owns both definer RPCs, table and
sequence; both RPCs have empty search_path; table RLS enabled; anon cannot execute
claim; authenticated can claim; both roles can count; neither role can access the
table or sequence directly. Sequence starts/minimum 2, increment 1, no cycling.
Public GET /api/reviews/numbers returned {data:{total:0}}. No account was created,
modified or assigned a number. G3 still needs the owner's address supplied in chat;
none has been copied from the screenshot or recorded in project files.

Live route acceptance after G2 also passed: POST number with site Origin/JSON but
no session returned 401 SESSION_EXPIRED; public resolve for a fictional professor
returned match "missing" without error. These checks wrote no student data.

## G3 founder reservation — October 22, 2026

Owner supplied the school address in chat and explicitly requested number 1.
Count-only precheck confirmed exactly one matching, confirmed Auth account.
The reviewed owner transaction ran at 07:55:53–07:56:01 America/Los_Angeles
(14:55:53–14:56:01 UTC), assigning/moving that account to number 1 without
resetting the sequence. Postcheck returned owner_rows=1, owner_number=1, total=1.
No address or account UUID is recorded here. The owner reported the live flow
working before this reassignment; refreshed native display after reassignment
remains to be confirmed because the app saves its claimed number locally.
