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

Install Ollama separately and run `ollama pull qwen3:4b` if you want local AI summaries. Model weights, local report caches, generated apps, and build caches are not part of the repository. PCC/RMP retrieval does not require the model. The included scripts contain accommodations for the toolchain on the original Mac; a different Xcode/SDK combination may need adjustment. No external Swift packages are declared, so no dependency lockfile is currently required.

See [project status and pending fixes](docs/PROJECT_STATUS.md) before continuing development. The Daniel Hamman matching fix has been planned, but is not implemented in this version.

## What a search does

1. Retrieve published terms from PCC and fetch the selected term's schedule.
2. Match the exact normalized subject/course, exclude reserved/hidden rows (`R`/`X`) just as PCC’s public schedule does, deduplicate CRNs, and group instructors. Closed historical sections remain useful for past-semester research.
3. Read public rendered RMP search and profile pages with WebKit. Accept only a unique first/family-name match at PCC; compound surnames are supported without guessing nicknames.
4. Use two independent WebKit readers to retrieve source numeric fields and up to three initial reviews for every professor. Publish and cache each verified preview immediately. The first pass does not load extra review pages or invoke the model. Page data is checked as it arrives, avoiding fixed per-page sleeps.
5. After ratings finish, load additional reviews only for opened reports, up to 50 accessible reviews using public Load More buttons. Deeper retrieval waits for the visible control’s click handler to be attached; an unready or disabled control is not treated as an exhausted review list. The latest selected report replaces pending work. Website retrieval and summaries have separate single-worker queues, so another opened report can retrieve reviews while an AI summary is running. Only one local-model request runs at a time. Other professors keep their quick previews. Failed or interrupted deeper retrieval preserves the verified scores and collected text. No private GraphQL calls, credentials, CAPTCHA bypasses, or hardcoded professor results are used.
6. Send bounded review text to `http://127.0.0.1:11434/api/chat`, model `qwen3:4b`, for a structured summary. Numeric scores are never model-generated. When at least two exact-course reviews exist, the summary uses those reviews only; otherwise it includes clearly disclosed other-course evidence. Common themes require at least two distinct retrieved supporting review IDs. The overview is assembled from accepted themes instead of displaying an independently generated overview. With no accepted recurring themes, the report shows insufficient feedback. A single retrieved review does not invoke the model. AI wording still needs human judgment; original excerpts and source links remain available.

PCC endpoints:

- `https://prod-apiweb.pasadena.edu/api/getClassScheduleTerms`
- `https://prod-apiweb.pasadena.edu/api/classSchedule/{termCode}`

Public review links provide stable source review IDs. The reader merges embedded and rendered copies by those IDs, preserves the visible original wording and posted date, and excludes cards whose links identify another professor. Header counts and accessible review counts can differ on RMP and remain separate.

The UI distinguishes overall RMP rating count from retrieved/analyzed text counts. Course matching is exact after whitespace/case normalization: a bare `014` or cross-listed `SOC014` is not silently treated as `ETH014`. Posted dates are not semester dates. Ratings are professor-wide, and summaries clearly disclose other-course evidence.

## Reliability and privacy

RMP retrieval is best effort. An inaccessible, missing, or ambiguous profile stays in the list with **Cannot retrieve RMP info** and an active **Check on RMP** link. A website layout change can require updating `Sources/Classwise/Resources/RMPReader.js`. The app never fills gaps with sample ratings.

Results appear progressively; cancellation retains completed results. The footer distinguishes checking everyone’s ratings from loading the opened report. Changing the selected professor does not wait for AI to show its ratings. Verified partial previews are cached even when report loading is stopped; they resume deeper retrieval when opened again. Review filters and sorting operate on retrieved reviews, not the full RMP database. **View more reviews** reveals the next five already retrieved reviews. **Refresh** refetches PCC and bypasses the report cache.

Verified profiles and summaries are cached for 24 hours in `~/Library/Application Support/Classwise/Reports/`. The cache is scoped to professor name and searched course, with a completion flag distinguishing previews from completed review passes. Older cache entries remain readable. PCC schedules are cached in memory for five minutes and shared by real course suggestions and searches; concurrent callers share one request. Refresh bypasses both schedule and report caches. WebKit uses a nonpersistent website data store. No analytics or cloud service receives the local summaries. RMP and PCC still receive normal website requests.

