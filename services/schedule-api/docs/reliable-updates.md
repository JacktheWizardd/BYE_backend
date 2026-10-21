# Reliable schedule updates — local implementation

Recorded October 20, 2026, Pacific time. Source changes are **uncommitted and not deployed**.

## Implemented

- Additive semester-safe backend migration; availability keys are `(term, CRN)`. Each term retains its own catalog, availability, lock, backoff and rollback. Cleanup protects every term's current/previous snapshots.
- Daily discovery of officially published terms, with independent discovery backoff. Validated current-year/future published terms import automatically. Previous imported terms are retained; removed terms stop collection and expose stale availability. A term is offered only after a valid catalog is published.
- Instructor assignment changes invalidate catalog versions, including Staff/TBA becoming named faculty; co-instructors remain separate source assignments. No review IDs or global professor identities are reassigned.
- Shared collection budget: at most one PCC request per five minutes, including discovery. Visible clients poll version metadata with jitter around sixty seconds. Unchanged catalogs are retained; only changed sections or displayed CRNs are downloaded.
- Before thirty days after a verified official start, active terms target five-minute checks and idle terms thirty-minute checks. Later terms target thirty-minute checks when active and daily checks when idle. A newly active term becomes due without bypassing the aggregate budget or failure cooldown. Unknown calendar dates never trigger automatic slowdown. Calendar comparisons use America/Los_Angeles.
- Typed Windows and Mac adapters, course-only bounded desktop disk caches, visible/online lifecycle handling, source timestamps, local fifteen-minute expiry, and preservation of valid professor selections. API failures do not trigger direct PCC or fictional-data fallback.
- Website same-origin routes are preserved. Its server Worker now reads schedules from the shared backend; browser polling preserves reviews, filters and valid profile choices. `/demo/` remains network-free, and all existing release/source flags remain unchanged.
- Safe fetch/decode/validation/staging/publication diagnostic codes and numeric source HTTP status, without source bodies, names, SQL messages or credentials.

## Benchmark method and results

`npm run benchmark:local -- ../../.local-docs/pcc-schedule/fall-2026/source.json` starts an ephemeral loopback HTTP simulator and an isolated PGlite database. Fetches outside that simulator are denied. Actual worker ingestion, API reads, injected failures and row-write counters are measured. The private saved Fall source is replayed for normalization; its raw content is never copied into this report.

The sixty-row cadence matrix covers 1/2/5/10/30-minute collection budgets, 1/3/6 terms and 1/30/100/1,000 clients. It is a **24-hour virtual-time estimate**, not sixty full-day load tests. All terms in that model are actively viewed and high priority; 10% of source checks are modeled as changed. Daily discovery adds a request/budget slot that the estimates exclude. Actual real-time load tests separately cover twelve term/client combinations.

| Terms | Clients in burst | Successful reads | HTTP 429 | p95 local latency | Measured DB row writes |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 30 | 30 | 0 | 23.7 ms | 30 |
| 1 | 100 | 100 | 0 | 17.5 ms | 100 |
| 1 | 1000 | 520 | 480 | 15.4 ms | 1000 |
| 3 | 30 | 30 | 0 | 13.1 ms | 32 |
| 3 | 100 | 100 | 0 | 12.6 ms | 100 |
| 3 | 1000 | 520 | 480 | 13.0 ms | 1000 |
| 6 | 30 | 30 | 0 | 12.0 ms | 33 |
| 6 | 100 | 100 | 0 | 12.9 ms | 100 |
| 6 | 1000 | 520 | 480 | 27.7 ms | 1000 |

Sixty percent of the clients share one simulated campus address. At 1,000 clients, 480 requests are rejected by the existing 120-operations/minute network limit. That safety limit was preserved. Low latency for a rejected response is not successful service capacity. Row writes include rate-limit accounting and sampled demand/key updates; unchanged reads do not rewrite availability generations.

With a five-minute aggregate budget, modeled worst change-to-screen delay is approximately **6 minutes for one active term, 16 minutes for three, and 31 minutes for six**. The last two exceed the fifteen-minute availability deadline, so counts will legitimately disappear between checks. A faster global rate is not enabled automatically.

Using the saved full response (12,256,542 bytes), 288 full checks would transfer roughly **3.53 GB/day of upstream ingress**. This is a worst-case active-use estimate, not client egress or a hosting bill. Actual future semester sizes and PCC's own update latency are unknown. Idle collection is slower. Projected CPU is normalization only and excludes database/transport work.

The separate existing full-Fall performance gate passed: 5,602 rows, 3,607 sections, 1,101 courses, approximately **625 ms CPU, 401 ms elapsed and 201 MiB RSS**, against gates of 1,400 ms CPU and 220 MiB RSS. The larger simulator's process memory also includes PGlite and concurrent clients and must not be compared to a hosted function's memory limit.

Recommendation: keep the five-minute aggregate ceiling and current rate limits until separate authorized hosted observation establishes a safe change. No production/PCC/RMP/email traffic was generated by these tests; no paid resources were enabled.

## Verification

