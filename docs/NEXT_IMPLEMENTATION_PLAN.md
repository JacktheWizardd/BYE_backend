# Current milestone — Native RMP API, privacy, shared cache, course reviews

Updated October 10, 2026 (America/Los_Angeles). This section supersedes the next-work ordering and deferred API research below. Preserve the older roadmap as historical context.

Reusable implementation goal: [NATIVE_API_IMPLEMENTATION_GOAL.md](NATIVE_API_IMPLEMENTATION_GOAL.md). Native API, privacy, shared cache and review-course selection are implemented. See [PROJECT_STATUS.md](PROJECT_STATUS.md) and [IMPLEMENTATION_HISTORY.md](IMPLEMENTATION_HISTORY.md) for the 125-test verification, live observations, build/signature results and external limitations. The older next-session instructions below are historical and do not authorize the deferred milestones.

- Build Sources/BYEAPI as a native Swift URLSession module. Use direct structured requests, no AI retrieval and no automatic WebKit fallback. Keep PCC retrieval unchanged.
- Preserve matching, explicit ambiguity selection, profile identity verification, subject-isolated preferences, retry, bounded queues, cancellation and stale-result guards.
- Isolate RMP cookies/logins and minimize request fields. Keep comparisons, schedules, choices and AI prompts local. RMP still sees IP and requested profiles. No Tor/OHTTP or hosted infrastructure.
- Share verified raw profile data across courses using a new 24-hour versioned cache; keep course summaries and identity mappings separate. Preserve old cache files as misses.
- Add This course / All courses / source course labels. Filter locally first. Fetch a specific class only on explicit Find more action. Preserve original labels, source totals and loaded coverage, three-review previews, 50 reviews per filter.
- Keep Ollama summaries functioning independently. Defer embedded AI replacement, top-three ranking, shorthand, loading redesign and Windows.
- Preserve app/source snapshots and record changes/tests/limitations in IMPLEMENTATION_HISTORY.md. No commit or upload.
- Verify request privacy, identity, retries/pagination/concurrency, partial failures, cross-course persistence, filtering, stale work, full tests, release/signature, and live ambiguous professors/timings.

---

# BYE — Next implementation plan

Updated October 9, 2026 (America/Los_Angeles).

## Current milestone

Stage 1, professor matching and recovery, is implemented and verified. See `docs/PROJECT_STATUS.md` for results. The owner narrowed this implementation to stage 1 only; stages 2–3 below remain planned, not implemented.

The final identity rule supersedes the original department-based proposal: **multiple eligible same-name PCC profiles always require explicit selection**. Departments are displayed to help the student choose, never used as an automatic tiebreaker. Verified manual choices are remembered per instructor and subject, reverified during fresh retrieval, and consulted before applicable version 3 report caches.

BYE remains a personal macOS app. Preserve progressive independent ratings, three-review previews, the 50-review deeper-retrieval cap, current source extraction, and Ollama summaries. Course suggestions and searches already share a short-lived semester schedule cache. Current course comparisons preserve leading zeros.

Agreed remaining decisions: recognize omitted leading zeros in search and review labels; reveal content progressively without an artificial minimum loading duration; leave future AI architecture undecided until the owner's research arrives.

## 2. Accept course shorthand consistently

### Resolve using official PCC courses

- Parse subject, optional number prefix, digit sequence, and suffix separately.
- Form an alias comparison key by removing leading zeros from the digit sequence only; normalize an all-zero digit sequence to `0`.
- Preserve subject, number prefix, and suffix. Keep official display codes separate from comparison keys.
- After loading the selected semester's schedule, prefer an exact official course-code match. Otherwise accept one unique alias match from the published course catalog.
- If several official codes match an alias, require selection from their official codes and titles. If none match, show the usual no-matching-classes result.
- Use the resolved official course everywhere downstream: schedule filtering, results header, source links, and cache lookup.
- Update the search field to the resolved official code. Pressing Enter must work without choosing an autocomplete suggestion.
- Reuse the schedule already fetched for suggestions when available; retain Refresh bypass behavior.

| Input | Expected behavior |
| --- | --- |
| `math 5a`, `MATH5A`, `math 05a` | Resolve to `MATH 005A` when published |
| `eth 14` | Resolve to `ETH 014` when published |
| `POLS C1000` | Preserve prefix and official numbering |
| `MATH 5B` | Never resolve to `MATH 005A` |
| `5A` | Require a subject |
| `SOC 14` | Never resolve to an ETH course |

### Apply one equivalence rule throughout

- Share the same conservative comparison between autocomplete, course resolution, review filters, review-coverage sorting, summary evidence selection, and analyzed-course counts.
- Reviews labeled `MATH5A` count toward `MATH 005A`; preserve the review's original label and wording in the interface.
- For full subject-and-number autocomplete input, place exact official matches first, followed by alias matches, then the existing broader code/title matches.
- Bare-number reviews remain unspecified-course evidence; do not silently treat them as exact-course reviews.
- Do not add subject synonyms, cross-listed-course equivalence, typo correction, or suffix guessing in this phase.

## 3. Seamless progressive loading

### Initial search and progressive results

- After a syntactically valid course and semester are submitted, transition directly into the existing two-column results layout.
- While PCC loads, show five placeholder professor cards and a placeholder report. Retain Change search and a Stop action.
- Do not invent names, counts, scores, or percentages for placeholders.
- Once PCC responds, show actual professors and sections. Retain placeholders only in regions awaiting information.
- Reveal each verified rating preview independently. Do not wait for other professors or AI.
- Display cached results immediately without an artificial delay or minimum animation duration.
- Schedule errors, course ambiguity, and empty results must replace the skeleton with the appropriate actionable state.

