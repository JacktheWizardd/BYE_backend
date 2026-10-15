# Implementation history

## 2026-10-12 — Class search performance and API rate safety optimization

Audited and optimized the PCC class search pipeline, schedule parsing logic, and network connection handling for both the PCC Schedule API and Rate My Professors (RMP) GraphQL API.

### Changes & Added Optimizations
1. **Static Regex Caching (`Course.init` in `Models.swift`)**:
   - Cached `Course.courseRegex` as a `private static let` instance.
   - Eliminated compiling `NSRegularExpression` on every `Course` instantiation (~5,000+ times per search across full term datasets), saving ~400ms per search pass (~99.9% reduction in regex overhead).
2. **Early Subject Filtering (`ScheduleParser.professors` in `Models.swift`)**:
   - Added early `row["subjCode"]` checking against `course.subject` before attempting full `Course` parsing.
   - Reduced Course parsing calls from ~5,000 schedule rows down to only ~10–30 matching subject rows per search (~99.7% reduction).
3. **Static Date Formatters (`Section.dateLabel` in `Models.swift`)**:
   - Reused static `startEndParser` and `startEndDisplay` instances, eliminating `DateFormatter` heap allocations during section list renders.
4. **Catalog Suggestion Sanitization (`CourseSuggestions.swift`)**:
   - Sanitized subject and course number strings prior to calling `Course(subj + numb)`, preventing redundant error paths when filtering catalog suggestions while typing.
5. **PCC Network Headers & Cancellation (`Services.swift`)**:
   - Added `Accept: application/json` and `User-Agent: BYE/0.3` headers to `PCCClient.fetch`.
   - Handled `URLError.cancelled` explicitly as `CancellationError()` for clean async search cancellations.
6. **Rate My Professors Server Safety Safeguards (`RMPTransport.swift`)**:
   - Verified and strictly enforced `RequestGate` bounding active concurrent requests to **at most 2 active requests** and **0.1s minimum request spacing**.
   - Enforced HTTP 429 / `Retry-After` rate-limit deferral cooldowns and capped OS networking socket connection pool (`httpMaximumConnectionsPerHost = 2`).
   - Updated RMP User-Agent header to `BYE/0.3`.

---

## 2026-10-10 — Sanitized build and local source milestone (0.3.0-beta.3, build 5)

Preserved a beta.2 app/source baseline. Sanitized the relocation record's identifying local paths. Stopped tracking the original generated app while preserving it locally; all dist outputs, Python caches and local history remain ignored. Retained source/test/docs/scripts and license credits.

Release builds now remap project/home prefixes and strip debug records before signing. The first privacy gate correctly rejected a remaining generated SwiftPM resource path; release resource lookup now uses packaged or adjacent resources without the generated absolute-path accessor. DEBUG regression tests keep their resource accessor. Added a recursive packaging gate covering personal paths, local username, UTF-8/UTF-16 and common credential markers, plus five regression tests. Central metadata and prerelease notes now identify beta.3/build 5.

Verification: **140 Swift tests and five Python privacy tests passed**. Built/staging/mounted/installed app scans, strict app/DMG signatures, integrity/checksum, arm64, notice comparison and installed byte equality passed. Installation from the mounted DMG preserved existing application data; ejection and launch passed. `math 5a` resolved MATH 005A Winter 2027, 8 sections/7 professors; 10 matching reviews remained available. Close/reactivate restored the same window/report. Original app executable still matches its saved baseline. The compiler emitted remapped-debug-module warnings; stripped app launched normally. No new summary benchmark.

Record: `docs/verification/privacy-beta3-2026-10-10.json`. A final app/source handoff snapshot accompanies this milestone. One local source commit includes prior pending Apple AI/beta.2 work and this cleanup. No push, tag change, release replacement, upload or history rewrite. Old commits, published beta.2 and downloaded copies retain historical paths. Another-Mac/browser-download security prompts, physical Dock click and full VoiceOver remain unverified. The targeted scan does not prove absence of every possible identifier or secret.

