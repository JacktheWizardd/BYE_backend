# Implementation history

## 2026-10-10 — Native API milestone implemented and verified (0.2.0, build 2)

Changes: dedicated Swift BYEAPI module with native URLSession and minimal typed queries; no production WebKit fallback; bounded shared transport/retries/cancellation/cursor checks; unchanged PCC networking; preserved explicit matching and recovery; v4 shared raw-profile caching with separate subject identity indexes and evidence-scoped course summaries; original review-course labels/counts, local filtering and explicit class retrieval. Added protection against stale summaries with changed text and against retaining an old automatic report after fresh ambiguity. Retained Amaan's MIT license and credits in source and app resources.

History: original app/source baseline remains at `app-history/2026-10-10-before-native-api/`. `scripts/build-app.sh` now automatically creates ignored before/after archives. Before-build archives distinguish the previous app from current working source; after-build archives contain the newly signed app and matching source. Manifest source/executable hashes were independently compared with archive contents. Private Application Support data is excluded.

Verification: full suite **125 tests, zero failures**; release build and strict deep signature check passed; bundled notice matched the source notice. Native API live checks passed Winter 2027 Daniel Hamman and Jose Lopez ambiguity, all four profile identities, choice persistence/fresh verification, live wrong-identity failure returning to selection, replacement and cross-course reuse. An unavailable loopback summary endpoint left source data usable without changing the owner's Ollama service. Actual UI checks passed dismissal, explicit choice, quit/relaunch persistence, Change profile, source-specific labels/reviews and explicit POLS001 retrieval from 24 downloaded reviews to the 50-rating cap (86 source ratings). API privacy checks use inspected URLProtocol requests/configuration, not a packet capture.

Timing: fresh MATH 005A/Fall 2026 ratings pass 6.44 seconds, first result 2.05 seconds; 35 sections, 26 instructors, 21 verified previews. Historical WebKit pass was 16.81/2.83 seconds; separate observations, not a controlled benchmark. Warm raw cache reads were sub-3 ms in isolated checks, not complete startup timings.

Limitations: undocumented RMP schema/availability, no forced live server outage/rate-limit test or packet capture, no complete VoiceOver session or second-Mac/Windows/notarization check. Embedded AI, top-three ranking, shorthand, loading redesign and extra privacy infrastructure remain deferred. Ollama is still required only for summaries. Temporary visual-check launch was initially rejected by automatic approval review; the owner approved it and the checks then completed with isolated storage, removed afterward. No commit/upload.

Records: `docs/PROJECT_STATUS.md` and `docs/verification/native-api-{matching,speed,acceptance}-2026-10-10.json`.

## 2026-10-10 — Agreed scope and implementation goal recorded

Owner requested a written log and reusable goal before proceeding. The current agreed scope is native URLSession RMP retrieval, reduced request exposure, reusable verified profile caching, and a review-course selector. PCC networking stays unchanged. Preserve licenses and author credits for borrowed code and preserve previous app/source versions before each implementation milestone.

The original reusable TypeScript-library proposal has been superseded for this macOS milestone by a dedicated native Swift API module. Amaan's client supplies reference ideas; a TypeScript runtime or external server is not required for the Mac app.

Privacy target: minimize information sent to RMP, not anonymity. RMP still receives the public IP and requested profile/query. Keep user comparisons, schedule context, preferences and summary prompts local; avoid cookies, login state, tracking resources and unnecessary requests. No Tor, proxy infrastructure or IP randomization is planned.

Longer-term product requirement: summaries should work inside the downloaded app without requiring a separate AI host. Evaluate Apple's on-device facilities and supported hardware separately; select a bundled fallback only after model/runtime licensing, size and performance are verified. This requirement remains open; the current milestone retains Ollama without making retrieval depend on it. Windows support and top-three recommendations also remain later milestones.

Implementation goal: `docs/NATIVE_API_IMPLEMENTATION_GOAL.md`. Native API/cache/UI changes are already present in the working tree, but full verification and handoff are unfinished. Do not describe this milestone as completed or reuse historical build/test results as current evidence. This documentation update makes no additional application-code changes.

## 2026-10-10 — Native RMP retrieval and privacy (baseline entry)

Baseline preserved at `app-history/2026-10-10-before-native-api/`: source archive includes existing uncommitted files, app archive preserves the old packaged app, manifest records SHA-256 hashes. Archives exclude Git metadata, build caches and external application/user data. Historical apps may share the existing Application Support folder; these are app/source snapshots, not user-data rollbacks.

Baseline: macOS 14+ SwiftUI, WebKit RMP reader, course-specific v3 report cache, Ollama summaries, two preview workers and separate detail/summary workers. Previous handoff records 90 passing tests and release/signature success; these are historical results, not checks rerun for this milestone.

Changes planned: native BYEAPI module, isolated HTTP transport, shared verified profile cache, explicit course-specific retrieval, course selector, API-only recovery, license notices.

At milestone start, verification was pending. The completed entry above records actual results and external limitations. No commit/upload.
