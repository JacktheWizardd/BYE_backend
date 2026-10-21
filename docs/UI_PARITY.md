# UI parity: web, Windows and Mac

> **Migration note (2026-10-20):** This page describes the existing v3 cross-platform UI implementation and differences, not an approved future framework. BYE is evaluating [shared React desktop consolidation, Tauri versus Electron, and optional mobile Capacitor](cross-platform-migration-proposal.md). Until a migration is verified and released, keep documenting differences in the existing Windows Electron, macOS SwiftUI and browser clients.


The approved v3 design (playful, search-first; plan in the website repository's `docs/APP_REDESIGN_PLAN.md`, mockup in [design/app-mockup-v3.html](design/app-mockup-v3.html)) is built three ways:

- **Shared React screens** live in the website repository (`BYE_website/packages/ui`). The web app uses them directly, and the Windows app gets a copy through `node scripts/sync-bye-shared.mjs` (into `apps/cross-platform/vendor/bye-shared/`, with the website commit in `SOURCE.json`).
- **Windows-only screens** (frame, first run, home, command menu, settings) live in `apps/cross-platform/src/renderer/src/app/`.
- **The Mac app** mirrors both in SwiftUI. It is native, so it never shares code with the others, but it shares tokens (`BYETokens.swift`, generated from `packages/tokens/tokens.json`) and the test vectors in `packages/core/vectors/`.

When you change a row below, say in the handoff whether its other columns changed too.

## Screens and parts

| Part | Web (`packages/ui`, `apps/web`) | Windows (`apps/cross-platform/src/renderer/src`) | Mac (`Sources/Classwise/Views`) |
| --- | --- | --- | --- |
| Tokens (color, type, radius, shadow, motion) | `packages/tokens/generated/tokens.css` | `vendor/bye-shared/tokens/generated/tokens.css` | `BYETokens.swift` (Phase 4; today `Palette` in `Components.swift`) |
| First run: welcome, name and ID card, confetti | — (web opens on search) | `app/onboarding.tsx`, `app/confetti.ts` | `WelcomeView`, `NameStepView` (Phase 4) |
| Frame: sidebar, Your classes, profile | — | `main.tsx` `Sidebar`, `app/app.css` | `NavigationSplitView` sidebar (Phase 4) |
| Home: greeting and course search | `apps/web` `SearchView` / `CourseField` (web layout) | `app/home.tsx` | `SearchView` → `HomeView` (Phase 4) |
| Command menu (Ctrl K / ⌘K) | — | `app/command-menu.tsx` | `CommandMenu` overlay (Phase 4) |
| Settings: name, updates, about | — | `app/settings-sheet.tsx` (check-only updates) | Settings scene + `UpdateSettingsView` (Sparkle) |
| "I'm free" day bubbles | `DayBubbles` | `DayBubbles` (vendored) | `AvailableDaysPicker` |
| Segmented sort | `Segmented` | `Segmented` (vendored) | Sort picker in `ContentView` |
| Professor list, sliding highlight, ↑ ↓ | `ProfessorList` + `ProfessorCard` (`ProfessorRow` available) | `ProfessorList` + `ProfessorRow` (vendored; Mac-style row actions) | `ProfessorListCard` |
| Loading rows | `LoadingRows` | `LoadingRows` (vendored) | `ProgressMeter` |
| Before a professor is picked | `EmptyDetail` with `sections` (format and term facts) | `EmptyDetail` (vendored) with `sections`, a course caption and the disclaimer | `CourseOverview` in `ContentView.swift` |
| Professor page | `Report` (chips filter, requests reviews on each filter) | `Report` (vendored) with `reviewFilter="select"`, `findMore`, `writeReview`, `summary` (AI note), `reviewPage={[3, 5]}` and saved per-professor state | `ProfessorReport` |
| Section card and seats | `SectionCard` | `SectionCard` (vendored) | `ClassCard` / `SeatMeter` in `Components.swift` |
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
- Windows section cards now use the shared `SectionCard`: the seat bar fills with open seats, without the Mac's ink, yellow and red thresholds. Score cards use the shared stats, without the Mac's helper lines ("Higher means better rated").
- Windows review cards name courses with RMP's labels (`HIST001`), as the select does. The web spaces them (`HIST 001`), as its chips do.
- The web app keeps its own search screen and phone navigation. The Windows home is app-only.
- Updates: the Mac uses Sparkle. Windows only checks `https://bye-before-you-enroll.pages.dev/windows/latest.json` when asked and links to the website.

## Rules every column keeps

- No "best" labels and no automatic professor selection.
- Source timestamps stay visible.
- The class-days rule is the same everywhere (`packages/core/vectors/class-days.json`).
- Controls are at least 44px, and motion is off for reduced motion.
- The student's name and recent classes stay on the device.
