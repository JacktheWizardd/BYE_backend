# Cross-platform consolidation proposal (2026-10-20)

**Status: proposed — discussion and validation required.** This is an engineering decision record and migration plan, **not** a statement that BYE has already migrated. No runtime, release, database, API, or deployment change is authorized by this document.

## Why this is being considered

BYE v3's Windows frontend is implemented in Electron, React and TypeScript. The Mac app is implemented separately in SwiftUI. Bringing either app up to the other's UI/feature level creates repeated implementation, regressions and release delays. Planned AI features would magnify that cost because each platform currently needs separate integration and troubleshooting.

The goal is **one canonical implementation of common product behavior** without sacrificing necessary OS-specific behavior. The project is small enough to evaluate this before adding more duplicated features.

## Verified starting point

- **Windows:** `apps/cross-platform/` is an Electron/React/TypeScript desktop beta; the v3 redesign is in `main`. Preserve the working v3 implementation and its verification fixtures as the reference for a migration spike. **The v3 UI being implemented does not mean a public v3 release was shipped.**
- **Mac:** `Sources/Classwise/` is native SwiftUI with its own local storage, RMP integration and Sparkle update flow. It is not feature-identical to v3 Windows. Preserve the existing signed update/feed compatibility until a replacement is verified.
- **Canonical shared React:** `BYE_website/packages/{ui,core,tokens}` owns shared components, domain helpers and tokens. Windows currently imports an **explicit vendored snapshot** via `scripts/sync-bye-shared.mjs`, recorded in `SOURCE.json`. This is code sharing already, but changes still require a manual cross-repository sync; Mac still reimplements UI in SwiftUI.
- **Backend:** the standalone PCC schedule service is deployed, and the student-submitted BYE review service is separately live. **Desktop clients are not yet connected to the centralized schedule API** according to the project README; do not present backend readiness as client migration. The native `BYEAPI` RMP module is a Swift library, not a hosted BYE API. Preserve existing working RMP integrations while verifying any new client adapter.
- **AI:** review summaries are currently disabled in ordinary beta operation. Desktop source retains local-AI experiments/runtime integration. Do not turn inference, model downloads or paid cloud services on as an incidental part of this migration.
- **Distribution:** current Mac Sparkle feed, signed artifacts and Windows ZIP/update-check behavior must remain compatible until explicit release plans replace them.

The authoritative status for each component is in [the project README](../README.md), [UI parity](UI_PARITY.md), [current architecture](architecture.md), [Windows verification](../apps/cross-platform/VERIFICATION.md), and the website repository's `docs/shared-ui/` records. Older dated progress files are historical snapshots.

## Target direction — to validate, not yet selected for shipping

Use **React + TypeScript** as the canonical feature/UI implementation, and keep a thin adapter around runtime-specific services:

```text
Shared React screens + responsive design + TypeScript domain/core + typed API clients
   |                  |                    |
   |                  |                    +-- Browser web app
   |                  +-- Capacitor wrapper --> future iOS / Android (optional, later)
   +-- Tauri 2 wrapper --> Windows / macOS (desktop candidate)
                         platform adapters for storage, updates, native permissions and optional AI

Backend boundaries remain independent:
  - BYE student-submitted review service and student verification
  - PCC schedule database + versioned schedule API
  - RMP retrieval/integration subject to the existing transport rules
```

- **Tauri 2 desktop is a candidate, not a foregone conclusion.** Compare against *the working Electron v3 application*. Shared React on Electron for both desktop OSes may solve code drift at lower migration risk, even if its baseline resource overhead is higher.
- **Capacitor is a future mobile candidate, not a current dependency.** Mobile screens can reuse product logic and components while adapting safe areas, navigation, touch, backgrounding, and connectivity.
- Sharing source does **not** automatically synchronize installed app binaries. Desktop/mobile releases and signing remain per-platform.
- Platform-specific rendering differences remain: macOS WebKit, Windows WebView2 and mobile WebViews must all be tested.
- Never put service-role credentials, backend signing keys, RMP private material, or other privileged secrets in a React/Tauri/Capacitor bundle.

## Repository organization — explicitly undecided

Current repositories:

1. **`JacktheWizardd/BYE_Before_You_Enroll` (private):** SwiftUI, Electron Windows, schedule service, release scripts, tests, documents.
2. **`JacktheWizardd/BYE_website` (private):** Cloudflare website, browser app, Pages functions/reviews, `packages/core`, `packages/ui`, `packages/tokens`.

Evaluate these alternatives **before moving files**:

| Option | Advantages | Tradeoffs |
| --- | --- | --- |
| A. Keep two repositories and improve versioned shared-package handoff | Least disruptive now; backend and website deployment boundaries stay intact | Cross-repo sync remains; shared changes are not atomic across apps |
| **B. Put browser + desktop + eventual mobile frontend in one frontend workspace** (candidate recommendation) | One version of React/core/UI/tokens, one lockfile and coherent client-side changes | Requires a deliberate move of desktop source/build scripts; avoid triggering Cloudflare Pages deployment; legacy Mac release and API records need an explicit home |
| C. One repository for everything | Fully atomic changes and one project view | Largest disruption to build/release/security boundaries; schedule API, review service and website deployment become coupled |

