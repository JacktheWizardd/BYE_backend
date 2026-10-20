# UI parity: web, Windows and Mac

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
| Professor list, sliding highlight, ↑ ↓ | `ProfessorList` + `ProfessorCard` | `ProfessorList` (vendored) + `ProfessorRow` in `app/report.tsx` (Mac-style row actions) | `ProfessorListCard` |
| Loading rows | `LoadingRows` | `LoadingRows` (vendored) | `ProgressMeter` |
| Before a professor is picked | `EmptyDetail` | `CourseOverview` in `app/report.tsx` (adds format and term facts) | `CourseOverview` in `ContentView.swift` |
| Professor page | `Report` | `Report` in `app/report.tsx` (adds Find more, course filter with RMP counts, Write a review, AI note) | `ProfessorReport` |
| Section card and seats | `SectionCard` | `ClassCard` / `SeatMeter` in `app/report.tsx` | `ClassCard` / `SeatMeter` in `Components.swift` |
| Profile chooser | `Chooser` | `Chooser` in `app/report.tsx` | `ProfileChooser` |

## Known differences to close

- The Windows professor page has features the shared web `Report` lacks: Find more for this class, the review-course menu with RMP counts, Write a review, "Listed at PCC as" and the AI policy note. The follow-up is to move them into `packages/ui` `Report` so the web gets them and Windows can use the shared page.
- The web app keeps its own search screen and phone navigation. The Windows home is app-only.
- Updates: the Mac uses Sparkle. Windows only checks `https://bye-before-you-enroll.pages.dev/windows/latest.json` when asked and links to the website.

## Rules every column keeps

- No "best" labels and no automatic professor selection.
- Source timestamps stay visible.
- The class-days rule is the same everywhere (`packages/core/vectors/class-days.json`).
- Controls are at least 44px, and motion is off for reduced motion.
- The student's name and recent classes stay on the device.
