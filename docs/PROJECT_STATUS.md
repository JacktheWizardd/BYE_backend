# BYE development handoff

## Current application

Native macOS 14+ SwiftUI application, built from `Package.swift`. The app is named BYE; internal modules and the local cache folder retain the name Classwise.

- Search published PCC schedules by course and semester; deduplicate sections and group instructors.
- Read public RMP profiles with WebKit. Initial results include source ratings, difficulty, and up to three reviews, using two readers.
- Load additional reviews for opened reports, then request a local Qwen3 4B summary through Ollama.
- Support sorting, online filtering, original review excerpts, source links, cancellation, refresh, and a 24-hour course-specific cache.
- Include production JavaScript reader resources, test fixtures, development-only live checks, and build/signing scripts.

## Pending fix: Daniel Hamman

This fix was discussed and planned, but has NOT been implemented.

The current search lookup attempts pagination before resolving already retrieved candidates. A pagination timeout marks the entire lookup unavailable. Matching only accepts one name-and-PCC match, so separate History and Political Science profiles for the same name remain ambiguous.

Agreed behavior for the next implementation:

1. Retain candidates when additional search pages fail; wait for search-button handlers before clicking.
2. Resolve visible candidates first and paginate only when needed.
3. Carry PCC’s official `subjDesc` into matching. Automatically choose one profile matching the searched subject after verifying the name and PCC identity. Never choose by highest rating or review count.
4. Ask the student to choose a profile when department evidence is missing or multiple matches remain.
5. Add a per-professor retry action and retain bounded retrieval concurrency.
6. Clear old reviews and summaries when changing the selected RMP profile. Preserve the existing three-review preview flow and course-specific cache.
7. Test delayed buttons, timeouts with retained candidates, duplicate names/departments, wrong schools, and a live Winter 2027 Daniel Hamman search without depending on Ollama.

## Other known limitations

- Course review matching normalizes spacing and case only. `MATH5A` is not yet treated as `MATH005A`; course aliases are separate future work.
- RMP retrieval depends on the public page structure and remains best effort. Source rating counts can differ from accessible review counts.
- AI summaries may fail or return insufficient-feedback wording. Numeric ratings and original reviews remain independent of AI.
- The app is locally ad-hoc signed, not notarized for distribution. Other Macs and a complete VoiceOver session have not been verified.

## Rebuild and verification

Follow the README’s setup and commands. Install Xcode on the other Mac, complete its first launch, and install Ollama/model weights separately if summaries are needed. No accounts, tokens, or external Swift packages are required by the application itself.

The GitHub-readiness check builds and tests a clean copy without the original `.build` or `dist` folders. Historical live verification records are under `docs/verification`; their timing and website values are observations, not permanent expectations.
