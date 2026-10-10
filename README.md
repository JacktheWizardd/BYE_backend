# BYE — Before You Enroll

A native SwiftUI app for finding PCC sections and comparing the professors teaching them. Enter a course and semester, then compare source-reported RMP ratings, difficulty, review excerpts, and local AI summaries.

## Run

Current development build: **BYE Apple AI Beta 0.3.0-beta.3**, separate from the preserved 0.2.0 app.

Requirements: Apple Silicon Mac, macOS 14+ for PCC/RMP ratings and reviews; **macOS 26.4+ with Apple Intelligence enabled and its model ready for summaries**. Building requires Xcode with a modern macOS SDK. The app uses Apple's on-device model through Foundation Models, with no Ollama, API key, cloud AI, or separate AI host. macOS may need to download its system model once.

```sh
./scripts/build-app.sh
open "dist/BYE Apple AI Beta.app"

# Create the drag-to-Applications installer:
./scripts/package-beta.sh
```

The beta uses a separate bundle identifier and `~/Library/Application Support/BYEAppleAIBeta` for caches and manual profile choices. The original `dist/BYE.app` is preserved. Model weights are supplied by macOS and are not embedded in the app download.

The locally signed DMG is for this early-tester beta, not an Apple-notarized release. Installing this locally created copy does not test security prompts on an internet-downloaded copy or another Mac. See [installation instructions](docs/BETA_INSTALLATION.txt).

`Package.swift` can be opened in Xcode. Complete its normal first-launch/license setup when prompted. The scripts use the installed Xcode compiler and matching modern SDK; the previous forced macOS 15.4 SDK cannot compile Foundation Models. `CLASSWISE_SWIFT_BIN` and `CLASSWISE_SDK_PATH` can override these paths. Caches stay under `.build`; XCTest runs through Xcode's test agent. No external Swift packages are declared.

GitHub prerelease copy is prepared in [release notes](docs/GITHUB_PRERELEASE.md). The shared build version is defined in `scripts/beta-version.sh`; the DMG and its checksum are local release assets and are not committed. The owner published beta.2 separately; beta.3 assets remain local and are not uploaded.

## Working on another Mac

Clone the repository, complete Xcode setup, then run `./scripts/swift.sh test` and `./scripts/build-app.sh`. Launch `dist/BYE Apple AI Beta.app`. An eligible Mac with Apple Intelligence ready is required for summaries; ratings/reviews remain independent of AI. Intel/Windows builds and another-Mac verification are not included in this beta.

See [project status and pending fixes](docs/PROJECT_STATUS.md) before continuing development. Leading-zero course shorthand (for example `math 5a`) resolves to the selected semester’s official label. Matching/recovery is implemented: multiple eligible PCC profiles require an explicit choice, with remembered selections and individual retry. The loading redesign remains planned.

## What a search does

1. Retrieve published terms from PCC and fetch the selected term's schedule.
2. Match the exact normalized subject/course, exclude reserved/hidden rows (`R`/`X`) just as PCC’s public schedule does, deduplicate CRNs, and group instructors. Closed historical sections remain useful for past-semester research.
3. Use the dedicated native `BYEAPI` module to send structured requests to RMP's undocumented GraphQL endpoint through URLSession. Deduplicate profile IDs and verify the source ID, name and PCC identity. Multiple eligible profiles require **Choose profile**, regardless of department or ratings; other professors continue loading. Search pagination is limited to three additional pages and preserves candidates through later failures.
4. Retrieve up to three initial reviews for each verified professor through the shared two-reader preview queue. Publish previews progressively, independently of AI. Initial lookups, retries, discovery and selected-profile verification share this queue; a professor cannot have duplicate preview jobs.
5. After ratings finish, retrieve more reviews for opened reports, capped at 50 source ratings per filter. Detail retrieval and summaries have separate single-worker queues and pause new jobs while previews are pending. **Review course** offers This course, All courses and original source class labels with source counts. Switching filters and **View more reviews** use downloaded text locally. Only explicit **Find more for this class** sends a course filter to RMP. Preserve partial pages and cursors on failure or cancellation. Keep professor-wide scores separate from course-filtered reviews. No credentials, CAPTCHA bypasses, hardcoded professor results or automatic WebKit fallback are used.
6. Generate a structured summary using Apple's on-device `SystemLanguageModel`. Prewarm during search; select review pairs and paraphrase/check each pair in fresh isolated sessions. Prefer exact-course evidence when at least two matching reviews exist; otherwise disclose other-course evidence. Select complete recent reviews that fit the token budget after reserving instructions, schema, framing and output. Numeric scores are never model-generated. Each recurring theme must cite two distinct supplied review IDs and pass conservative word/sentiment corroboration against both sources, and the overview is assembled only from accepted themes. The UI discloses analyzed versus downloaded review counts. These checks do not prove semantic accuracy and can reject valid paraphrases; original reviews and source links remain available. Apple availability/failure messages offer retry and system settings, with no automatic Ollama fallback.


