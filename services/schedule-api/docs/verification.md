# Standalone schedule API verification

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