### Visual behavior

- Keep the existing off-white canvas, soft gray cards, and muted orange accent.
- Use a gentle 1.4-second opacity pulse for placeholders and approximately 180-millisecond content fades.
- Keep placeholder dimensions aligned with final content to minimize layout shifts.
- Preserve the selected professor and report scroll position as other ratings arrive.
- Keep existing sorting behavior but avoid animated row movement during the ratings pass.
- Animate only visible loading regions. Respect Reduce Motion with static placeholders and immediate content replacement.

### Status text and recovery

- Remove routine processing text such as `Checking ratings`, `Loading more reviews before preparing a summary`, and `Preparing summary on your Mac` from normal loading surfaces.
- Use local placeholders for pending scores, additional reviews, and summaries. Keep collected reviews readable while more arrive.
- Retain source attribution, the AI-summary label, evidence counts, and actionable failures. These explain the information, rather than exposing processing steps.
- After 15 seconds of unresolved loading, show a quiet `Taking a little longer…` message with Stop. Tie elapsed time to the relevant operation so switching reports does not inherit an unrelated timer.
- Stop ends animation and queued work, preserving completed results. Unfinished regions offer `Try again`.
- Unavailable profiles stop pulsing and show retry or profile-selection controls.
- Use explicit presentation states derived from actual operations rather than rendering internal progress strings. Retain operational diagnostics for development checks.
- Provide concise accessibility loading labels; do not repeatedly announce animation frames or reveal events.

## 4. AI research milestone — deferred

The owner will research a lightweight open-source model/API and provide its repository. No replacement provider, cloud dependency, or AI retrieval architecture is selected yet.

Keep current direct source extraction and Ollama summaries functioning during items 1–3. Do not build a speculative provider abstraction or replace retrieval as part of those changes.

When the repository arrives, assess:

- Whether the proposed capability is extraction, summarization, or both.
- Local versus hosted inference, supported Mac hardware, installation requirements, credentials, licensing, rate limits, and costs.
- Latency and structured-output reliability compared with the current implementation.
- Whether source values can be verified and original reviews retain stable identities, wording, and dates.
- How evidence validation, failures, cancellation, and cache compatibility would work.

Benchmark against saved source pages and existing fictional fixtures before integration. Extracted ratings must agree with source values; summaries must stay grounded in retrieved reviews. API/model selection requires a separate plan after research.

## 5. Tests and acceptance criteria on the Mac

### Automated matching tests

- Initial candidates resolve without unnecessary pagination.
- Delayed click handlers and disabled buttons are handled with bounded waits.
- Pagination timeouts retain candidates and offer selection when necessary.
- Multiple eligible same-name PCC profiles always require selection, even when one department matches.
- Department labels are informational only and never break identity ties.
- Wrong-school candidates are excluded; compound surnames still work.
- Saved choices survive store recreation and remain isolated by subject.
- Invalid saved identities require selection; transient failures preserve the preference.
- Retries stay bounded and repeated clicks do not create duplicate work.
- Changing a profile clears its previous data; stale retrieval and AI responses cannot publish or cache it again.
- Old report caches are ignored and new caches cannot cross selected profiles.

### Automated course tests

- Shorthand and official inputs produce identical sections for the same semester.
- Autocomplete recognizes shorthand, and direct Enter works without selecting a suggestion.
- Subject, prefix, and suffix distinctions remain intact; bare numbers do not become exact matches.
- Exact official matches take precedence over aliases; ambiguous aliases require selection.
- Unpublished shorthand produces an empty result, not an invented official code.
- Review filtering, review-coverage sorting, summary selection, and analyzed counts use the shared equivalence.
- Original review labels remain unchanged; all-zero digit normalization is stable.

### Automated loading and queue tests

- Initial schedule loading is distinct from an empty result.
- Cached content appears without an artificial wait.
- Partial results remain available through failures and cancellation.
- Terminal failures and Stop clear loading state.
- Search changes and profile changes reject stale responses.
- Slow-operation timing resets for new work.
- Existing queue, cache, extraction, cancellation, and summary-grounding tests continue to pass.

### Live and visual acceptance

1. Run `./scripts/swift.sh test` and `./scripts/build-app.sh`, then verify the release app's signature.
2. With Ollama closed, repeat the Winter 2027 Daniel Hamman search. Offer the chooser whenever multiple eligible profiles exist, regardless of department; never silently discard candidates after pagination failure.
3. Compare `MATH 5A` and `MATH 005A` in the same published semester and inspect the canonical displayed code and course-review counts.
4. Choose a profile, restart BYE, confirm reuse within that subject, then use Change profile and verify that old reviews and summaries do not reappear.
5. Inspect fast, slow, cached, partial-failure, empty-result, and cancelled searches. Confirm selection, scrolling, and Change search remain usable.
6. Inspect Reduce Motion and accessibility labels. Verify that loading animation does not repeatedly announce itself.
7. Record actual test results and live observations in the project handoff; update README/status claims only after verification.

## Instructions for the next implementation session

Matching/recovery stage 1 is implemented and verified; do not reintroduce automatic department-based selection. Read `docs/PROJECT_STATUS.md` and the acceptance records first.

Implement stages 2 and 3 in order, with focused regression checks after each and full Mac verification afterward. Stage 2 must introduce another cache version so current summaries are not reused under changed course-alias semantics. Keep stage 4 deferred until the owner supplies research. No commit or upload is implied by this handoff.
