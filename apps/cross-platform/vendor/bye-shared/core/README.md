# BYE core (shared domain logic)

`domain.ts` and `types.ts` originated from BYE's Electron `src/shared` implementation and are maintained here. No desktop runtime or sibling checkout is needed to build the website. `api.ts` defines the website API's response contract.

Since the 2026-10-19 app redesign plan, this package is also the **shared client logic for the Windows app**. The app repository vendors it with `scripts/sync-bye-shared.mjs` (into `vendor/bye-shared/`), so a fix here reaches the web app and Windows. The Mac app keeps its Swift `ClasswiseCore` but must pass the same test vectors.

## Shared test vectors (`vectors/`)

JSON input/expected cases that every app runs:

| File | Rule | TypeScript | Swift |
| --- | --- | --- | --- |
| `class-days.json` | A section matches only if it meets on every picked day; fully online always matches; no announced days never matches | `fits` | `Section.fits(availableDays:)` |
| `format-label.json` | In person / Hybrid / Online · live / Online · async | `formatLabel` | `Section.formatLabel` |
| `review-order.json` | Six review sorts; missing scores and dates last | `orderReviews` | `Ordering.reviews(_:by:)` |
| `display-title.json` | PCC capitals to title case | `displayTitle` | `displayTitle(_:)` |

`tests/vectors.test.ts` runs them here. Change a vector only when every app changes with it.

## Parity notes

- Display helpers (`fits`, `filterSections`, `formatLabel`, `dateLabel`, `displayTitle`, `visibleText`, `orderReviews`, `preferredFilter`, `filterFinished`, `reviewURL` …) match Electron `src/shared/domain.ts`, which the Windows renderer uses.
- `professors()` and `sectionDetails()` still differ from the Electron copy. The website clamps every count and checks safe integers; Electron merges co-instructor meetings by CRN, formats places with `place()` and reports `subjectDescription` and `unannouncedMeetings`. The website server and API use these, so aligning them belongs to the BYE API work (redesign plan Phase 5).
- Known Swift/TypeScript difference outside the vectors: `delivery` for a section with no format codes is "In person" in TypeScript and "Online · scheduled meetings" in Swift.

Enrollment details and structured day fields follow the native `ClasswiseCore/Models.swift` behavior as of October 16, 2026. Preserve parity with explicit regression fixtures when changing course normalization, day filtering, identity matching or section grouping.

The server network adapter is ported from BYE's Electron client to Web APIs. Retained third-party notices, including Amaan's MIT client attribution and font licenses, are in the website-root `THIRD_PARTY_NOTICES.md`.