**Suggested order:** maintain option A temporarily; prototype shared-desktop UI first; decide B versus A after the spike. No repo merge, rename, history rewrite, deletion or replacement is approved by this proposal. Do not introduce a third repository merely to solve a problem that a workspace can solve.

If B is chosen, the website workspace could evolve toward `apps/{landing,web,desktop,mobile}` and `packages/{ui,core,tokens,api-client,ai}`; keep the standalone schedule service logically separate and preserve its existing release/permission model. **These paths are illustrative, not existing folders or committed work.**

## Migration phases and release gates

### Phase 0 — establish a safe baseline

- Record the exact Windows v3 commit and feature parity list; preserve its reproducible build, fixture suite, and current download/check behavior.
- Record Mac supported flows, current update-feed compatibility, data locations, and student preference/cache migration requirements.
- Freeze unrelated feature rewrites during the spike; do not interrupt deployed services or existing student data.
- Inventory public API schemas, auth/CORS constraints and which client integrations still use PCC/RMP directly.

### Phase 1 — isolate the shared app and native boundaries

- Extract common React screens, product state, filters, professor identity/ambiguity rules, review provenance and API client contracts from Electron-specific dependencies.
- Define small runtime adapters for persistence, window/menus, opening URLs, update checks, filesystem/permissions and optional AI.
- Preserve current accessibility, keyboard/motion behavior, local preference semantics, privacy disclosures, and neutral professor choice.
- Keep backend services separate: schedule records are not the student-review dataset.

### Phase 2 — run an isolated desktop spike

- Build the same representative flows in Tauri 2 on **both Windows and macOS** without modifying the production Electron/SwiftUI releases.
- Exercise the professor search, course filters, section cards, identity chooser, review source labels, saved state, error/empty/offline behavior and backend contract.
- Profile comparable release builds on named test hardware: cold/warm startup, idle/search peak memory, CPU, package size, responsiveness, battery impact when measurable, and external API request counts. Do not claim a universal Tauri performance win from framework marketing.
- Check platform-specific tooling, signing/update path, WebView differences and feasibility of optional local AI.
- Compare an **Electron-on-macOS reuse spike** if needed: a single Electron desktop frontend is a valid fallback.

### Phase 3 — choose repo layout, integrate APIs and release desktop safely

- Decide A/B after measured costs and maintenance results, then document an accepted ADR.
- Introduce the chosen shared desktop app behind preview/beta flags; do not overwrite existing installers or break Mac Sparkle update URLs.
- Migrate to the hosted schedule API only through separately verified auth, freshness, rate-limit, caching and data correctness tests.
- Add contract tests for school schedule, professor information, original BYE reviews and RMP source labels; validate API access server-side.
- Map old local settings/caches explicitly before deciding on any data migration. Provide rollback to working Windows v3 and existing Mac beta.

### Phase 4 — mobile later

- Use Capacitor as an optional iOS/Android wrapper once desktop contracts and frontend composition are stable.
- Adapt the UI to phones, rather than shipping desktop navigation unchanged; verify app lifecycle, touch targets, safe areas, reduced motion, offline/slow connectivity and platform permissions.
- Mobile AI is a separate product/cost decision. Do not ship API provider secrets or silently enable a paid model.

## AI feature boundary

Keep one shared feature API for generating, validating, attributing, canceling and displaying AI assistance. Actual inference may be a *runtime adapter*: optional local desktop inference (where supported), or a deliberately approved server-side provider for other devices. Inputs should identify review/source provenance, and generated outputs must not silently become authoritative professor recommendations. Test empty/failed/slow/inconsistent model responses and privacy handling. No unapproved subscription or per-token bill is acceptable.

## Acceptance criteria before retiring either existing application

- Comparable core feature coverage on both desktop OSes with recorded exceptions and accessibility checks.
- Typed client/API contracts and explicit review-vs-RMP data provenance.
- Platform tests run on real Windows and Mac targets, not just type-check/build on one OS.
- Measurements versus Electron v3 and clear security/permission review.
- Working installers, signing, update/rollback plan, retained student preferences where required.
- No changes to live website demo, review verification, API keys, service deployment or release assets without separately reviewed rollout.
- A documented repository ownership decision and developer commands that a new contributor can reproduce.

## Open decisions for the project owner

1. Keep two repositories with versioned package snapshots, or consolidate the **frontend** into the existing website workspace after testing?
2. How important is keeping native SwiftUI-only capabilities versus a shared desktop interface?
3. Does Tauri materially beat an Electron-on-both-OSes approach on BYE's actual workload?
4. Should AI remain optional/local on desktop, and what (if anything) should mobile offer?
5. Which app version and migration path should existing Mac installations see?

**Next step:** evaluate repo topology with the owner, run a contained Tauri/React spike, record a go/no-go result, then update this proposal to an accepted or rejected ADR. No framework migration is represented as complete here.
