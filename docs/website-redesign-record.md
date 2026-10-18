# Website redesign record (October 17–18, 2026)

What changed on the BYE website (`../BYE_website`, live at https://bye-before-you-enroll.pages.dev) during the October 2026 redesign, and how it was checked. The website repository's `AGENTS.md` "Current state" section stays the detailed source of truth; this record exists so work in this app repository knows what the website now looks like and promises.

No app code, release files, appcast or Pages project settings were changed by this work. `/download`, `/updates/appcast.xml`, `public/updates/` and `public/downloads/` are untouched, and every page keeps `noindex`.

## Why

- Testers mistook "Use BYE in your browser" for the full app with real data. The web option is now clearly a **demo with sample data**.
- The old landing page had too much whitespace and misaligned illustrations. The owner asked for a mobile-first redesign that keeps the BYE design system (ivory/linen/stone, Jet Black, yellow only for highlights, Libre Baskerville / Schibsted Grotesk / JetBrains Mono, self-hosted).

## What shipped

### Home page (website commit `479f15b`, merged to `main`)

- Rebuilt in React 19 + Tailwind v4 under `apps/landing/`, prerendered to static HTML and hydrated (`scripts/build-landing.mjs` writes `public/index.html` and `public/site/`). The old ivory page is kept in `archive/landing-ivory/`.
- Motion: GSAP ScrollTrigger, Lenis smooth scrolling and a lazy Three.js ambient layer. Motion starts only after hydration, and everything is off under Reduce Motion.
- "How it works" is an interactive mini app (Search → Days → Compare → Reviews). It is pinned and scroll-driven on desktop and phones, with a real PCC course list for the search step. It is labeled "Sample data for now · not real professors".
- Calls to action: "Try the demo →" (web) and "Install" for the Mac and Windows apps (Windows is shown as coming soon).
- The 404 page was restyled to match.

### Review page (website commit `292d350`)

- `/reviews/` (the live student review form, open to `@go.pasadena.edu`) restyled to match the home page. Only presentation changed; sign-in and submission logic are the same.

### Web demo (website commit `215291b`)

- `/demo/` restyled to match. A sticky "Sample data" banner, a "How the demo works" card and sample tags on professor data make it unmistakable that nothing is real.
- Real PCC course suggestions appear but are dimmed and cannot be selected in the demo.
- Typed search hints play in the empty course field.

### Plan for the apps (website commit `1f36040`)

- `docs/APP_REDESIGN_PLAN.md` in the website repository plans how to bring this look and motion to **the Mac app (SwiftUI) and the Windows app (Electron)**. It is a plan only and has not been started. Open questions are listed at its end: the AI summaries label on the Mac, a welcome screen, ambient dots in the apps, and the release version.

### October 18 fixes (owner commits this batch from GitHub Desktop)

- **Feedback section** on the home page (`#feedback`, also in the nav). It has topic tiles that prefill the email subject, an "Email us" button that opens the visitor's mail app to **byebeforeyouenroll@gmail.com** with a short template, and a copy-address fallback. There is no form backend and the site stores nothing.
- **Phone story overlap fixed:** the pinned "How it works" window now has a fixed, compact phone layout (fewer rows, one review on the Reviews step), so nothing overlaps while it is pinned. The sort menu is 44px tall.
- **Review-page course search ranking:** searching "Math" listed ABE/AHSD/BUS classes whose titles contain "math" before `MATH …`. The server (`server/reviews.ts`) now runs a code query first and then a title query, and merges them code-first. The code query is a prefix match that understands PCC's zero padding ("math 5a" → `MATH 005A`), plus a contains match on the code ("c1001" → `ENGL C1001`). Same Supabase client and key; no new permissions.
- **Demo typed hint:** the full placeholder no longer flashes between examples. A "|" typing caret was added, and there are now 8 examples (codes and titles).

## Verification (October 18, local)

- `pnpm typecheck`; `pnpm test` (72 unit tests, including a new course-search ranking test); `pnpm build` with the static checks: noindex everywhere, `/download` and appcast present, no fictional data in the live build, no Supabase keys in browser assets, feedback `mailto` present.
- Playwright browser suites in Chromium and WebKit at 390px and 1280px, all passing:
  - `pnpm test:browser` (demo)
  - `pnpm test:app:browser`
  - `pnpm test:reviews:browser`
- Built-site spot check at phone width: no sideways scroll on `/`, `/demo/`, `/reviews/` and the 404 page; tap targets at least 44px except inline text links.

## Not verified yet

- Course search ranking against the **real** Supabase catalog. Local fixtures return one row. After deploy, search "Math" and "Coll" on the live `/reviews/`: `MATH …` and `COLL 001` should come first.
- Real email delivery of feedback (it depends on the visitor's own mail app).

## Still open on the website

- A nicer domain. It must keep the current update address working.
- Live PCC/RMP data for the web app. The live `/app/` stays unlinked and disabled.
- Remove `noindex` / `robots.txt` at public launch.
- Optional ideas the owner has not decided on: a Gmail compose button, obfuscating the feedback address against spam, and a feedback form.
