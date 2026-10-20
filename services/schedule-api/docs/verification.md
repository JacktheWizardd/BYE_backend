# Standalone schedule API verification

Latest accepted state is recorded in the [hosted owner acceptance](#hosted-owner-portal-acceptance--october-19-2026-pacific)
and [key-management update](#key-management-update--october-19-2026-pacific).
Read the [delivery record](records/2026-10-19-delivery.md) for a nontechnical overview.
The original October 17 deployment and intermediate preparation checkpoints below
are historical; use the later acceptance entries for the delivered state.

Verified October 17, 2026 (Pacific). This is a backend-only delivery.

## Deployed result

- Project: existing BYE Supabase project, `nahvhampsxtasfwvvfei`.
- Read function: `bye-schedule-api`, deployed version 4.
- Private synchronization function: `bye-schedule-sync`, deployed version 3.
- Base URL: `https://nahvhampsxtasfwvvfei.supabase.co/functions/v1/bye-schedule-api`.
- The default enabled publishable key identifies public callers. Key retrieval,
  request examples, deployment and owner commands are in [guide.md](guide.md).
- The six read routes and `/v1/openapi.json` are active. No student login is
  required. App releases and API deployments are independent.
- Cron and the worker are enabled. One-minute ticks honor a shared five-minute
  source deadline, a distributed lock, demand expiry, and failure cooldowns.
  A daily check is due at/after 10:00 UTC. No PCC request occurs on a public read.
- An actual cron execution succeeded at 9:22 p.m. Pacific and received HTTP 200
  with `COOLDOWN`, confirming that a timer tick respected the existing source
  deadline instead of issuing another PCC request.

The initial read model was populated from the verified private pilot, with no
PCC traffic. A controlled live refresh then reconciled all 5,602 source rows,
detected **six changed availability records**, and kept the catalog version
unchanged. A subsequent private scheduled-path invocation completed successfully
and changed only the successful-check timestamp because the data was unchanged.

Counts after publication:

| Record | Count |
| --- | ---: |
| Courses | 1,101 |
| Sections | 3,607 |
| Original catalog source rows | 5,602 |
| Current availability rows | 3,607 |
| Catalog snapshots | 1 |
| Unfinished staging rows | 0 |

The catalog version is
`9370cab3aa9bf043794c49886fe7474c8c33eb4c2bda12aa980b873f26d1d564`.
The successful live availability version was
`f7645724d6e197373135a777fcea87019ebaa59e63f0bee9825415c73d5f6dd1`.
Future successful jobs may change versions and timestamps.

## Tests and source comparisons

- `npm test`: **11 passing** unit/contract/transport tests.
- `npm run test:db`: **15 passing** isolated PostgreSQL scenarios. Includes the
  complete non-extension migration chain, atomic publication, source row
  reconciliation, role denial, seat-only updates, repeated rollback, independent
  catalog rollback, crash recovery, circuit cooldown, bounded retention, stale
  counts, unchanged writes and polling without repeated lease renewal.
- `npm run check`: Deno type checks pass for both entry points.
- `npm run benchmark`: passes against the saved full Fall response. A measured
  local Deno run used approximately 0.58 seconds CPU, 0.35 seconds elapsed and
  202 MiB process RSS. Gates are 1.4 seconds CPU and 220 MiB RSS. Local process
  RSS is not the hosted runtime's memory accounting.
- `npm run verify:hosted`: **8 passing** hosted acceptance scenarios. These
  checks call only BYE/Supabase; they never fetch PCC or RMP.
- Public authentication, exact/normalized searches, partial queries, unsupported
  terms, ETag/304, bounded CRN queries, structured sections, stale suppression,
  private worker denial and private RPC denial were verified on the deployed API.

Representative hosted comparisons:

- `MATH 005A`, `math 005a`, `math 5a` and `MATH5A` resolve to `MATH 005A` first.
  Partial `MATH005` also returns `MATH 005B`; suffixes remain distinct.
- MATH 005A sections 71655 and 80206 exist. Section 71655 retains PCC status `C`
  alongside a positive available-seat count. No open status is inferred.
- Section 80206 preserves the concurrent-enrollment instructions.
- ACCT 001A section 81016 has separate campus dates September 29, October 27 and
  November 24, plus the semester's online component.
- Fixtures cover `005AH`, `005AL`, CCN `C1000H`, unknown fields and statuses,
  missing counts, multiple meetings and instructors, HTML notes, malformed dates,
  conflicting source records and reordered rows.

## Runtime findings fixed before activation

The first controlled live attempt reached the provider's memory limit and did
not publish. The byte reader retained small views backed by large HTTP buffers.
It now decodes and hashes each chunk immediately and releases those byte views.
No response buffers are accumulated for the whole feed.

The corrected live run completed in approximately **3.5 seconds elapsed** with
0.58 seconds normalization time. Hosted shutdown telemetry reported **875 ms
CPU**, below the 2-second limit. A following scheduled-path run completed in
approximately **2.1 seconds**, with 0.56 seconds normalization. Its memory samples
were approximately 52 MiB after reading, 94 MiB after preparation and 92 MiB after
publication. These are measured samples, not a claim about continuous peak memory.

Hosted verification also found and corrected the Edge runtime's shortened URL
prefix. Tests now cover direct, gateway and function-runtime route prefixes.
Retention tests caught an ambiguous staging-token reference; the fixed predicate
is qualified. Null/expired publication locks are rejected. Abandoned workers
recover into a cooldown rather than immediately triggering another source fetch.
Completed network operations explicitly clear their deadline timers.

The scheduler uses one-minute ticks because a five-minute tick can miss a
five-minute cooldown by milliseconds and wait ten minutes. The source minimum
remains five minutes; expected active collection is five to six minutes.

## Private access, retention and existing data

All eight new data tables have RLS enabled and no client policies. Live privilege
checks confirm `anon` and `authenticated` cannot read private records, write
state or execute the backend gateway. `service_role` can execute only the server
gateway for this schema and has no direct table SELECT/UPDATE grant. The private
implementation intentionally runs with owner privileges behind that narrow
machine-only gateway; public handlers do not expose arbitrary operations or SQL.

Catalog/raw retention, availability deltas, expired staging, rate buckets,
2,500-event limits and rollback were verified in isolated PostgreSQL. Cron
history cleanup is scoped to this one job and bounded to seven days/2,500
completed executions. No application cache or recurring client timer was added.

Existing public data remained at **1,531 courses, 1,425 professors and two
reviews**. The complete review-record checksum before and after deployment was
`ab3bdcdcbdce6505e200d24b26d18842` using ordered row JSON. Original pilot records
and their policies were not modified. Database size after initial publication
was approximately 71 MiB, including the original pilot and reusable staging space.

Security advisors report the expected deny-by-default
[RLS-with-no-policy informational notices](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy)
for private tables. The existing
[review-submission SECURITY DEFINER warning](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable)
and [disabled leaked-password protection warning](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
were present before this work and remain unchanged. No new warning was introduced.

## Limits and remaining work

- PCC's own source update frequency is unknown. Five-minute collection is not
  true real-time enrollment. Stale values are suppressed after fifteen minutes.
- No seat-only endpoint or working conditional PCC validator was established.
  Active refreshes still download the full Fall feed, shared across all callers.
- The hosted run covers the current Fall feed; it is not an unlimited-load or
  larger-semester capacity guarantee. Input and runtime limits fail safely.
- `R`/`X` meanings, textbook data, cross-term equivalencies and linked-course
  interpretation remain unresolved; source text and codes remain intact.
- Windows, Mac, website integration and client polling remain later work.
  No client source, website deployment, folder renaming or paid upgrade occurred.
- The coordination board could not run on Windows because `scripts/agents.py`
  imports Unix-only `fcntl`. It was not changed, and existing uncommitted app
  work was preserved.

## Key management update — October 19, 2026 (Pacific)

Deployed: read v5, sync v4, owner management `bye-key-admin` v1. The registry
migration was applied, and the explicitly supplied verified account UUID was
approved through the private gateway. The old key remains active with no expiry.

Checks rerun for this delivery:

- `npm test`: 17/17 unit/security checks after the in-page form fix, including real loopback HTTP fixture tests.
- `npm run test:db`: 22/22 PostgreSQL scenarios.
- `npm run check`: read, sync and management Edge sources checked by Deno.
- `node --check dashboard/public/app.js`: passed.
- `npm run verify:hosted`: 8/8 schedule checks, no direct PCC/RMP traffic.
- Hosted management without a user JWT returns 401.
- Local dashboard and session endpoint both return HTTP 200; CSP is present.
- Review counts remain 1,531 courses, 1,425 professors and 2 reviews; before/after
  checksum `ab3bdcdcbdce6505e200d24b26d18842` is unchanged.
- Registry stores only digests; 304 requests still authorize; revocation/expiry,
  30-day boundary, extensions, revision conflicts, lost-response replay, shared
  rate limits, sampled last use and retention pass fixture tests.
- New local Host/Origin/CSRF, non-owner/expired login, sign-out, session bounds,
  shutdown cleanup and database-outage tests pass with no email/network fixtures.
- Security advisors report no new warning: four new private tables intentionally
  add deny-by-default RLS/no-policy INFO notices. Existing warnings remain the
  review SECURITY DEFINER function and disabled leaked-password protection.

Owner-assisted email-code login passed: the owner reported reaching the key list
and seeing the preserved active key. Create, rotation, retirement extension and permanent revocation passed with
owner assistance. All three temporary keys are confirmed revoked in Supabase; the
original compatibility key is active with no retirement date. Automated concurrency scenarios use PGlite's serialized
connection; real PostgreSQL exclusion is enforced with an advisory transaction
lock and revision predicates, not yet stress-tested with parallel hosted owners.
A fresh headless Edge browser verified extension submission and rotation cancellation
against intercepted fixtures, with no page errors or live API mutations. Existing Cron was left running;
source scheduling and source request budgets were not changed. Hosted reads may
renew the normal demand lease; they never download PCC data themselves.

No client integration, replacement delivery, website rollout or project-key
rotation is included. Additional security tests, retry-window fix and documentation
remain uncommitted; no commit or push was performed during this delivery.

### Owner walkthrough finding: embedded-browser prompts

The owner reached the key list and created a temporary key. During the walkthrough,
the original compatibility key was accidentally rotated; its no-expiry state was
restored with an audited private owner-recovery correction. The accidental
replacement was subsequently revoked through the dashboard during explicit cleanup.

The owner then reported `prompt() is not supported` on Extend retirement. The
browser-native prompt/confirm calls were replaced with accessible HTML dialogs
showing the selected key's label, mask and ID. Extension supports a blank default
or a local date converted to UTC, plus explicit restoration confirmation when
expired. Replacement labels now include “replacement” to distinguish the rows.
Three added regression tests exercise these forms without native dialogs. A fresh
headless Edge check with intercepted API fixtures confirmed submission and cancel
behavior without modifying production keys. The local server serves the fix
immediately; already open pages need a browser reload.

### Final owner-assisted result

The owner confirmed the in-page extension and revoke forms work. Database checks
confirmed the original key remains active with `retire_at = null`, while the test
key, its replacement, and the accidental compatibility-key replacement are revoked.
The live extension used a selected future date; default 30-day extension and UTC
boundaries are covered by controlled-clock fixtures. App usage of these keys has
not been tested because no Windows/Mac/website client integration is included.

Final hosted authorization probes after cleanup: existing key returned HTTP 200;
the revoked temporary key with `If-None-Match: *` returned HTTP 401, never 304.
A final review checksum/count comparison still matches the pre-deployment baseline.

## Separate Cloudflare owner portal — October 19, 2026 (Pacific)

Historical preparation checkpoint, superseded by the acceptance section below:
a separate `bye-admin` Worker was prepared without public-site or Supabase changes.
Cloudflare account authorization was still pending at this checkpoint.
Current checks: 21 unit/security tests, Deno checks of Edge and hosted sources,
Cloudflare dry-run build, and the complete workerd/SQLite runtime test all pass.
The runtime intercepts all outbound requests and proves memory-only login tokens
are dropped on restart while the three quota records survive. The build is about
12 KiB / 4 KiB gzip before static assets. New pins: Wrangler 4.151.2 and its matching
Miniflare 5.20261019.0-beta test runtime; npm audit reports no vulnerabilities.
The earlier 22 database and 8 hosted schedule checks remain recorded evidence;
source/read schema and key lifecycle code were not changed by this hosting work.
See hosted-owner-dashboard.md for deployment commands and remaining live acceptance.
At this checkpoint no hosted URL had been verified. Deployment and acceptance
were subsequently completed as recorded below; no commit or push was performed.

## Hosted owner portal acceptance — October 19, 2026 (Pacific)

Cloudflare authentication completed. `bye-admin` was absent from the existing
account before creation. Published HTTPS URL:
https://bye-admin.jack-truong2k1.workers.dev . Version
`7fb9ee13-a222-424c-89c1-29e779dba956`; startup 1 ms; bundle 11.98 KiB / 3.94 KiB gzip.
The account is Free. Cloudflare rejected a custom CPU limit on the first upload;
the setting was removed and deployment succeeded using built-in Free limits.
No paid plan was enabled and no unrelated Worker/site was changed.

Live checks passed: HTTPS page/CSP/HSTS/no-store, assets, signed-out session,
management 401, cross-origin sign-in 403 without sending email, and unknown-route
404. Fresh Edge browser checks at 390px and 1280px passed after waiting for the
initial session request, with no overflow or JavaScript errors. The owner completed
real email-code sign-in and confirmed the existing key list on the hosted URL.
The local admin process was verified by port and command line, then stopped.
The hosted page and session API still returned HTTP 200 afterward. The site is
independent of the local computer/server and this chat. Tokens remain server-memory
only; a Cloudflare restart can require sign-in again. Client integration is deferred.
The 21 offline tests, Deno checks and full workerd restart/quota tests pass. No
additional schedule live refresh or app build was performed. Changes are uncommitted.

## Documentation and records pass — October 19, 2026 (Pacific)

Added a dated plain-language delivery record and owner/developer handoff under
`docs/records/`, and linked them from package/repository indexes. Updated architecture,
roadmap and commit handoff to reflect the accepted hosted state. Corrected the
historical test-count typo and labeled the pre-deployment checkpoint as superseded.
This pass changes documentation only: the earlier implementation, runtime and live
results above were not rerun or presented as fresh production-health measurements.
Local-link, consistency, whitespace and Git-exclusion checks are recorded with this
pass. No code deployment, app build, staging, commit or push is part of this update.

Documentation-pass results: 14 Markdown files and 84 local links checked;
58 Git-eligible API/index files scanned with no private-key, real BYE-key or
long-JWT pattern findings; seven credential/build/local-state exclusions confirmed.
`git diff --check` passed. These checks do not constitute an exhaustive security audit.
