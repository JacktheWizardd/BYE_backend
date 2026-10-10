# BYE native API implementation goal

Implement and verify BYE's native RMP retrieval, privacy improvements, shared professor cache, and review-course selector. Prioritize speed, reliable identity matching, and minimal exposure to RMP. Continue from the existing working tree; inspect unfinished changes before adding more. Keep PCC schedule retrieval unchanged. Do not commit or upload.

## Preserve history and credits

- Read the current roadmap, project status and implementation history.
- Preserve the previous app and corresponding source, including uncommitted work, before each implementation milestone. Exclude private user data and record what each snapshot contains.
- Retain applicable licenses and author credits for borrowed code. Verify licenses before incorporating additional repositories.
- Record changes, actual verification results, measured timings, remaining issues and external limitations in the handoff.

## Native retrieval and recovery

- Use a dedicated Swift BYEAPI module and Apple's URLSession, informed by the reviewed clients. Fetch source ratings and reviews independently of AI; no automatic WebKit fallback.
- Use shared connections, bounded concurrency, cancellation, timeouts, limited retries and safe cursor pagination. Preserve usable partial results.
- Preserve ID deduplication, compound-surname matching, PCC checks and explicit selection whenever multiple eligible profiles match. Never use department, rating or AI to break identity ties.
- Reverify profile ID, name and PCC identity before publishing fresh data. Keep profiles separate.
- Preserve subject-scoped remembered choices, individual retry and protection against stale asynchronous results after search/profile changes.

## Minimize RMP exposure

- Isolate networking from browser cookies, credentials and login state. Request only needed fields and use minimal headers.
- Keep schedules, comparisons, sorting, preferences and AI prompts local. Avoid tracking resources and unnecessary background retrieval.
- Do not claim anonymity: direct requests expose the public IP and query to RMP. No paid infrastructure, Tor, OHTTP or IP randomization in this milestone.

## Cache and course reviews

- Store verified raw profile data by school and profile ID in a versioned local cache with a 24-hour lifetime, reusable across courses and app restarts.
- Consult manual choices first; keep identity mappings scoped by instructor and subject. Scope summaries separately by profile, course and verified evidence.
- Preserve refresh/retry bypass and leave incompatible old cache files untouched as misses.
- Add This course, All courses and available original source course labels to the review selector. Preserve original labels and distinguish source totals from downloaded counts.
- Filter downloaded reviews locally first. Send a class-specific request only after explicit Find more for this class.
- Preserve three-review previews and a maximum of 50 retrieved reviews per filter. Filtering must not change the professor's overall source scores.

## Verification and completion

- Test matching, ambiguity, identity failures, pagination, partial failures, retries, cancellation, concurrency, cache reuse, subject isolation, restart persistence and stale reviews/summaries.
- Inspect outgoing requests for cookies, unnecessary identifiers, unrequested course filters and unexpected destinations.
- Run full tests, release build and signature verification.
- Live-check Winter 2027 Daniel Hamman with AI unavailable, another ambiguous professor when available, chooser dismissal, retry, restart persistence and Change profile.
- Measure cold retrieval and warm-cache behavior. Report only observed performance improvements and clearly identify unavailable external checks.
- Update documentation with the final behavior and actual results. Finish only when verification is complete or remaining limitations are explicitly documented.

## Later milestones

Keep the current summary provider functioning independently during this change. The future experience should provide summaries inside the app without a separately installed AI host; evaluate Apple's on-device model and a suitably licensed bundled fallback in a separate milestone. Do not promise universal Apple-model availability or silently add a cloud dependency.

Defer top-three ranking, course shorthand, loading redesign, Windows implementation and additional privacy infrastructure.
