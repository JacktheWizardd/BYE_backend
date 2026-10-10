# Implementation history

## 2026-10-10 — Sanitized build and local source milestone (0.3.0-beta.3, build 5)

Preserved beta.2 app/source at `app-history/20261010T190712-before-build-96ck98r1`. Sanitized the relocation record's identifying local paths. Stopped tracking the original generated app while preserving it locally; all dist outputs, Python caches and local history remain ignored. Retained source/test/docs/scripts and license credits.

Release builds now remap project/home prefixes and strip debug records before signing. The first privacy gate correctly rejected a remaining generated SwiftPM resource path; release resource lookup now uses packaged or adjacent resources without the generated absolute-path accessor. DEBUG regression tests keep their resource accessor. Added a recursive packaging gate covering personal paths, local username, UTF-8/UTF-16 and common credential markers, plus five regression tests. Central metadata and prerelease notes now identify beta.3/build 5.

Verification: **140 Swift tests and five Python privacy tests passed**. Built/staging/mounted/installed app scans, strict app/DMG signatures, integrity/checksum, arm64, notice comparison and installed byte equality passed. Installed from the newly mounted DMG, retained all 14 existing data files, ejected that image and launched. A separate image already mounted by the owner was left untouched. `math 5a` resolved MATH 005A Winter 2027, 8 sections/7 professors; 10 matching reviews remained available. Close/reactivate restored the same window/report. Original app executable still matches its saved baseline. The compiler emitted remapped-debug-module warnings; stripped app launched normally. No new summary benchmark.

Record: `docs/verification/privacy-beta3-2026-10-10.json`. A final app/source handoff snapshot accompanies this milestone. One local source commit includes prior pending Apple AI/beta.2 work and this cleanup. No push, tag change, release replacement, upload or history rewrite. Old commits, published beta.2 and downloaded copies retain historical paths; removing those requires separately authorized actions. Another-Mac/browser-download security prompts, physical Dock click and full VoiceOver remain unverified. The targeted scan does not prove absence of every possible identifier or secret.

## 2026-10-10 — GitHub-ready local DMG beta (0.3.0-beta.2, build 4)

Preserved beta.1 app/source before changes at `app-history/20261010T183306-before-build-x8x4gtac`. Added leading-zero comparison, selected-term official course resolution, shorthand suggestions and same-course review/evidence counting. Source labels and persistent keys are preserved; Apple matching-policy identity changed to reject old summaries while reusing raw profiles. Retained the main window with an application delegate so red-close and reactivation preserve the search/report; New search brings the window forward. Simplified the footer to “One simple search.”

Centralized release metadata in `scripts/beta-version.sh`; build targets arm64. Packaging checks matching version/build and architecture, creates a locally signed compressed DMG with Applications shortcut, rendered versioned instructions and notices, and writes a SHA-256 sidecar. Prepared `docs/GITHUB_PRERELEASE.md` for early testers. No personal caches, source/development files or model weights are packaged. No notarization, commit, tag or upload.

Verification: **140 tests passed, zero failures**, release build, strict signatures, DMG integrity/checksum, arm64, notices and archived source/executable hashes passed. Mounted final DMG, updated the separate beta in Applications, ejected and launched it. All 50 existing beta data files were unchanged by installation; original 0.2.0 executable matches its baseline. The first window-scene approach terminated on close during testing; final WindowGroup plus explicit retained-window reopen handling passed two close/reactivate cycles and minimize/reactivate with the same window/report. This was LaunchServices reactivation through computer-use controls, not a physical Dock click.

Installed shorthand checks: `math 5a` suggested MATH 005A; both spaced and compact shorthand submitted directly, returning Winter 2027's 8 sections/7 professors. Anahit Asadyan now shows 10 same-course MATH5A reviews of 47 downloaded; regenerated summary analyzed 10 same-course reviews but still returned no verified theme. No new speed/quality improvement claim. Actual GitHub browser download, quarantine prompts on another Mac, full VoiceOver and a physical Dock click remain unverified.

Record: `docs/verification/dmg-beta2-2026-10-10.json`. Final code release archive: `app-history/20261010T183739-after-build-4sx2k71c`; completed handoff snapshot saved afterward.

## 2026-10-10 — Apple AI private installation beta (0.3.0-beta.1)

Preserved the original 0.2.0 app/source in `app-history/20261010T170119-before-build-z_hkib2c`; `dist/BYE.app` remains unchanged. Built a separate bundle/data namespace with Apple Foundation Models, a summary-provider interface, search prewarming, fresh isolated sessions, whole-review token budgeting, source-ID validation, conservative two-review corroboration, versioned provider/evidence caches, retry and availability messages. No automatic Ollama fallback. Existing profile identity, queue cancellation, stale publication guards and 50-rating retrieval limit remain in place. SDK 27.0 builds the guarded macOS 26.4+ summary APIs with weak Foundation Models linking.

Produced a locally ad-hoc signed DMG with Applications shortcut, installation instructions and license notices; no model weights, private user data or development source are packaged. Mounted, copied to `/Applications/BYE Apple AI Beta.app`, checked its signature, ejected the image and launched the installed copy. Restart reused the Anahit report and cached summary. Hoa Ly initially failed generation, then Retry summary completed with a conservative no-theme result (22 of 50 downloaded reviews); ratings/reviews remained usable. UI text and a screenshot were inspected. This locally created installer does not validate internet-download security prompts or another Mac.

Full suite: **136 tests passed, zero failures**, including cache isolation/expiry/recreation, bounded complete evidence, invalid supporting IDs, negation/sentiment checks, unavailable provider, retries, and existing stale-result/concurrency/cancellation regressions. Release and package signature checks passed; bundled notices matched. Tests require an unsandboxed process for existing WebKit regressions. No commit, notarization or upload.

Timings on this M5/16 GiB Mac, macOS 26.6.2: first process-use generation 2.828 s, prewarmed report opening with saved raw evidence 2.866 s; cache read 0.762 ms, cached report selection logic 0.012 ms. Both real-profile generations returned no verified recurring theme. These timings are not useful-summary latency, full startup/render timings, or a fresh network-to-report measurement. The 2–3 second target remains unproven for consistently useful summaries. The source sample analyzed 19 whole reviews of 47 downloaded; none exactly matched MATH005A under current strict labels.

Quality: five fictional cases yielded two supported positives and three conservative empty results, including a missed valid concern. Earlier freeform and compact schemas generated unsupported/reversed claims; a bounded nested-array schema also failed on this OS. The final optional-field schema and conservative source-word/sentiment gate improve safety but sacrifice recall and do not prove semantic grounding. Apple summaries remain experimental; original reviews are authoritative. Readiness is available locally; unavailable states are tested by injection, not by disabling the owner's Apple Intelligence. No packet capture or OS-cold model test. A UI inspection-tool delay was unrelated to measured AI latency.

Records: `docs/verification/apple-ai-{speed,quality,trials,installation}-2026-10-10.json`. Build archives preserve iteration history without Application Support data. Original API milestone measurements below remain historical.

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
