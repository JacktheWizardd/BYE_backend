# Windows API integration — October 20, 2026

## Current state

The local Windows source/build reads the standalone BYE schedule API, starts BYE student-review lookups first, and automatically retrieves separately labeled RMP information. BYE reviews appear before RMP scores/reviews. Averages and source identities are never combined. Native Mac and website schedule integration are separate work.

The API currently offers Fall 2026 (`202670`). Read-only live checks returned the expected MATH 005A suggestion, 36 unique sections and 27 course-local instructor groups. Availability was marked stale, so seat counts were suppressed. This is not an enrollment or freshness guarantee. Live checks contacted only BYE endpoints; they made no direct PCC/RMP request, email request, review write or database change.

## Implementation and configuration

- Electron main owns fixed-origin, GET-only schedule/review transports, response bounds, cancellation, conditional reads, rate-limit handling and retries. Renderer IPC validates commands and current professor/course membership. Privileged credentials cannot be built into the app.
- `BYE_CLIENT_KEY` is loaded from ignored `apps/cross-platform/.env.local` or the build environment and bundled only in main. This machine uses the existing registered compatibility application key, verified with the read API; no key was created/rotated. Installed clients receive replacements through a rebuilt app/manual update. No automatic replacement-key delivery is claimed.
- The engine consumes a typed schedule provider rather than raw PCC rows. Co-instructors retain every meeting of their CRN; dates, suffixes, unknown formats, notes and raw registration codes are preserved. Seats do not determine registration status.
- The public schedule cache is atomic and bounded to 12 entries / approximately 8 MiB. It contains no API key, student preferences or reviews. Saved terms/catalog are immediately usable, with bounded background revalidation. Explicit searches revalidate the catalog; changed bodies use ETags.
- One 60-second loop runs only for visible, online results and a non-minimized window, with one update in flight and exponential failure backoff. Requests contain only the CRNs represented by the current filtered screen, in batches of at most 100. Source checks expire after 15 minutes; unknown/stale totals remain unknown. The web retains its five-minute policy.
- Schedule refresh keeps the current course, professor/report objects, review filters and source jobs. Failures stay visible and mark saved availability stale. Semester + official course identifies each of at most five session tabs. Recent settings remain compatible with earlier string entries; newly visited classes record their semester.
- BYE uses the website's public `resolve`, `profile` and `list` API. Only unique catalog matches attach feedback. BYE scores, review pages and errors remain independent of RMP, including when either source is empty/unavailable. Twenty-row pages are bounded to 200 reviews per selection; text stays in session memory. Writing opens the existing verified-email website form. No native login/submission/reporting or privileged Supabase SDK was added.
- RMP still loads automatically after BYE jobs start and supplies the explicitly labeled existing professor-list sorts. Original identity checks, manual choices, source limits, caches and disabled-AI policy remain intact.

## Verification

- Windows typecheck/build and **61/61 unit tests** passed. Added tests cover API mapping, suffixes/co-instructors, unknown data, 304 reads, revoked keys, rate limits, cancellation, partial failures, pagination, source-job independence, refresh retention and polling lifecycle.
- Windows offline UI acceptance covers first run, keyboard search, explicit profile choice, saved classes, cache restart, source separation, safe BYE text, 20-row pages, stale overview/card suppression, failed refresh/retry and semester isolation. Report path is recorded in `apps/cross-platform/test-results/offline-ui-latest.json`.
- Website typecheck, **87/87 unit tests**, build/static checks, Chromium/WebKit browser suites at phone/desktop widths, and local worker-runtime tests passed. Fixture acceptance does not establish physical Safari gestures or a new live rollout.
- Public live schedule and BYE resolver checks passed through the new clients. They printed aggregate counts/flags only. RMP was never called by automated verification.
- `scripts/agents.py inbox codex` could not run because Windows Python lacks `fcntl`; no board state was forged. WSL was inaccessible. Initial implementation checkouts were clean.

## Source control and limits

Codex did not commit, push, deploy, migrate, publish or change release assets. During implementation the website checkout advanced externally to `20519cc` (including the shared UI changes alongside landing edits). That history and unrelated landing work were preserved. Desktop integration and subsequent documentation/tests remain local unless later committed externally. Check `git status` before preparing a commit.

No updated release ZIP or native Mac test app is claimed. Test the Windows source with `npm run dev` from `apps/cross-platform/`. API availability is currently stale; showing sections while hiding seats is intentional. BYE identity gaps remain explicit rather than inferred. Existing shared legacy key use does not provision a dedicated Windows key or a rotation-delivery system.

## GitHub Desktop handoff

### Desktop repository

**Summary:** Connect Windows schedules and BYE student reviews

**Description:**
Use the BYE schedule API with bounded caches, conditional reads and visible-client polling. Start independently matched BYE reviews first, retain automatic RMP retrieval, and label sources separately. Preserve reports during schedule refresh, surface refresh errors, suppress stale/unknown totals, and scope tabs by semester/course. Add public-key safeguards and offline regression coverage. Windows typecheck/build and 61 tests pass; offline UI and read-only BYE checks pass. No live RMP requests, database changes, commit/push, deployment or release by Codex. Live availability is stale and hidden; installed-client replacement-key delivery remains manual.

### Website repository

**Summary:** Document and verify BYE-first shared review support

**Description:**
Verify shared BYE-first review presentation and separate source freshness policies, plus deduplicated/unknown seat-total tests. Preserve demo disclosures, same-origin browser access and release gates. Website typecheck, 87 tests, build/static, browser and local runtime checks pass. Shared source changes are already present in externally created commit 20519cc; include only remaining local changes after reviewing GitHub Desktop. No commit, push or deployment by Codex.
