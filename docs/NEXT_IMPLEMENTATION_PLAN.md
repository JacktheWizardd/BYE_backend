# BYE — Next implementation plan

Planning date: October 9, 2026 (America/Los_Angeles).

Status: agreed planning handoff only. None of the changes below have been implemented or verified. Implement and run the full verification on the Mac in a later session.

## Purpose and agreed decisions

Continue BYE as a personal macOS app. Do not expand platforms in this phase.

The next work is, in order:

1. Fix professor matching, starting with the Daniel Hamman bug, and add recovery controls.
2. Recognize course shorthand such as `MATH 5A` for `MATH 005A`.
3. Replace routine technical loading messages with progressive animated placeholders.
4. Evaluate a lightweight AI integration separately after the owner supplies a repository/provider.

Decisions confirmed with the owner:

- Reveal results progressively rather than waiting for a full-screen animation to finish.
- Recognize omitted leading zeros in both searches and RMP review labels.
- Remember manually chosen RMP profiles on this Mac, scoped to instructor and PCC subject.
- Leave the future AI architecture undecided until the owner's research is available.

Read `README.md` and `docs/PROJECT_STATUS.md` alongside this document. This document extends the existing handoff with the newly agreed behavior. Historical tests and live observations in those files are not verification of these planned changes.

## Current implementation context

- Native macOS 14+ SwiftUI app. The product is BYE; internal modules and cache paths retain `Classwise`.
- `ClasswiseCore` contains schedule parsing, course suggestions, identity matching, report caching, and summary validation.
- The app uses WebKit to read public rendered RMP pages. The initial pass uses two readers and retrieves ratings, difficulty, and up to three reviews per professor.
- Additional reviews are retrieved only for opened reports after the initial ratings pass. Review retrieval and summaries have separate single-worker queues.
- Ollama with `qwen3:4b` currently summarizes reviews. Numeric ratings and original review text come from RMP, not the model.
- Course comparison currently normalizes spacing and case but preserves leading zeros, so `MATH5A` does not match `MATH005A`.
- RMP lookup currently paginates before resolving retrieved candidates. Search pagination lacks the readiness check used for review buttons; a pagination error currently fails the whole lookup.
- This handoff was prepared on Windows. The existing SwiftUI/WebKit app and full tests require the Mac toolchain.

## 1. Fix professor matching and recovery

### Resolve existing candidates first

- Read the initial search results, deduplicate by RMP profile ID, and attempt identity resolution immediately.
- Continue requiring a matching professor name and PCC identity. Preserve compound-surname support.
- Paginate only when current candidates cannot resolve the lookup, with the existing limit of three additional search pages.
- Before clicking pagination, wait for a visible, enabled button with an attached click handler. Use bounded readiness polling and cancellation, not unconditional fixed sleeps.
- Merge each additional page with the retained candidates by profile ID.
- If pagination times out or fails, retain all collected candidates and resolve or offer those candidates. Do not discard usable results because a later page failed.

### Distinguish duplicate names using PCC subject information

- Carry the official subject code and `subjDesc` from the PCC schedule into lookup context.
- With one verified name-and-PCC candidate, preserve the current automatic match behavior.
- With multiple eligible candidates, auto-select only when exactly one department matches the official subject and the other candidates have known, different departments.
- Normalize department case, spacing, and punctuation. Use an explicit, tested alias map for supported equivalents such as `Math` and `Mathematics`.
- Do not use fuzzy matching, ratings, review counts, or AI to determine identity.
- Missing or conflicting department evidence, or multiple matching departments, requires student selection.
- Reverify the chosen profile ID, name, and PCC identity on its profile page before publishing its data.

### Profile chooser and remembered choices

- Add a distinct selection-required state rather than representing ambiguity as retrieval failure.
- Show a sheet containing eligible candidates' names, departments, schools, and source links. Display missing departments as unavailable.
- Require explicit selection; do not preselect based on ratings or review counts. Closing the sheet leaves the professor unresolved and allows reopening it.
- Save a manual choice only after verification succeeds.
- Store choices locally by normalized PCC instructor name and subject code, reusable across courses and semesters within that subject.
- Add `Change profile` to reports so the owner can reopen the chooser and replace a remembered selection.
- Reverify remembered profiles when retrieving fresh data. An identity mismatch returns to selection; a temporary network failure offers retry and preserves the preference.

### Individual retry and safe profile changes

- Add `Try again` to an unavailable professor. Retry only that professor, bypassing its report cache.
- Route retries and chosen-profile verification through the bounded two-reader preview pool. Repeated clicks must not enqueue duplicate jobs.
- Keep deeper report work gated while preview work is active, retaining the existing separate review and summary queues.
- When changing profiles, immediately clear old scores, reviews, summary, completion flags, and related errors. Keep PCC sections.
- Cancel or invalidate work belonging to the old profile. Before publishing or caching any asynchronous result, check search generation, professor generation, and selected profile ID.
- Preserve completed results for other professors.
- Keep the three-review preview behavior and the existing cap of 50 accessible reviews for deeper retrieval.

### Internal interfaces and cache compatibility

- Replace lookup's success/error-only contract with typed outcomes: verified profile, profile selection required, and unavailable.
- Extend professor state with subject metadata, eligible candidates, and selection-required status.
- Add a local profile-choice store separate from report caches. Inject its location for isolated tests.
- Introduce a new report-cache version scoped by instructor, canonical course, subject, and selected profile ID. Remembered choices must be consulted before selecting the applicable cached report.
- Existing report caches become misses after the update; leave old files untouched. Preserve the 24-hour report lifetime.
- Do not reuse old summaries under the new course-alias semantics. Fresh reports regenerate summaries from the newly selected evidence.

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
- Duplicate names with different departments resolve only under the agreed evidence rules.
- Missing, conflicting, and multiple matching departments require selection.
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
2. With Ollama closed, repeat the Winter 2027 Daniel Hamman search. Resolve using verified department evidence or offer the chooser; never silently discard candidates after pagination failure.
3. Compare `MATH 5A` and `MATH 005A` in the same published semester and inspect the canonical displayed code and course-review counts.
4. Choose a profile, restart BYE, confirm reuse within that subject, then use Change profile and verify that old reviews and summaries do not reappear.
5. Inspect fast, slow, cached, partial-failure, empty-result, and cancelled searches. Confirm selection, scrolling, and Change search remain usable.
6. Inspect Reduce Motion and accessibility labels. Verify that loading animation does not repeatedly announce itself.
7. Record actual test results and live observations in the project handoff; update README/status claims only after verification.

## Instructions for the next implementation session

Use this document as the agreed specification. Inspect repository instructions and the current code before editing. Implement items 1–3 in the order above, with focused regression checks after each stage and full Mac verification at the end. Keep item 4 deferred until the owner supplies the research/repository.

No implementation, new tests, build, live lookup, commit, or upload was performed while preparing this planning document.