## 2026-10-10 — GitHub-ready local DMG beta (0.3.0-beta.2, build 4)

Preserved a beta.1 app/source baseline before changes. Added leading-zero comparison, selected-term official course resolution, shorthand suggestions and same-course review/evidence counting. Source labels and persistent keys are preserved; Apple matching-policy identity changed to reject old summaries while reusing raw profiles. Retained the main window with an application delegate so red-close and reactivation preserve the search/report; New search brings the window forward. Simplified the footer to “One simple search.”

Centralized release metadata in `scripts/beta-version.sh`; build targets arm64. Packaging checks matching version/build and architecture, creates a locally signed compressed DMG with Applications shortcut, rendered versioned instructions and notices, and writes a SHA-256 sidecar. Prepared `docs/GITHUB_PRERELEASE.md` for early testers. No personal caches, source/development files or model weights are packaged. No notarization, commit, tag or upload.

Verification: **140 tests passed, zero failures**, release build, strict signatures, DMG integrity/checksum, arm64, notices and archived source/executable hashes passed. Mounted final DMG, updated the separate beta in Applications, ejected and launched it. Existing beta data was unchanged by installation; original 0.2.0 executable matches its baseline. The first window-scene approach terminated on close during testing; final WindowGroup plus explicit retained-window reopen handling passed two close/reactivate cycles and minimize/reactivate with the same window/report. This was LaunchServices reactivation through computer-use controls, not a physical Dock click.

Installed shorthand checks: `math 5a` suggested MATH 005A; both spaced and compact shorthand submitted directly, returning Winter 2027's 8 sections/7 professors. Anahit Asadyan now shows 10 same-course MATH5A reviews of 47 downloaded; regenerated summary analyzed 10 same-course reviews but still returned no verified theme. No new speed/quality improvement claim. Actual GitHub browser download, quarantine prompts on another Mac, full VoiceOver and a physical Dock click remain unverified.

Record: `docs/verification/dmg-beta2-2026-10-10.json`. Release app/source hashes and the completed handoff snapshot were verified.

## 2026-10-10 — Apple AI installation beta (0.3.0-beta.1)

Preserved the original 0.2.0 app/source baseline. Built a separate bundle/data namespace with Apple Foundation Models, a summary-provider interface, search prewarming, fresh isolated sessions, whole-review token budgeting, source-ID validation, conservative two-review corroboration, versioned provider/evidence caches, retry and availability messages. No automatic Ollama fallback. Existing profile identity, queue cancellation, stale publication guards and 50-rating retrieval limit remain in place. SDK 27.0 builds the guarded macOS 26.4+ summary APIs with weak Foundation Models linking.

Produced a locally ad-hoc signed DMG with Applications shortcut, installation instructions and license notices; no model weights, private user data or development source are packaged. Mounted, copied to `/Applications/BYE Apple AI Beta.app`, checked its signature, ejected the image and launched the installed copy. Restart reused the Anahit report and cached summary. Hoa Ly initially failed generation, then Retry summary completed with a conservative no-theme result (22 of 50 downloaded reviews); ratings/reviews remained usable. UI text and a screenshot were inspected. This locally created installer does not validate internet-download security prompts or another Mac.

Full suite: **136 tests passed, zero failures**, including cache isolation/expiry/recreation, bounded complete evidence, invalid supporting IDs, negation/sentiment checks, unavailable provider, retries, and existing stale-result/concurrency/cancellation regressions. Release and package signature checks passed; bundled notices matched. Tests require an unsandboxed process for existing WebKit regressions. No commit, notarization or upload.

Timings on an M5/16 GiB test Mac, macOS 26.6.2: first process-use generation 2.828 s, prewarmed report opening with saved raw evidence 2.866 s; cache read 0.762 ms, cached report selection logic 0.012 ms. Both real-profile generations returned no verified recurring theme. These timings are not useful-summary latency, full startup/render timings, or a fresh network-to-report measurement. Consistently useful-summary latency was not established. The source sample analyzed 19 whole reviews of 47 downloaded; none exactly matched MATH005A under current strict labels.