## Verify

```sh
./scripts/swift.sh test
```

Tests cover PCC parsing/deduplication, exact-course matching, online classification, identity ambiguity and wrong schools, missing fields, source reader extraction, review ordering, cache expiry, AI evidence validation, published terms, and unavailable services.

The PCC fixture is a small excerpt of the public Summer 2026 ETH 014 schedule. Other fixtures explicitly use fictional test data and are never loaded by the production app.

## Interface

Off-white canvas, soft gray cards, readable black type, subtle borders, and a muted orange selection marker. Search requires two inputs. Results have an independently scrolling 300-pixel professor list and full report beside it. The default window is 1180 × 800, minimum 1000 × 700. Highest-rated results appear first, with lowest-difficulty and same-course review coverage alternatives. Missing-information links remain active and text stays readable.

Accounts, education-plan import, multi-professor comparison, cloud AI, and distribution are outside this first version.

## Verified on this Mac — October 9, 2026

- Release build and strict code-signature verification passed.
- The fast-retrieval update passed 67 XCTest tests, including bounded concurrency, incremental previews, cancellation, schedule reuse/refresh, course suggestions, partial-cache compatibility, eight tests of the actual app’s report queues, public-review identity/date handling, deferred click handlers, and local AI failures.
- Live Summer 2026 ETH 014 lookup: 14 sections, 10 instructors; fully online filter: 11 sections, 8 instructors.
- Live WebKit search matched Martha Toscano to Martha Joya/Toscano at PCC, retrieved 19 review cards, and read the source's 5.0 rating / 1.1 difficulty. The local model successfully summarized the 16 exact-course reviews.
- Native UI checks covered search/semester selection, progressive results, separate scrolling, professor selection, showing all professors, online filtering, review filtering/pagination, ranking controls, and changing an active search.
- Jose Lopez's public search returned two PCC profiles with the same name. The app correctly left the match unavailable and retained the manual RMP link; it did not pick one by rating. Ryan Howard also remained unavailable when no unique identity could be established.
- Accessibility labels were inspected through the macOS accessibility tree. A complete VoiceOver user session and testing on other Macs remain unverified.

## Fast retrieval verification — October 9, 2026

The development-only `--verify-speed /absolute/output.json` check bypasses report caches and uses the real app model for MATH 005A / Fall 2026. On this Mac it found 35 sections and 26 instructors, published the first verified profile at 2.83 seconds, and completed the ratings pass at 16.81 seconds. Twenty-one profiles were verified; five remained unavailable because public results were ambiguous or could not be retrieved. All verified previews had at most three reviews; no unopened report was paginated or summarized during that pass. Timing is an observation, not a guaranteed response time.

The small-model trial inputs under `Tests/ClasswiseCoreTests/Fixtures/summary-trial-cases.json` are explicitly fictional evaluation data and are never loaded by the app. Gemma 3 1B was fast but failed grounding and structured-output checks with the current prompt; download size alone is not a model quality gate.

Qwen3 4B remains the default summary model after the actual-prompt trials. Both Gemma 3 1B and SmolLM2 1.7B generated invalid or unsupported results. An updated ten-case Qwen trial returned valid structures/source IDs in all cases, with seven useful grounded outputs and three conservative insufficient-feedback outputs; two paraphrases retained minor qualifiers that should be checked against original reviews. This is a small development check, not a general accuracy guarantee. `OllamaClient(model:)` permits future model trials without changing website retrieval or the UI. No model automatically replaces the configured default or sends data to cloud AI.

Run commands from the cloned project folder; the build script supports folder names containing spaces. Internal Swift module and cache-directory names remain `Classwise` for compatibility.

Final deeper-report regression: Anahit Asadyan’s MATH 005A / Fall 2026 preview contained three reviews at 1.99 seconds. Opening the report retrieved 47 distinct source review IDs by 4.67 seconds, while the source header reported 46 ratings. The app preserves these independent source counts. Qwen3 returned a valid conservative insufficient-feedback summary for this evidence; it did not invent recurring themes. The actual WebKit regression tests also verify deferred handlers, HTML entity normalization, visible posted dates, source identity, and exclusion of another professor’s reviews. See `docs/verification/review-expansion-2026-10-09.json`.
