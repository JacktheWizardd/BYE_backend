# UI parity: web, Windows and Mac

> **Migration direction:** [Agreed React/TypeScript migration](cross-platform-migration-proposal.md), Tauri desktop candidate and later Capacitor. Electron is legacy only. This page records existing platform differences; actual Windows and Mac preview acceptance must precede replacement.

> **Legacy inventory:** Current main retires the existing desktop apps and disables their network/update features. The implementation details below describe retained source and previous parity behavior; this migration does not reactivate those features.

The approved v3 design (playful, search-first; plan in the website repository's `docs/web-app/APP_REDESIGN_PLAN.md`, mockup in [design/app-mockup-v3.html](design/app-mockup-v3.html)) is built three ways:

- **Shared React screens** live in the website repository (`BYE_website/packages/ui`). The web app uses them directly, and the Windows app gets a copy through `node scripts/sync-bye-shared.mjs` (into `apps/cross-platform/vendor/bye-shared/`, with the website commit in `SOURCE.json`).
- **Windows-only screens** (frame, first run, home, command menu, settings) live in `apps/cross-platform/src/renderer/src/app/`.
- **The Mac app** mirrors both in SwiftUI (Phase 4, 2026-10-20). It is native, so it never shares code with the others, but it shares:
  - tokens: `Sources/Classwise/Views/BYETokens.swift`, generated from `packages/tokens/tokens.json` and copied by the same sync script; `TokenDriftTests` checks it against the vendored copy;
  - test vectors: `SharedVectorTests` runs the vendored `packages/core/vectors/` against `ClasswiseCore`.

When you change a row below, say in the handoff whether its other columns changed too.

## Screens and parts

| Part | Web (`packages/ui`, `apps/web`) | Windows (`apps/cross-platform/src/renderer/src`) | Mac (`Sources/Classwise/Views`) |
| --- | --- | --- | --- |
| Tokens (color, type, radius, shadow, motion) | `packages/tokens/generated/tokens.css` | `vendor/bye-shared/tokens/generated/tokens.css` | `BYETokens.swift` (`Palette` names in `Components.swift` read it), `Motion.swift` |
| First run: welcome, name and ID card, confetti | — (web opens on search) | `app/onboarding.tsx`, `app/confetti.ts` | `Onboarding.swift`: `WelcomeView`, `NameStepView`, `StudentIDCard`, `ConfettiBurst` |
| Frame: sidebar, Your classes, profile | — | `main.tsx` `Sidebar`, `app/app.css` | `Sidebar.swift` in a plain two-column frame (`ContentView`) |
| Home: greeting and course search | `apps/web` `SearchView` / `CourseField` (web layout) | `app/home.tsx` | `HomeView.swift` |
| Command menu (Ctrl K / ⌘K) | — | `app/command-menu.tsx` | `CommandMenu.swift` overlay; ⌘K also in the menu bar ("Search or Jump To…") |
| Settings: name, updates, about | — | `app/settings-sheet.tsx` (check-only updates) | `SettingsView.swift`: `SettingsSheet` in the window and `SettingsWindow` for ⌘, (Sparkle) |
| "I'm free" day bubbles | `DayBubbles` | `DayBubbles` (vendored) | `DayBubbles` in `Results.swift` |
| Segmented sort | `Segmented` | `Segmented` (vendored) | `Segmented` in `Results.swift` (also Settings tabs) |
| Professor list, sliding highlight, ↑ ↓ | `ProfessorList` + `ProfessorCard` (`ProfessorRow` available) | `ProfessorList` + `ProfessorRow` (vendored; Mac-style row actions) | `ProfessorList` + `ProfessorRow` in `Results.swift` |
| Loading rows | `LoadingRows` | `LoadingRows` (vendored) | `LoadingRows` in `Results.swift`; `ProgressMeter` in the footer |
| Before a professor is picked | `EmptyDetail` with `sections` (format and term facts) | `EmptyDetail` (vendored) with `sections`, a course caption and the disclaimer | `CourseOverview` in `Results.swift` (numbers from `CourseOverviewStats` in `ClasswiseCore`) |
| Professor page | `Report` (chips filter, requests reviews on each filter) | `Report` (vendored) with `reviewFilter="select"`, `findMore`, `writeReview`, `summary` (AI note), `reviewPage={[3, 5]}` and saved per-professor state | `ProfessorReport` (kept mounted; per-professor review choices in `AppModel`) |
| Section card and seats | `SectionCard` | `SectionCard` (vendored) | `ClassCard` / `SeatMeter` in `Components.swift` (seat levels from `ClasswiseCore`) |
| Profile chooser | `Chooser` | `Chooser` in `app/report.tsx` (Mac wording: Close, "Finding matching profiles…") | `ProfileChooser` |

## Behavior every desktop app keeps

- Your classes stay in the order they were added; the oldest drops off past five.
- Each class is a tab for the session: it keeps its open professor, filters, sort and each professor's review choices, and reappears at once when revisited.
- Switching professors updates the page in place: numbers glide from the old value, bars glide to the new width, and nothing remounts or flashes.
- Text fades in rather than sliding, and only short stickers tilt.

## Known differences to close

- Windows now uses the shared `Report`, `ProfessorRow` and `EmptyDetail` (2026-10-20). Their Mac extras are optional props. The web app has "Listed at PCC as", per-review "Original on RMP ↗" links, the "all courses are shown" note and the format/term facts, but it keeps:
  - review-course chips that request reviews as soon as a filter is picked, instead of the select and "Find more for this class";
  - 4 reviews first, then 6 more (the Mac and Windows show 3, then 5);
  - its own "Write a review →" link inside the BYE reviews block, instead of `writeReview`;
  - no AI policy note, because summaries are not part of the web beta;
  - `ProfessorCard` rows (taps open the chooser) instead of `ProfessorRow` actions.
- A section with no format codes now shows "Format not announced" everywhere (2026-10-20): the Mac `Section.formatLabel`, the web app, the shared `packages/core` (also for `formatUnknown`) and the Windows main code. The vendored copies in `apps/cross-platform/vendor/bye-shared/` update with the next `node scripts/sync-bye-shared.mjs` after the website commit; until then the Windows screens drawn from vendored code still say "In person" for empty codes.
- Seat bars: the shared `SectionCard` fills with open seats in one colour. The Mac bar fills with taken seats and turns yellow at 10 or fewer open and red at 5 or fewer (`SeatLevel`). Score tiles now match: the Mac dropped its helper lines for one caption under the tiles.
- Windows review cards name courses with RMP's labels (`HIST001`), as the select does. The web spaces them (`HIST 001`), as its chips do.
- The web app keeps its own search screen and phone navigation. The Windows home is app-only.
- Mac-only frame and screen details:
  - The Mac uses a plain two-column frame instead of `NavigationSplitView`, because macOS 26 draws that sidebar as floating glass. Its sidebar does not collapse.
  - The Mac Home field is focused on open, so it does not type example codes as the placeholder (`useTypedHint` on Windows).
  - The Mac ID card leaves out the term line until a semester loads, instead of showing a fixed "Fall 2026".
- Updates: the Mac uses Sparkle. Windows only checks `https://bye-before-you-enroll.pages.dev/windows/latest.json` when asked and links to the website.

## Rules every column keeps

- No "best" labels and no automatic professor selection.
- Source timestamps stay visible.
- The class-days rule is the same everywhere (`packages/core/vectors/class-days.json`).
- Controls are at least 44px, and motion is off for reduced motion.
- The student's name and recent classes stay on the device.