- Backend: 21 unit/contract/security tests; 30 isolated database scenarios; Deno checks passed.
- Windows: 56 tests and type checks passed; production build passed. The final renderer freshness boundary and configured production main bundle were rebuilt successfully.
- Website: 94 tests, type checks and build passed. Real local workerd/Pages/SQLite fixture acceptance passed. Chromium and WebKit passed at 375, 390 and 1280px, including history, selection, stale counts and disabled-source behavior. Full-app tests passed at 390 and 1280px in both engines, including review/profile recovery. Real Safari phone gestures remain unverified.
- Mac: source adapter, lifecycle integration and contract tests added. No Swift toolchain is available on this Windows host. The owner will run Swift tests, `scripts/build-test-app.sh` and relaunch `test/BYE Test.app` on the Mac before Mac acceptance.
- Independent PostgreSQL concurrency harness added as `npm run test:postgres`. It requires an already migrated, disposable loopback database named `bye_schedule_test`. No compatible PostgreSQL/container runtime was found, so this check was not run. PGlite tests do not prove independent-session locking.
- The required coordination script was attempted with bundled Python and failed on its Unix-only `fcntl` import. No `.agents` state was fabricated or edited. Existing uncommitted demo and shared UI changes were preserved.

## Important remaining boundary

The existing hosted synchronization outage is **not claimed fixed**. Inspection found 30 failures and a last successful source check on October 19 at 3:00 a.m. Pacific; its old diagnostics contained only `SYNC_FAILED`. Saved-data and fixture tests reproduce the supported failure paths, but cannot establish the exact live cause. The new diagnostic code/status will make the next separately authorized controlled hosted run actionable. No production migration, deployment, source experiment, commit or push was performed.

Verified official semester dates and platform application keys must be configured before acceptance. New-term discovery imports current-year terms when no verified dates exist because semester dates cannot be inferred from codes or individual meeting dates. An owner can supply official dates to stop ended terms and enable the thirty-day policy. Mac and website public launch gates remain separate.

## Configuration and authorized rollout checklist

1. Review the additive migration and run the real PostgreSQL concurrency harness on a disposable local test database. Never run that harness against production.
2. Supply `BYE_SCHEDULE_API_URL` and `BYE_SCHEDULE_API_KEY` to Windows at launch/build configuration (`.env.local` and existing `BYE_CLIENT_KEY` are supported; the canonical existing backend URL is the desktop build default); only a public application identification key belongs there. Mac supports those environment names or `BYEScheduleAPIURL` / `BYEScheduleAPIKey` in its bundle Info.plist. Do not embed service-role or job credentials.
3. Set the website source Worker's server-side `BYE_SCHEDULE_API_URL` / `BYE_SCHEDULE_API_KEY`; the browser continues to use `/api/v1/*`. Preserve existing feature flags and RMP authorization.
4. For reviewed official calendar dates, use the private owner command with `BYE_TERM` set: `npm run owner -- term-dates YYYY-MM-DD YYYY-MM-DD https://pasadena.edu/...`. This is a privileged mutation for a later authorized environment; no date values were applied here.
5. With separate deployment authorization, pause Cron, wait for active leases to finish, apply the migration, deploy the compatible worker/API, verify configured keys and fixture/staging paths, and restore Cron. Do not run the old Fall-only worker against newly imported terms. Inspect safe diagnostics on one budgeted source run before relying on availability.
6. Verify representative schedules, instructor changes, source timestamps and stale expiry in staging; complete the Mac test-app workflow. Keep public website activation, release assets, paid upgrades and Git actions separate.

## GitHub Desktop handoff — desktop/backend repository

**Summary**

Add semester-aware schedule updates and shared client adapters

**Description**

Add validated term discovery, term-scoped availability/rollback, shared fetch budgeting, calendar-based priority and safe sync diagnostics. Connect Windows and native Mac schedule consumers, preserve valid professor selections, and expire stale counts locally. Add a loopback simulator, cadence/load report, regression tests and a guarded independent-PostgreSQL lock harness. Backend unit/database checks, Windows tests/build and saved-data performance gate passed. Mac compilation/test-app acceptance and independent PostgreSQL concurrency remain pending. Hosted outage cause remains unconfirmed; no deployment, migration application, commit or push. Preserve existing unrelated demo changes and exclude local credentials.

## GitHub Desktop handoff — website repository

**Summary**

Connect live schedule reads to the shared semester-aware backend

**Description**

Route schedule reads through the source Worker's server-side typed adapter while retaining same-origin browser APIs and all rollout gates. Poll version metadata, fetch changed sections/availability, preserve valid profile choices and expire stale counts. Refresh published term choices without changing the selected semester. Add adapter regressions and update actual Worker fixtures. Type checks, 94 tests, build, workerd acceptance and Chromium/WebKit phone/desktop checks passed. Public activation and hosted verification remain pending; RMP/review behavior and sample-only demo rules are preserved. Generated browser assets were rebuilt from source. Changes remain uncommitted alongside existing shared UI/review edits.

## GitHub handoff verification — October 20, 2026

The schedule-only branch excludes unrelated offline-demo and merged-review work. Its exported source passed 21 backend tests, 30 isolated database scenarios, Deno checks, 51 Windows tests, TypeScript and the Windows production build. The separate website export passed 91 tests, type checking, build, local workerd acceptance and Chromium/WebKit browser checks. Earlier counts above describe the full local combined working copies. Mac compilation, native tests/test-app relaunch and independent PostgreSQL concurrency remain pending. This is a source handoff, with deployment and migrations still deferred.
