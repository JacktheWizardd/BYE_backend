# Repository map and cleanup inventory

**Structure preparation:** October 21, 2026, based on main `2654650` (merged backend PRs #9 and #12). Repository names and runtime locations are unchanged. Backend contracts now have root workspace tooling; shared React/Tauri source lives in `BYE_website`.

## Purpose

Give students, contributors, Codex and Claude Code a reliable way to find active code without accidentally editing old experiments or release assets. Keep retained Windows/native macOS sources, schedule/review infrastructure and local student data untouched while the implemented shared frontend trial completes acceptance.

## Current paths and ownership

| Path | Classification | Maintained purpose | Cleanup decision |
| --- | --- | --- | --- |
| `apps/cross-platform/` | **Retained legacy — preserve** | Windows Electron + React source, persistence and tests | Not the target architecture or a fallback; do not archive, remove or migrate in this phase |
| `Sources/Classwise/`, `Sources/ClasswiseCore/`, `Sources/BYEAPI/` | **Retained legacy — preserve** | Native Mac app, Swift domain code and native RMP integration | Preserve until a replacement has shipped safely |
| `packages/api-contracts/` | **Backend-owned, canonical** | Versioned public TypeScript/OpenAPI contracts | Root pnpm workspace; frontend consumes an explicit snapshot |
| `package.json`, `pnpm-workspace.yaml`, `pnpm-lock.yaml` | **Backend contract tooling** | Private root workspace for `packages/*` | Excludes `services/` and legacy apps; no root deployment command |
| `Package.swift`, `Tests/` | **Retained legacy tooling** | Swift build and tests | Keep in their current locations |
| `services/schedule-api/` | **Active** | Independently deployed PCC schedule service, Supabase migrations and owner dashboard | Preserve deployment contract, credentials separation and own tests |
| `supabase/` | **Active records** | Review and database SQL and historical migrations | Do not re-home until all applied migrations and tooling are inventoried |
| `apps/web/` | **Compatibility pointer** | Explains that canonical browser source is in the sibling `BYE_website` repository | Retain pointer until references and agent guides are updated together |
| `scripts/` | **Mixed active** | Native packaging/signing, publishing, sync, agent coordination and experiment tools | Audit every script caller before moving anything |
| `docs/` | **Mixed active/historical** | Development status, architecture, release guides, experiments and verification | Coordinate overlapping PR #8 work and preserve dated records |
| `benchmarks/` | **Historical + reproducibility** | Performance and AI experiment code, fixtures and recorded evidence | Keep paths used by tests/records; consider a history index, not a blind move |
| `assets/` | **Active** | Branding and packaging assets | Preserve |
| `appcast.xml` | **Release-critical** | Native Mac update metadata | Do not move/rename or replace except through approved release flow |
| `test/` and local `archive/` | **Local test/backup area** | Local Mac test app and source snapshots | Keep local snapshots ignored and out of Git |

### Neighboring repository

`BYE_website` owns landing, browser/review UI, shared React application,
`apps/preview`, the isolated Tauri host, client adapters and canonical UI/core/tokens/fonts.
The retained Windows client vendors a snapshot; new browser/Tauri hosts use the
frontend workspace directly. Public contracts are owned here and exported
explicitly; neither checkout imports runtime code from its sibling.

### Workspace and independent toolchains

The root pnpm workspace covers only `packages/*`, currently `@bye/contracts`
version `1.0.0-preview.1`. Use Node 22.16+, pnpm 11.25.0 and TypeScript 5.9.3:

```sh
pnpm install --frozen-lockfile
pnpm typecheck
pnpm contracts:check <frontend-checkout>/packages/api-contracts
```

Snapshot checking is read-only. `pnpm contracts:export <frontend-contract-directory>`
is an intentional writing operation. See [contract instructions](../packages/api-contracts/README.md).
`services/schedule-api` stays outside the workspace, with npm, its existing
package lock, Node 24.3+ and current deployment/test commands. Swift and legacy
Electron retain their own toolchains. Root contract typechecking does not claim
coverage of those services or applications.

### Transitional backend implementations

| Current source in `BYE_website` | Future location here | Current phase |
| --- | --- | --- |
| `server/` API/source/review implementation | `services/web-api/` | Remains in frontend checkout until desktop acceptance |
| `workers/source/` | `services/source-worker/` | Worker/DO identities, migrations and bindings unchanged |
| `functions/api/` | Thin Pages forwarders remain frontend after later service-binding work | Existing handlers remain unchanged now |
| Backend tests, runtime fixtures and deployment tooling | Service-owned backend locations after dependency separation | Mixed frontend/backend tooling remains in place now |

Neither planned service directory is created. The frontend's `docs/REPOSITORY_MAP.md`
contains the detailed module, shared-domain, fixture, test and deployment-tool
inventory. `packages/core` supplies runtime algorithms, not just contract types;
that dependency and fixtures importing frontend demo data must be separated before
relocation. The existing schedule service and review system are not combined.
Full actual Windows/Mac acceptance, subsequent staging/rollback and separately
authorized production cutover remain required.

### Current source-of-truth documentation

- [Main README](../README.md) — component-level current status and quick start.
- [Engineering docs index](README.md) — guides and records.
- [UI parity](UI_PARITY.md) — known differences among web, Windows, and Mac.
- [Schedule API](../services/schedule-api/README.md) — independent backend operations and actual deployment state.
- [Windows verification](../apps/cross-platform/VERIFICATION.md) — tests and limitations.
- [Experiment tooling](../benchmarks/README.md) — historical model experiments and restrictions.
- [Historical records index](HISTORICAL_RECORDS.md) — what to retain versus archive.
- [Agreed architecture and migration gates](cross-platform-migration-proposal.md) — PR #9 is merged; PR #12 establishes contracts. Frontend PR #16 implements the isolated shared app trial; backend relocation remains pending.

## Coordination before later moves

- PRs #9/#12 and frontend #13/#16 are merged. They establish architecture,
  contracts and the isolated frontend trial, not completed backend relocation.
- Desktop PR #8 is a separate runtime/documentation workstream. Recheck its
  current diff/status before overlapping changes; do not recreate its moves.
- Recheck GitHub main, local Git status and the shared coordination board before
  edits. Preserve the Mac trial evidence and any newer schedule/runtime work.

## Safe cleanup order

1. **Document current ownership** and distinguish active, compatibility, historical, generated and local-only directories (this document).
2. **Review and integrate outstanding changes deliberately**; keep unrelated platform work separate and audit PR #8's runtime changes.
3. **Inventory references** with `git grep`, script paths, release scripts, CI, docs links, and agent instructions before any rename or move.
4. **Use Git tags for retired app implementations**, and preserve a small history index. Archive historical *documents* only after inbound links are updated or replaced by pointers.
5. Keep local build snapshots, student data, model weights, secrets and signing keys outside Git. Existing `.gitignore` explicitly excludes `/archive/`, `dist/`, model weights and local test apps.
6. Shared client work already belongs to the frontend workspace. Backend relocation, legacy retirement and production cutover require their own acceptance and authorization; none occurs in this preparation phase.

## Historical Phase 1 result and limits

For the subsequent physical record moves, exact old-to-new mapping, compatibility
pointers, checks and deferred work, see [Phase 2 cleanup](maintenance/phase-2-cleanup.md).

That phase was an **index and archive classification**, not a source tree restructure: no tracked application files were deleted, moved or renamed; no configuration, endpoint, database migration, dependency, user data, build, release, or Cloudflare/Supabase deployment changed. Future cleanup batches must carry their own verification and rollback notes.

## October 21 structure preparation

Added a private backend contracts workspace with frozen lockfile and root
check/export commands. Updated ownership guides for the implemented frontend
trial and transitional backend locations. No runtime sources, schedule-service
files, contract payloads, databases, migration records, release assets or
production configuration moved or changed.

Local preparation checks: frozen root install, contract typecheck and four-hash
frontend snapshot verification passed. Root check/export commands were exercised
against a temporary destination containing spaces; export/check round-trip passed,
and mismatched snapshots and missing destinations failed as expected. The real
frontend contract snapshot was unchanged. Schedule-service/native tests and
deployments were not run for this tooling/documentation change.
