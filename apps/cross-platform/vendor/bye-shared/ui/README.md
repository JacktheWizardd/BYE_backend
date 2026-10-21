# BYE shared UI

React screens shared by the web app (`apps/web`, demo and live) and the Windows app (the app repository vendors this folder with `scripts/sync-bye-shared.mjs`). The Mac app mirrors them in SwiftUI; the app repository's `docs/windows/UI_PARITY.md` maps each one to its Swift view.

| Export | What it is |
| --- | --- |
| `SurfaceProvider`, `useSurface`, `SampleTag` | Tells the screens whether they show the sample-data demo; `SampleTag` renders only there |
| `ProfessorCard` | One professor in the results list |
| `ProfessorRow` | The Mac app's row: scores and counts, with Choose profile, Try again and Check on RMP actions under it (Windows) |
| `Report`, `ReportState` | A professor's page: scores, sections, reviews. Takes the class-days rule as `matches` and optional `bye` reviews (host state + `load`/`write`): BYE scores above RMP, one Reviews list with BYE first, a Both · BYE · RMP toggle, an RMP tag or a collectible BYE stamp (`ByeStamp`, tier from `stampTier(review ID)`, never scores) on every card. Optional Mac extras: `reviewFilter="select"` (course menu with RMP counts), `preloaded` (reviews load on open; filters use saved reviews), `checking`, `writeReview`, a `summary` slot, `reviewPage` and `initial`/`onChange` to keep each professor's choices. Without `back` it has no phone header |
| `SectionCard` | One PCC section with seats; stale schedules hide seats |
| `Chooser` | Explicit RMP profile choice; BYE never guesses |
| `DayBubbles`, `Segmented` | "I'm free" class-day toggles; sliding segmented control |
| `ProfessorList` | Rows with a sliding highlight on the open professor, glide re-ordering, ↑ ↓ keys. Optional `renderRow` lets a host draw its own row (Windows adds Mac-style actions); its main button needs class `prof-card` |
| `LoadingRows`, `EmptyDetail` | Skeleton rows with playful copy; "Pick a professor." with the drawn arrow (never auto-opens). `EmptyDetail` adds a section count and format/term facts when given `sections` |
| `Wordmark`, `Avatar`, `Bar`, `Num` | Brand mark, initials avatar, rating bar, count-up number |
| `useCountUp`, `useTypedHint`, `useFlip`, `reducedMotion`, `MOTION` | Motion helpers using the token timings; all off for reduced motion |

Rules that travel with these screens:
- Keep every "Sample" label in demo mode.
- No "best" or "top pick" labels, and no automatic professor selection.
- Source timestamps stay visible, and 44px minimum targets.

Imports are relative (`../core`, `../tokens`), so the folder works the same when vendored. `styles.css` holds the v3 look (Phase 2, 2026-10-19) and uses only the shared `--bye-*` tokens. Base controls (`.button`, `.chip`, `.pill`, `.stat`, `.tag`) still live in `apps/web/src/styles.css`; they move here in Phase 3 when the Windows app needs them.