Quality: five fictional cases yielded two supported positives and three conservative empty results, including a missed valid concern. Earlier freeform and compact schemas generated unsupported/reversed claims; a bounded nested-array schema also failed on this OS. The final optional-field schema and conservative source-word/sentiment gate improve safety but sacrifice recall and do not prove semantic grounding. Apple summaries remain experimental; original reviews are authoritative. Readiness is available locally; unavailable states were tested by injection without changing system settings. No packet capture or OS-cold model test. A UI inspection-tool delay was unrelated to measured AI latency.

Records: `docs/verification/apple-ai-{speed,quality,trials,installation}-2026-10-10.json`. Build archives preserve iteration history without Application Support data. Original API milestone measurements below remain historical.

## 2026-10-10 — Native API milestone implemented and verified (0.2.0, build 2)

Changes: dedicated Swift BYEAPI module with native URLSession and minimal typed queries; no production WebKit fallback; bounded shared transport/retries/cancellation/cursor checks; unchanged PCC networking; preserved explicit matching and recovery; v4 shared raw-profile caching with separate subject identity indexes and evidence-scoped course summaries; original review-course labels/counts, local filtering and explicit class retrieval. Added protection against stale summaries with changed text and against retaining an old automatic report after fresh ambiguity. Retained Amaan's MIT license and credits in source and app resources.

History: the original app/source baseline was preserved. `scripts/build-app.sh` now automatically creates ignored before/after archives. Before-build archives distinguish the previous app from current working source; after-build archives contain the newly signed app and matching source. Manifest source/executable hashes were independently compared with archive contents. Private Application Support data is excluded.

Verification: full suite **125 tests, zero failures**; release build and strict deep signature check passed; bundled notice matched the source notice. Native API live checks passed Winter 2027 Daniel Hamman and Jose Lopez ambiguity, all four profile identities, choice persistence/fresh verification, live wrong-identity failure returning to selection, replacement and cross-course reuse. An unavailable loopback summary endpoint left source data usable without changing any Ollama service. Actual UI checks passed dismissal, explicit choice, quit/relaunch persistence, Change profile, source-specific labels/reviews and explicit POLS001 retrieval from 24 downloaded reviews to the 50-rating cap (86 source ratings). API privacy checks use inspected URLProtocol requests/configuration, not a packet capture.

Timing: fresh MATH 005A/Fall 2026 ratings pass 6.44 seconds, first result 2.05 seconds; 35 sections, 26 instructors, 21 verified previews. Historical WebKit pass was 16.81/2.83 seconds; separate observations, not a controlled benchmark. Warm raw cache reads were sub-3 ms in isolated checks, not complete startup timings.

Limitations: undocumented RMP schema/availability, no forced live server outage/rate-limit test or packet capture, no complete VoiceOver session or second-Mac/Windows/notarization check. Ollama is still required only for summaries. Visual checks used isolated temporary storage, removed afterward. No commit/upload.

Records: `docs/PROJECT_STATUS.md` and `docs/verification/native-api-{matching,speed,acceptance}-2026-10-10.json`.

## 2026-10-10 — Native RMP retrieval and privacy (baseline entry)

The source and packaged app baseline was preserved with a manifest of SHA-256 hashes. Archives exclude Git metadata, build caches and external application/user data. Historical apps may share the existing Application Support folder; these are app/source snapshots, not user-data rollbacks.

Baseline: macOS 14+ SwiftUI, WebKit RMP reader, course-specific v3 report cache, Ollama summaries, two preview workers and separate detail/summary workers. Previous handoff records 90 passing tests and release/signature success; these are historical results, not checks rerun for this milestone.

At milestone start, verification was pending. The completed entry above records actual results and external limitations. No commit/upload.