PCC endpoints:

- `https://prod-apiweb.pasadena.edu/api/getClassScheduleTerms`
- `https://prod-apiweb.pasadena.edu/api/classSchedule/{termCode}`

The API preserves stable source review IDs, original wording and posted dates. It verifies profile identity on every review page. Source header counts and downloaded text counts can differ and remain separate. The legacy WebKit reader remains for regression comparison, but production RMP retrieval uses the API.

The UI distinguishes overall RMP rating count from retrieved/analyzed text counts. Course matching ignores case, whitespace and leading numeric zeros while preserving subject and letter suffixes: a bare `014` or cross-listed `SOC014` is not silently treated as `ETH014`. Posted dates are not semester dates. Ratings are professor-wide, and summaries clearly disclose other-course evidence.

## Reliability and privacy

RMP retrieval is best effort. An inaccessible or missing profile stays in the list with **Cannot retrieve RMP info**, **Try again**, and an active **Check on RMP** link. Multiple eligible profiles show **Choose profile** with their departments, schools, and source links. **Change profile** lets you replace a verified selection; its old scores, reviews, and summary are cleared when a replacement is confirmed. Profiles are never merged. An RMP endpoint/schema change can require updating `Sources/BYEAPI`; an API failure stays actionable rather than falling back to browser retrieval. The app never fills gaps with sample ratings.

Results appear progressively; cancellation retains completed results. The footer distinguishes checking everyone’s ratings from loading the opened report. Changing the selected professor does not wait for AI to show its ratings. Verified partial previews are cached even when report loading is stopped; they resume deeper retrieval when opened again. Review filters and sorting operate on retrieved reviews, not the full RMP database. **View more reviews** reveals the next five already retrieved reviews. **Refresh** refetches PCC and bypasses the report cache.

Version 4 stores verified raw profile data by school/profile ID for 24 hours in `~/Library/Application Support/Classwise/Reports/`, reusable across courses. Identity indexes use normalized name and subject. Summaries are separately scoped to profile, course, subject and matching review evidence. Version 3 and older files remain untouched and are ignored. Manual choices persist separately in `~/Library/Application Support/Classwise/profile-choices-v1.json` by instructor and subject. Preferences take precedence; fresh retrieval reverifies them, temporary failures retain them and identity mismatches invalidate them. PCC schedules remain cached in memory for five minutes; Refresh bypasses schedule/report caches.

RMP networking uses an ephemeral session without cookie storage, credentials, URL cache or redirects. It requests only required fields and does not load webpage ads/scripts. Comparisons, preferences, schedules and summary prompts stay local. RMP still sees the public IP, timing and requested profile/name; this minimizes exposure without providing anonymity. Inspect the transport limits in `Sources/BYEAPI/README.md`. Source links open the user's browser only when clicked.

Every build saves local before/after app/source snapshots under ignored `app-history/`. Before-build snapshots preserve the prior app and current working source separately; after-build snapshots associate the signed app with its source. Snapshots exclude user Application Support data and are not user-data rollbacks. Credits and MIT notices are retained in `THIRD_PARTY_NOTICES.md` and the app resources. Apple on-device AI is included in the separate Mac beta. Windows and any bundled model fallback remain future milestones. Ollama code is retained for explicit legacy regression checks only.

