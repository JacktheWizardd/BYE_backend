# BYE — Before You Enroll

A native SwiftUI app for finding PCC sections and comparing the professors teaching them. Enter a course and semester, then compare source-reported RMP ratings, difficulty, review excerpts, and local AI summaries.

## Run

Requirements: macOS 14 or newer, Xcode (including developer tools, for building and running the full test suite), internet for PCC/RMP, and [Ollama](https://ollama.com/download) with `qwen3:4b` for summaries. No account, API key, or cloud AI is used.

```sh
# Once, if the model is not installed:
ollama pull qwen3:4b

# Build the app:
./scripts/build-app.sh

# Launch:
open dist/BYE.app
```

Open Ollama when you want AI summaries. If it is closed or the model is unavailable, PCC sections, retrieved RMP scores, and original reviews still work; open Ollama and select **Retry summary**.

`Package.swift` can also be opened in Xcode. Complete Xcode's normal first-launch/license setup when prompted. The scripts use the separately installed Command Line Tools SDK when available and the Xcode compiler, accommodating the developer-tool mismatch found on this Mac. `CLASSWISE_SWIFT_BIN` can override the compiler. The native SwiftPM build backend is currently necessary on this machine; the script records all caches under `.build`. For tests, it exposes XCTest alone and runs the compiled suite with Xcode’s XCTest agent, avoiding the incomplete Command Line Tools test launcher.

The build produces a locally ad-hoc signed `dist/BYE.app`. This is for personal use, not a notarized distribution package. No system settings or Xcode agreements are modified by the scripts.

## Working on another Mac

Clone this repository, open Terminal in the cloned folder, and complete Xcode’s first-launch setup. Then run:

```sh
./scripts/swift.sh test
./scripts/build-app.sh
open dist/BYE.app
```

Install Ollama separately and run `ollama pull qwen3:4b` if you want local AI summaries. Model weights, local report caches, and build caches are not part of the repository. PCC/RMP retrieval does not require the model. The included scripts contain accommodations for the toolchain on the original Mac; a different Xcode/SDK combination may need adjustment. No external Swift packages are declared, so no dependency lockfile is currently required.

See [project status and pending fixes](docs/PROJECT_STATUS.md) before continuing development. Matching/recovery is implemented: multiple eligible PCC profiles require an explicit choice, with remembered selections and individual retry. Course shorthand and the loading redesign remain planned.

## What a search does

1. Retrieve published terms from PCC and fetch the selected term's schedule.
2. Match the exact normalized subject/course, exclude reserved/hidden rows (`R`/`X`) just as PCC’s public schedule does, deduplicate CRNs, and group instructors. Closed historical sections remain useful for past-semester research.
3. Use the dedicated native `BYEAPI` module to send structured requests to RMP's undocumented GraphQL endpoint through URLSession. Deduplicate profile IDs and verify the source ID, name and PCC identity. Multiple eligible profiles require **Choose profile**, regardless of department or ratings; other professors continue loading. Search pagination is limited to three additional pages and preserves candidates through later failures.
4. Retrieve up to three initial reviews for each verified professor through the shared two-reader preview queue. Publish previews progressively, independently of AI. Initial lookups, retries, discovery and selected-profile verification share this queue; a professor cannot have duplicate preview jobs.
5. After ratings finish, retrieve more reviews for opened reports, capped at 50 source ratings per filter. Detail retrieval and summaries have separate single-worker queues and pause new jobs while previews are pending. **Review course** offers This course, All courses and original source class labels with source counts. Switching filters and **View more reviews** use downloaded text locally. Only explicit **Find more for this class** sends a course filter to RMP. Preserve partial pages and cursors on failure or cancellation. Keep professor-wide scores separate from course-filtered reviews. No credentials, CAPTCHA bypasses, hardcoded professor results or automatic WebKit fallback are used.
6. Send bounded review text to `http://127.0.0.1:11434/api/chat`, model `qwen3:4b`, for a structured summary. Numeric scores are never model-generated. When at least two exact-course reviews exist, the summary uses those reviews only; otherwise it includes clearly disclosed other-course evidence. Common themes require at least two distinct retrieved supporting review IDs. The overview is assembled from accepted themes instead of displaying an independently generated overview. With no accepted recurring themes, the report shows insufficient feedback. A single retrieved review does not invoke the model. AI wording still needs human judgment; original excerpts and source links remain available.

PCC endpoints:

- `https://prod-apiweb.pasadena.edu/api/getClassScheduleTerms`
- `https://prod-apiweb.pasadena.edu/api/classSchedule/{termCode}`

The API preserves stable source review IDs, original wording and posted dates. It verifies profile identity on every review page. Source header counts and downloaded text counts can differ and remain separate. The legacy WebKit reader remains for regression comparison, but production RMP retrieval uses the API.

The UI distinguishes overall RMP rating count from retrieved/analyzed text counts. Course matching is exact after whitespace/case normalization: a bare `014` or cross-listed `SOC014` is not silently treated as `ETH014`. Posted dates are not semester dates. Ratings are professor-wide, and summaries clearly disclose other-course evidence.

## Reliability and privacy

RMP retrieval is best effort. An inaccessible or missing profile stays in the list with **Cannot retrieve RMP info**, **Try again**, and an active **Check on RMP** link. Multiple eligible profiles show **Choose profile** with their departments, schools, and source links. **Change profile** lets you replace a verified selection; its old scores, reviews, and summary are cleared when a replacement is confirmed. Profiles are never merged. An RMP endpoint/schema change can require updating `Sources/BYEAPI`; an API failure stays actionable rather than falling back to browser retrieval. The app never fills gaps with sample ratings.

Results appear progressively; cancellation retains completed results. The footer distinguishes checking everyone’s ratings from loading the opened report. Changing the selected professor does not wait for AI to show its ratings. Verified partial previews are cached even when report loading is stopped; they resume deeper retrieval when opened again. Review filters and sorting operate on retrieved reviews, not the full RMP database. **View more reviews** reveals the next five already retrieved reviews. **Refresh** refetches PCC and bypasses the report cache.

Version 4 stores verified raw profile data by school/profile ID for 24 hours in `~/Library/Application Support/Classwise/Reports/`, reusable across courses. Identity indexes use normalized name and subject. Summaries are separately scoped to profile, course, subject and matching review evidence. Version 3 and older files remain untouched and are ignored. Manual choices persist separately in `~/Library/Application Support/Classwise/profile-choices-v1.json` by instructor and subject. Preferences take precedence; fresh retrieval reverifies them, temporary failures retain them and identity mismatches invalidate them. PCC schedules remain cached in memory for five minutes; Refresh bypasses schedule/report caches.

RMP networking uses an ephemeral session without cookie storage, credentials, URL cache or redirects. It requests only required fields and does not load webpage ads/scripts. Comparisons, preferences, schedules and summary prompts stay local. RMP still sees the public IP, timing and requested profile/name; this minimizes exposure without providing anonymity. Inspect the transport limits in `Sources/BYEAPI/README.md`. Source links open the user's browser only when clicked.

Every build saves local before/after app/source snapshots under ignored `app-history/`. Before-build snapshots preserve the prior app and current working source separately; after-build snapshots associate the signed app with its source. Snapshots exclude user Application Support data and are not user-data rollbacks. Credits and MIT notices are retained in `THIRD_PARTY_NOTICES.md` and the app resources. Embedded AI and Windows support remain future milestones; Ollama is still required only for summaries.

## Verify

```sh
./scripts/swift.sh test
```

Tests cover PCC parsing/deduplication, exact-course matching, online classification, identity ambiguity and wrong schools, missing fields, source reader extraction, review ordering, cache expiry, AI evidence validation, published terms, and unavailable services.

The PCC fixture is a small excerpt of the public Summer 2026 ETH 014 schedule. Other fixtures explicitly use fictional test data and are never loaded by the production app.

## Interface

Off-white canvas, soft gray cards, readable black type, subtle borders, and a muted orange selection marker. Search requires two inputs. Results have an independently scrolling 300-pixel professor list and full report beside it. The default window is 1180 × 800, minimum 1000 × 700. Highest-rated results appear first, with lowest-difficulty and same-course review coverage alternatives. Missing-information links remain active and text stays readable.

Accounts, education-plan import, multi-professor comparison, cloud AI, and distribution are outside this first version.

## Native API verification — October 10, 2026

The full suite passed **125 tests**, including native request privacy/limits, identity verification, retries/cancellation, partial pagination recovery, shared cache persistence, course filtering and stale evidence rejection. Release build and strict deep signature verification passed. Live Winter 2027 Daniel Hamman and Jose Lopez checks required explicit profile selection and passed persisted-choice verification, live identity-mismatch recovery and replacement. Native UI checks covered chooser dismissal, quit/relaunch, Change profile and explicit class retrieval while a test summary endpoint was unavailable.

### Speed comparison: v0.1.0 versus v0.2.0

Live MATH 005A / Fall 2026 searches covered 35 sections and 26 instructors. Both runs produced verified previews for 21 professors.

| Measurement | v0.1.0 — WebKit | v0.2.0 — native API | Observed improvement |
| --- | ---: | ---: | ---: |
| First verified professor result | 2.83 seconds | 2.05 seconds | 28% less waiting |
| Complete ratings pass | 16.81 seconds | 6.44 seconds | 62% less waiting |

The complete ratings pass finished **10.37 seconds sooner**, about **2.6× faster**. These were separate live runs with potentially different network/server conditions, not a controlled benchmark or guaranteed speedup. The ratings pass excludes deeper review retrieval and AI summaries.

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

Qwen3 4B remains the default summary model after the actual-prompt trials. Both Gemma 3 1B and SmolLM2 1.7B generated invalid or unsupported results. An updated ten-case Qwen trial returned valid structures/source IDs in all cases, with seven useful grounded outputs and three conservative insufficient-feedback outputs; two paraphrases retained minor qualifiers that should be checked against original reviews. This is a small development check, not a general accuracy guarantee. `OllamaClient(model:)` permits future model trials without changing website retrieval or the UI. No model automatically replaces the configured default or sends data to cloud AI.

Run commands from the cloned project folder; the build script supports folder names containing spaces. Internal Swift module and cache-directory names remain `Classwise` for compatibility.

Final deeper-report regression: Anahit Asadyan’s MATH 005A / Fall 2026 preview contained three reviews at 1.99 seconds. Opening the report retrieved 47 distinct source review IDs by 4.67 seconds, while the source header reported 46 ratings. The app preserves these independent source counts. Qwen3 returned a valid conservative insufficient-feedback summary for this evidence; it did not invent recurring themes. The actual WebKit regression tests also verify deferred handlers, HTML entity normalization, visible posted dates, source identity, and exclusion of another professor’s reviews. See `docs/verification/review-expansion-2026-10-09.json`.


## Historical matching and recovery verification — October 9, 2026

The updated suite passed **90 XCTest tests**, including bounded retry/verification concurrency, duplicate-profile selection regardless of department, retained candidates after search pagination failures, delayed handlers, subject-specific preference persistence, profile-specific cache isolation, and stale review/summary rejection after profile changes. The release build, strict deep signature check, and native launch passed. Build scripts restore execute permission on the packaged executable, including when overwriting a transferred checkout.

Live Winter 2027 checks found two eligible Daniel Hamman profiles and two Jose Lopez profiles; both required selection, and all four were individually reverified without calling Ollama. Native UI checks covered chooser dismissal/reopening, explicit choice, restart persistence, Stop, and Change profile without restoring the previous profile’s evidence. Test-only preferences were restored afterward. A forced live network outage and a complete VoiceOver session were not performed. See `docs/verification/matching-recovery-2026-10-09.json` and `docs/verification/recovery-acceptance-2026-10-09.json`.

Development-only source matching check: `./scripts/swift.sh build`, then `.build/arm64-apple-macosx/debug/Classwise --verify-matching /absolute/output.json` (use the architecture-specific debug binary directory on other Macs). This native check uses temporary cache/choices, exercises an unavailable local summary endpoint without using the configured Ollama host, and removes its test storage afterward. Live source values may change.
