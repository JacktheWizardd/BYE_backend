# BYE web app (`apps/web`) — guide for AI coding agents

Read this before changing anything under `apps/web/`. It applies to any AI agent (Codex, Claude Code and others). The repository-wide rules in the root [AGENTS.md](../../AGENTS.md) still apply, including the shared `scripts/agents.py` board: claim your files before editing and run `done` when finished. **Update the "Current state" section whenever you change the app.**

## What this is

The browser version of BYE. It's published on the website at `/demo/` and is the main way phone users use BYE (about 80% of visitors).

- **Sample data only, for now.** Every instructor, rating, review and seat count is fictional (`src/demo-data.ts`). The app makes **no network requests**: no PCC, no Rate My Professors (RMP), no analytics, no font CDNs.
- **Mobile first.** Phones show one screen at a time (search → professors → report). From 760px up, the professor list and report sit side by side.
- **Static build** (Vite + React 19 + TypeScript), served from any folder (`base: './'`).

## How it fits together

| File | Role | Notes |
| --- | --- | --- |
| `src/main.tsx` | All UI: search screen, professor list, report, bottom-sheet chooser | Talks only to the `Bridge` interface |
| `src/styles.css` | All styles and design tokens, mobile first (`@media (min-width: 760px)` for desktop) | |
| `src/demo-bridge.ts` | `DemoBridge`: implements the shared `Bridge` contract (`command` + `subscribe`) over sample data | Mirrors the Electron `Engine` flow |
| `src/demo-data.ts` | Fictional PCC-shaped schedule rows, profiles, reviews, `demoSeats` | Never use real names or copied review text |
| `src/schedule.ts` | Class-days filter and format labels | Ported from `Sources/ClasswiseCore/Models.swift`; keep them the same |
| `../cross-platform/src/shared/` | Shared domain logic and types, imported as `@shared/*` | **Owned by the Windows app.** Don't edit from here (see below) |
| `tests/*.test.ts` | Node test runner via `tsx` | |

## Never change

- **No network requests and no real data** while the app is the sample-data demo. Don't add fetches, analytics, trackers or third-party fonts and scripts.
- **No real people.** A test checks that no instructor name from the saved real PCC schedule appears in the sample data. Keep it passing and keep names clearly fictional.
- **Neutrality.** Never label a professor "best", "top pick" or "recommended", and don't sort in a way that implies a pick beyond the student's chosen sort.
- **`apps/cross-platform/src/shared/*`.** The Windows Electron app depends on it. If the web app needs a domain change, propose it (or make it with the Windows app's tests passing: `cd apps/cross-platform && npm test`), and say so in your summary.
- **The "Demo · sample data" banner and the `noindex` tag in `index.html`.** Remove them only when the owner switches to live data or launches publicly.

## Change with care

- **Back-gesture history (`go()` / `popstate` in `main.tsx`).** Each phone screen is a history entry, so swipe-back returns to the previous screen instead of leaving the site. Desktop selections don't add entries. After any navigation change, re-test: landing page → search → list → report, then back four times.
- **Class-days rule (`fits` in `schedule.ts`).** It must match the Mac app: a section matches when it meets on *every* picked day; fully online sections always match; sections with no announced days never do. Change both apps together or neither.
- **Phone requirements:**
  - text inputs at 17px or larger (so iPhone doesn't zoom in)
  - tap targets 44px or more
  - safe-area padding (`env(safe-area-inset-*)`), `100dvh`
  - no sideways scrolling at 375–390px
- **The `Bridge` contract.** The UI must keep talking only to `Bridge`, so a live data source can replace `DemoBridge` later without UI changes.

## Safe to change or add

- UI layout, copy and styles, within the design rules below.
- More sample courses, sections, professors and reviews in `demo-data.ts`. Follow the existing row shape; add seats for every new CRN (a test checks this).
- New UI features that use data already in `Snapshot`/`Professor`.
- Tests. Add one for every behavior change.

## Design rules

The look follows the **BYE design system** and the **"Mobile web" page of the BYE prototype canvas** (claude.ai artifacts; the owner can share them).

- **Light mode only.**
- **Colors:**
  - Surfaces: ivory `--paper`, linen `--paper-2`, stone `--tile` for professor cards.
  - Text and buttons: Jet Black `--ink`; warm grey `--ink-2` for secondary text.
  - **Yellow `--highlight` only** for the wordmark swipe, rating bars and the progress meter.
  - Signal orange-red `--signal` only for problems, always paired with words ("Cannot retrieve RMP info.").
- **Fonts:**
  - Libre Baskerville (headings, scores), loaded from `Sources/Classwise/Resources`.
  - Schibsted Grotesk (text) and JetBrains Mono (course codes, CRNs), both bundled via `@fontsource`.
- **Writing:**
  - Sentence case.
  - No emoji.
  - Use → for forward actions, ↗ for external links, and · as a separator.
  - Describe states honestly ("Checking RMP…", "Cannot retrieve RMP info. Try again").

## Commands

Node 24 on the owner's Mac is keg-only, so first run `export PATH=/opt/homebrew/opt/node@24/bin:$PATH`.

```sh
cd apps/web
npm install
npm run dev          # http://localhost:5173
npm run typecheck
npm test
npm run build        # static output in dist/
```

**Publish to the website** (the owner commits and pushes the website repo themselves):
```sh
rm -rf ../../../BYE_website/public/demo && mkdir ../../../BYE_website/public/demo
cp -R dist/ ../../../BYE_website/public/demo/
```
The website repo has its own [AGENTS.md](../../../BYE_website/AGENTS.md).

## Check before you finish

1. `npm run typecheck && npm test && npm run build` all pass.
2. In a browser at **390×844** and **1280×800**:
   - search a course
   - open a professor
   - use the chooser for an instructor with two matching profiles ("Daniel Reyes" in ETH 014)
   - toggle class days
   - use the back gesture
   - confirm nothing scrolls sideways and no request goes to another host
3. If you changed what the site shows, rebuild and copy to `BYE_website/public/demo/`.
4. Don't commit unless asked. The owner commits in GitHub Desktop and wants a ready-to-paste **Summary** and **Description** for each repository you touched.

## Current state (update this when you change the app)

- **2026-10-15:**
  - Mobile-first rework is done: phone screens, history back gesture, class-days filter, invented seat counts, bottom-sheet chooser and recent searches (kept in this browser only).
  - 13 tests pass.
  - Published at `/demo/` on the website.
- **Not built yet:**
  - live PCC/RMP data. The browser can't call PCC or RMP directly because of CORS; it needs a server step, and RMP access needs a terms-of-use decision first.
  - a shared core package (moving `Engine` out of Electron)
  - AI summaries (Mac app only)
  - links out to PCC/RMP (off in the demo)