## Verify

```sh
./scripts/swift.sh test
```

Tests cover PCC parsing/deduplication, exact-course matching, online classification, identity ambiguity and wrong schools, missing fields, source reader extraction, review ordering, cache expiry, AI evidence validation, published terms, and unavailable services.

The PCC fixture is a small excerpt of the public Summer 2026 ETH 014 schedule. Other fixtures explicitly use fictional test data and are never loaded by the production app.

## Interface

Off-white canvas, soft gray cards, readable black type, subtle borders, and a muted orange selection marker. Search requires two inputs. Results have an independently scrolling 300-pixel professor list and full report beside it. The default window is 1180 × 800, minimum 1000 × 700. Highest-rated results appear first, with lowest-difficulty and same-course review coverage alternatives. Missing-information links remain active and text stays readable.

Accounts, education-plan import, multi-professor comparison, cloud AI, Windows and notarization remain outside this beta. GitHub release assets are prepared locally; publication is pending.

## Beta.3 privacy cleanup — October 10, 2026

**140 Swift tests and five packaging-privacy tests passed.** Removed identifying local build paths from documentation and the distributed app. Release builds remap paths, strip debug records before signing, and avoid a generated resource accessor that embeds the build directory. Packaging checks bundled files for personal paths, local username and common credential markers. These targeted checks are not a comprehensive secret/privacy audit.

The locally signed beta.3 DMG, checksum, notices and installed app were verified. Updating preserved all 14 existing beta data files. Launch, shorthand search and closed-window restoration passed. The original BYE app and local history archives remain preserved, while generated apps/installers are excluded from Git.

The owner’s published beta.2 installer, downloaded copies, and old Git history still contain previous paths. This cleanup does not rewrite history or replace public assets. Beta.3 is prepared locally; no push, tag change or upload is included. See [verification](docs/verification/privacy-beta3-2026-10-10.json) and [prerelease notes](docs/GITHUB_PRERELEASE.md).

## Historical beta.2 installer verification — October 10, 2026

**140 tests passed, zero failures.** The Apple Silicon release, app/DMG signatures, installer integrity, checksum and bundled notices passed verification. The DMG was mounted, the separate beta updated in Applications, the image ejected, and the installed copy launched. All 50 existing beta data files were unchanged by installation; the original BYE app is preserved.

Installed checks: `math 5a` offered **MATH 005A** and both `math 5a` and `math5a` worked without selecting a suggestion. Winter 2027 returned 8 sections and 7 professors. Anahit Asadyan’s 10 downloaded `MATH5A` reviews now appear under This course and count as same-course summary evidence. The regenerated summary still reported no verified recurring theme. Two close/reopen cycles and minimize/reactivate restored the same report/window. The footer reads “One simple search.”

The approximately 1.19 MB DMG and its SHA-256 file are ready under `dist/`, with [copy-ready prerelease notes](docs/GITHUB_PRERELEASE.md). These checks cover local installation and application reactivation, not an actual GitHub browser download, physical Dock click, or another Mac. No commit, tag or upload was performed. See [verification record](docs/verification/dmg-beta2-2026-10-10.json).

## Historical Apple beta.1 results — October 10, 2026

The separate beta was installed from its signed DMG into Applications, ejected and launched successfully. **136 tests passed**; app/package signatures and license notices were verified. The original 0.2.0 app is preserved. Apple summaries work without a separate AI host, but remain experimental and can return no verified themes. One installed-app generation failure recovered with Retry summary.

| Measurement | Observed time | Scope |
| --- | ---: | --- |
| First process-use generation | 2.828 s | Previously retrieved evidence; no verified themes |
| Prewarmed report opening | 2.866 s | Saved raw evidence through summary completion; no verified themes |
| Summary cache read | 0.762 ms | Local storage only |
| Cached report selection | 0.012 ms | App logic only; excludes rendering/startup |

