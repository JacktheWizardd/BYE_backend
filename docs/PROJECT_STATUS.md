# BYE development handoff

Updated October 10, 2026 (America/Los_Angeles).

## Current application

Native macOS 14+ SwiftUI app, release 0.2.0 (build 2). The product is BYE; internal core/app modules and cache folders retain Classwise. PCC schedule retrieval is unchanged.

- Production RMP retrieval uses the dedicated Swift **BYEAPI** module and native URLSession, independently of AI. Legacy WebKit code remains only for comparison/regression tests; there is no automatic browser fallback.
- Shared client transport: two concurrent requests, 100 ms start spacing, 15-second request / 25-second resource timeout, at most three attempts for transient network/selected HTTP failures. Retry-After is respected up to 30 seconds; longer waits produce a recoverable failure. Cursor progress and page-size checks prevent unbounded pagination.
- Initial lookups, discovery, retries and chosen-profile verification share two preview readers; detail retrieval and summaries retain separate single-worker queues. New optional jobs pause while preview work is pending. Cancellation and search/professor/profile/evidence checks prevent stale publication or cache writes.
- Verify source ID, name and PCC identity on each retrieved profile page. Deduplicate candidate IDs; preserve compound surnames. Multiple eligible same-name profiles always require explicit selection regardless of department, rating or AI. Retain candidates after later search-page failures; at most three additional search pages.
- Keep profiles separate. Chooser dismissal leaves unresolved identities unresolved. Change profile preserves existing data until confirmation, then clears the old report immediately and retains PCC sections. Fresh ambiguity also clears a prior automatic report.
- Manual choices persist by normalized instructor name and subject; fresh retrieval reverifies them. Temporary failures retain choices, identity mismatches invalidate them and return to selection. Individual Try again bypasses the professor's identity-cache lookup without discarding other results.

## Cache and review courses

Version 4 raw caches use school/profile ID, last 24 hours and are reused across courses. Automatic identity indexes use normalized instructor name and subject. Course summaries are separate and require matching profile/course/subject/review evidence; changed text invalidates a summary even if review IDs are unchanged. Incompatible v3 and older files remain untouched as misses. Refresh bypasses caches; partial review coverage/cursors persist across restart.

The Review course menu offers This course, All courses and original source labels/counts. Switching filters and revealing more downloaded reviews are local. Only **Find more for this class** sends a class filter to RMP. Keep three-review previews and a maximum of 50 source ratings retrieved per filter; combined cached raw data may exceed 50 when different classes are explicitly requested. Blank comments can make downloaded text counts lower than source-rating coverage. Overall source scores remain professor-wide.

## Privacy and attribution

RMP gets an ephemeral session with no cookie/credential store, persistent URL cache or redirects. Minimal typed requests fetch required data without webpage ads, scripts or analytics. Student comparisons, sorting, preferences, schedule context and summary prompts remain local. RMP still sees the public IP, timing and query/profile; this is exposure reduction, not anonymity. User-clicked source links open their browser separately. PCC networking remains unchanged.

Amaan's MIT license, copyright and reference revision are in THIRD_PARTY_NOTICES.md and the app resources. No code with an unverified license was borrowed. No hosted server, proxy, Tor, OHTTP or cloud AI was added.

## Verification

- Full suite: **125 XCTest tests passed, zero failures**. Coverage includes transport privacy/size bounds, retries/cooldown/cancellation/concurrency, native identity and pagination, local filtering and explicit course jobs, partial retry cursors, shared cache/subject isolation/restart, ambiguity recovery, and stale reviews/summaries. Existing legacy WebKit regressions also pass. On this Mac the browser tests require an unsandboxed test process; sandboxed attempts stalled and were stopped before the successful complete run.
- Release build and strict deep code-signature checks passed; notices were compared byte-for-byte with the bundled copy. Build scripts automatically save before/after snapshots under ignored app-history/. Archived executable/source hashes were verified against their manifest.
- Live Winter 2027: Daniel Hamman (POLSC 1000) and Jose Lopez (ETH 014) each returned two eligible profiles and required selection. All four identities were individually verified. Isolated app-model checks passed dismissal, persisted preferences, fresh verification, wrong-identity recovery to selection, replacement and cross-course cache reuse. An unavailable local summary endpoint preserved API data; the owner's running Ollama host was not stopped or used by this check.
- Native visual checks used a temporary app/storage: Winter 2027 Daniel ambiguity, chooser dismissal/reopening, Political Science selection, actual quit/relaunch persistence, Change profile to History, correct replacement source/reviews, original course-label menu/counts, local All courses filtering, explicit POLS001 expansion from 24 downloaded to the 50-rating limit against 86 reported by RMP, unchanged overall scores, and failed-summary retry retaining data. Temporary preferences were removed afterward. The release UI uses the same views; the acceptance-only storage/failure flags are DEBUG-only.
- Fresh MATH 005A / Fall 2026 native ratings pass: **2.05 seconds first result, 6.44 seconds overall**, 35 sections, 26 professors, 21 verified previews, three ambiguous and two unavailable. Every preview was capped at three. Earlier WebKit observation: 2.83/16.81 seconds. These are separate runs, not a controlled benchmark or latency guarantee.
- Live known-profile previews were approximately 0.14 seconds. Cross-course raw-cache reads after store recreation were approximately 0.0013–0.0020 seconds in the last isolated run; these do not measure complete app startup or a full-course cached search.
- Records: docs/verification/native-api-matching-2026-10-10.json, native-api-speed-2026-10-10.json and native-api-acceptance-2026-10-10.json. Earlier matching milestones remain in the October 9 records.

## History and remaining limitations

The pre-implementation app/source baseline is app-history/2026-10-10-before-native-api/. Each build now saves a prior-app/current-source snapshot before building and a matched app/source snapshot after successful signing. Manifests distinguish these associations; snapshots exclude private user data and do not roll back Application Support.

RMP's endpoint is undocumented and can change or reject requests; client tests cannot guarantee future server availability. A forced live RMP outage/rate limit and packet-level traffic capture were not performed. Failure/retry/cooldown/cookie/header behavior was inspected with deterministic URLProtocol tests, plus live identity-mismatch recovery. A complete VoiceOver session, another Mac, notarization/distribution and Windows remain unverified. The toolchain still emits its existing native SwiftPM-backend deprecation warning.

Course matching remains whitespace/case only; shorthand is deferred. Top-three recommendations, loading redesign, embedded AI, Windows and additional privacy infrastructure remain later milestones. Ollama is still separately required for summaries only. The future single-download summary experience needs a dedicated Apple-model/hardware/licensed-fallback plan.

No commit or upload was performed.
