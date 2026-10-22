# BYE shared frontend and backend migration

Status: architecture agreed by the owner; implementation and replacement require the gates below. React + TypeScript is the shared application. Tauri 2 is the desktop candidate. Capacitor is the later mobile candidate. Electron has no role in the target architecture and is not a fallback.

## Repository ownership

Keep the GitHub repository names. BYE_website owns landing, shared application, desktop/mobile wrappers, canonical UI/core/tokens/fonts and client logic. BYE_Before_You_Enroll owns backend contracts and ultimately services, authentication, source synchronization, owner dashboard and migrations. Legacy desktop code and release tooling stay in place until replacement acceptance.

## Implementation sequence

1. Recheck main commits, instruction hashes, local changes, claims and desktop PR #8 before extraction. Preserve newer uncommitted schedule integrations and runtime work separately.
2. Create the pnpm frontend workspace with packages/app and apps/desktop. Reuse canonical UI/core/tokens directly, with a pinned backend-owned TypeScript contract. Mount an isolated browser preview; keep production navigation and deployment output unchanged.
3. Trial Tauri on actual Windows and Mac using separate BYE Preview identifiers and storage. Preserve Bridge.command / Bridge.subscribe through injected browser/native adapters. Product behavior remains TypeScript; Rust provides bounded requests, local persistence, window integration and approved external links. No Node runtime or AI sidecar.
4. Only after desktop acceptance, move website APIs, source Worker, tests and deployment tooling to the backend repository. Keep thin same-origin forwarding functions using service bindings. Preserve service identities, URLs, Durable Objects, databases, migrations, cookies, origin checks, rate limits, statuses and independent schedule/review boundaries. Validate staging and rollback before separately authorized production cutover.
5. After parity, add explicit read-only legacy preference import and a separately signed Tauri updater. Preserve existing apps, Sparkle feed, downloads and release assets until acceptance/rollback verification. Add Capacitor afterward.
6. Personal synchronization is a separate milestone for intentional saved classes and selected preferences. Tabs, filters, caches and unfinished review text remain local. Browsing works without signing in.

## Validation and release gates

Preserve existing route/response/error/freshness/authorization contracts. Browser calls stay same-origin; native calls use narrowly scoped commands and approved fixed origins. Privileged credentials stay server-side, and remote content receives no Tauri capabilities. Review writing stays in the verified-email website flow. AI remains disabled.

Test explicit professor selection, all-selected-days matching, asynchronous/unknown days, stale seats, cancellation, rapid switching, offline recovery, malformed responses, expired availability, rate limiting and independent BYE/RMP failures. Check 390px/1280px, keyboard access, reduced motion, touch targets and phone history/profile selection.

Record actual Windows and Mac persistence, shortcuts, external links, lifecycle, permission restrictions, startup, memory, CPU, responsiveness and package size under identical fixtures/settings. Browser WebKit checks do not replace Mac evidence. Critical Tauri failures become blockers; they do not introduce an Electron fallback.

Implementation branches and draft PRs are allowed. Merges, production deployments, public releases, automatic legacy imports and removal of existing applications require their separate authorization. Backend relocation remains gated on actual desktop trial acceptance.