These measurements do **not** establish a 2–3 second useful-summary experience. The real-profile sample used 19 of 47 downloaded reviews and produced no accepted themes. Five fictional quality cases produced two supported positives and three conservative results; the gate also omitted a valid concern. Fresh network-to-report latency, an OS-cold model, another Mac and downloaded-app security prompts remain unverified. See [implementation history](docs/IMPLEMENTATION_HISTORY.md) and [timing evidence](docs/verification/apple-ai-speed-2026-10-10.json).

## Native API verification — October 10, 2026

The full suite passed **125 tests**, including native request privacy/limits, identity verification, retries/cancellation, partial pagination recovery, shared cache persistence, course filtering and stale evidence rejection. Release build and strict deep signature verification passed. Live Winter 2027 Daniel Hamman and Jose Lopez checks required explicit profile selection and passed persisted-choice verification, live identity-mismatch recovery and replacement. Native UI checks covered chooser dismissal, quit/relaunch, Change profile and explicit class retrieval while a test summary endpoint was unavailable.

### Speed comparison: v0.1.0 versus v0.2.0

Live MATH 005A / Fall 2026 searches covered 35 sections and 26 instructors. Both runs produced verified previews for 21 professors.

| Measurement | v0.1.0 — WebKit | v0.2.0 — native API | Observed improvement |
| --- | ---: | ---: | ---: |
| First verified professor result | 2.83 seconds | 2.05 seconds | 28% less waiting |
| Complete ratings pass | 16.81 seconds | 6.44 seconds | 62% less waiting |

The complete ratings pass finished **10.37 seconds sooner**, about **2.6× faster**. These were separate live runs with potentially different network/server conditions, not a controlled benchmark or guaranteed speedup. The ratings pass excludes deeper review retrieval and AI summaries.

These measurements describe the 0.2.0 retrieval milestone, not the Apple summary beta.

The new shared cache also reuses verified professor data across courses, avoiding fresh RMP requests while the cached data remains valid. These timings measure fresh retrieval, not warm-cache performance.

See [project status](docs/PROJECT_STATUS.md), the [v0.1.0 timing record](docs/verification/ratings-first-2026-10-09.json), and the [v0.2.0 timing record](docs/verification/native-api-speed-2026-10-10.json) for evidence and limitations. Every build now preserves local app/source history.

## Historical WebKit verification — October 9, 2026

- Release build and strict code-signature verification passed.
- The fast-retrieval update passed 67 XCTest tests, including bounded concurrency, incremental previews, cancellation, schedule reuse/refresh, course suggestions, partial-cache compatibility, eight tests of the actual app’s report queues, public-review identity/date handling, deferred click handlers, and local AI failures.
- Live Summer 2026 ETH 014 lookup: 14 sections, 10 instructors; fully online filter: 11 sections, 8 instructors.
- Live WebKit search matched Martha Toscano to Martha Joya/Toscano at PCC, retrieved 19 review cards, and read the source's 5.0 rating / 1.1 difficulty. The local model successfully summarized the 16 exact-course reviews.
- Native UI checks covered search/semester selection, progressive results, separate scrolling, professor selection, showing all professors, online filtering, review filtering/pagination, ranking controls, and changing an active search.
- Jose Lopez's public search returned two PCC profiles with the same name. The app correctly left the match unavailable and retained the manual RMP link; it did not pick one by rating. Ryan Howard also remained unavailable when no unique identity could be established.
- Accessibility labels were inspected through the macOS accessibility tree. A complete VoiceOver user session and testing on other Macs remain unverified.

## Historical WebKit timing — October 9, 2026

The development-only `--verify-speed /absolute/output.json` check bypasses report caches and uses the real app model for MATH 005A / Fall 2026. On this Mac it found 35 sections and 26 instructors, published the first verified profile at 2.83 seconds, and completed the ratings pass at 16.81 seconds. Twenty-one profiles were verified; five remained unavailable because public results were ambiguous or could not be retrieved. All verified previews had at most three reviews; no unopened report was paginated or summarized during that pass. Timing is an observation, not a guaranteed response time.

The small-model trial inputs under `Tests/ClasswiseCoreTests/Fixtures/summary-trial-cases.json` are explicitly fictional evaluation data and are never loaded by the app. Gemma 3 1B was fast but failed grounding and structured-output checks with the current prompt; download size alone is not a model quality gate.

For the historical Ollama version, Qwen3 4B was retained after the actual-prompt trials; the Apple beta now uses the system model. Both Gemma 3 1B and SmolLM2 1.7B generated invalid or unsupported results. An updated ten-case Qwen trial returned valid structures/source IDs in all cases, with seven useful grounded outputs and three conservative insufficient-feedback outputs; two paraphrases retained minor qualifiers that should be checked against original reviews. This is a small development check, not a general accuracy guarantee. `OllamaClient(model:)` permits future model trials without changing website retrieval or the UI. No model automatically replaces the configured default or sends data to cloud AI.

Run commands from the cloned project folder; the build script supports folder names containing spaces. Internal Swift module and cache-directory names remain `Classwise` for compatibility.

Final deeper-report regression: Anahit Asadyan’s MATH 005A / Fall 2026 preview contained three reviews at 1.99 seconds. Opening the report retrieved 47 distinct source review IDs by 4.67 seconds, while the source header reported 46 ratings. The app preserves these independent source counts. Qwen3 returned a valid conservative insufficient-feedback summary for this evidence; it did not invent recurring themes. The actual WebKit regression tests also verify deferred handlers, HTML entity normalization, visible posted dates, source identity, and exclusion of another professor’s reviews. See `docs/verification/review-expansion-2026-10-09.json`.


## Historical matching and recovery verification — October 9, 2026

The updated suite passed **90 XCTest tests**, including bounded retry/verification concurrency, duplicate-profile selection regardless of department, retained candidates after search pagination failures, delayed handlers, subject-specific preference persistence, profile-specific cache isolation, and stale review/summary rejection after profile changes. The release build, strict deep signature check, and native launch passed. Build scripts restore execute permission on the packaged executable, including when overwriting a transferred checkout.

Live Winter 2027 checks found two eligible Daniel Hamman profiles and two Jose Lopez profiles; both required selection, and all four were individually reverified without calling Ollama. Native UI checks covered chooser dismissal/reopening, explicit choice, restart persistence, Stop, and Change profile without restoring the previous profile’s evidence. Test-only preferences were restored afterward. A forced live network outage and a complete VoiceOver session were not performed. See `docs/verification/matching-recovery-2026-10-09.json` and `docs/verification/recovery-acceptance-2026-10-09.json`.

Development-only source matching check: `./scripts/swift.sh build`, then `.build/arm64-apple-macosx/debug/Classwise --verify-matching /absolute/output.json` (use the architecture-specific debug binary directory on other Macs). This native check uses temporary cache/choices, exercises an unavailable local summary endpoint without using the configured Ollama host, and removes its test storage afterward. Live source values may change.

## Apple summary cache

Apple summaries use a separate version 5 namespace keyed by provider/OS/prompt policy, school/profile, subject and course. Entries retain the exact whole-review evidence and expire 24 hours after generation. Legacy Ollama summaries are never displayed as Apple results. Raw profiles and subject identity indexes retain version 4 semantics inside the beta's separate storage. Changing source text, profile, course or provider prevents stale reuse.

## Apple AI beta quality limitations

The on-device integration is experimental. Initial live trials generated unsupported details, unrelated citations, and sentiment reversals. The beta therefore selects source pairs, paraphrases each pair separately, rejects unshared key words and obvious sentiment reversals, and runs a separate support check. It may retain only a corroborated leading observation. These conservative checks sacrifice coverage: useful source themes may be omitted, and the report can say Apple AI could not verify a theme even with many reviews. **Retry summary** is available for that result and reuses downloaded source data. Original reviews remain the basis for decisions. Neither lexical checks nor another model call establish general semantic accuracy.
