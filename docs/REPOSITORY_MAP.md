# Repository map and cleanup inventory

**Review status:** initial nonbreaking cleanup, October 20, 2026. This describes the **current `main` tree**, not the proposed Tauri/Capacitor frontend structure.

## Purpose

Give students, contributors, Codex and Claude Code a reliable way to find active code without accidentally editing old experiments or release assets. Keep Windows v3, existing native macOS, deployed schedule/review infrastructure, and local student data untouched while a shared-client architecture is evaluated.

## Current paths and ownership

| Path | Classification | Maintained purpose | Cleanup decision |
| --- | --- | --- | --- |
| `apps/cross-platform/` | **Active — preserve** | Windows Electron + React frontend, local persistence, retained optional AI plumbing and tests | Working Windows v3 reference; **do not archive or migrate yet** |
| `Sources/Classwise/`, `Sources/ClasswiseCore/`, `Sources/BYEAPI/` | **Active — preserve** | Native Mac app, Swift domain code and native RMP integration | Preserve until a replacement has shipped safely |
| `Package.swift`, `Tests/` | **Active** | Swift build and tests | Keep in their current locations |
| `services/schedule-api/` | **Active** | Independently deployed PCC schedule service, Supabase migrations and owner dashboard | Preserve deployment contract, credentials separation and own tests |
| `supabase/` | **Active records** | Review and database SQL and historical migrations | Do not re-home until all applied migrations and tooling are inventoried |
| `apps/web/` | **Compatibility pointer** | Explains that canonical browser source is in the sibling `BYE_website` repository | Retain pointer until references and agent guides are updated together |
| `scripts/` | **Mixed active** | Native packaging/signing, publishing, sync, agent coordination and experiment tools | Audit every script caller before moving anything |
| `docs/` | **Mixed active/historical** | Development status, architecture, release guides, experiments and verification | Reorganize only after reconciling PR #8 and #9 |
| `benchmarks/` | **Historical + reproducibility** | Performance and AI experiment code, fixtures and recorded evidence | Keep paths used by tests/records; consider a history index, not a blind move |
| `assets/` | **Active** | Branding and packaging assets | Preserve |
| `appcast.xml` | **Release-critical** | Native Mac update metadata | Do not move/rename or replace except through approved release flow |
| `test/` and local `archive/` | **Local test/backup area** | Local Mac test app and source snapshots | Keep local snapshots ignored and out of Git |

### Neighboring repository

Canonical web frontend, React components, shared domain helpers and design tokens live in [`BYE_website`](https://github.com/JacktheWizardd/BYE_website). The desktop sync script currently creates a **vendored copy** under `apps/cross-platform/vendor/bye-shared/`; it is not yet an imported monorepo package. This copy should not be hand-edited.

### Current source-of-truth documentation

- [Main README](../README.md) — component-level current status and quick start.
- [Engineering docs index](README.md) — guides and records.
- [UI parity](UI_PARITY.md) — known differences among web, Windows, and Mac.
- [Schedule API](../services/schedule-api/README.md) — independent backend operations and actual deployment state.
- [Windows verification](../apps/cross-platform/VERIFICATION.md) — tests and limitations.
- [Experiment tooling](../benchmarks/README.md) — historical model experiments and restrictions.
- [Historical records index](HISTORICAL_RECORDS.md) — what to retain versus archive.
- [Cross-platform strategy proposal](https://github.com/JacktheWizardd/BYE_Before_You_Enroll/pull/9) — draft; **not an implemented migration**.

## Existing work that must be resolved before bulk moves

- [PR #8](https://github.com/JacktheWizardd/BYE_Before_You_Enroll/pull/8) proposes moving desktop documentation into topic folders **and** changes Windows application code. Review its actual diff and tests before merging; do not recreate those moves on `main`.
- [PR #9](https://github.com/JacktheWizardd/BYE_Before_You_Enroll/pull/9) separately documents cross-platform architecture. It overlaps root documentation from PR #8; reconcile links after either changes the docs tree.
- [Website PR #13](https://github.com/JacktheWizardd/BYE_website/pull/13) records proposed frontend architecture. Do not assume it is merged or that its design was approved for production.
- GitHub cannot reveal working-directory changes on either developer's local machine. Verify `git status --short` and the existing `.agents/` coordination board before source moves, and preserve uncommitted work.

## Safe cleanup order

1. **Document current ownership** and distinguish active, compatibility, historical, generated and local-only directories (this document).
2. **Review and integrate outstanding changes deliberately**; keep unrelated platform work separate and audit PR #8's runtime changes.
3. **Inventory references** with `git grep`, script paths, release scripts, CI, docs links, and agent instructions before any rename or move.
4. **Use Git tags for retired app implementations**, and preserve a small history index. Archive historical *documents* only after inbound links are updated or replaced by pointers.
5. Keep local build snapshots, student data, model weights, secrets and signing keys outside Git. Existing `.gitignore` explicitly excludes `/archive/`, `dist/`, model weights and local test apps.
6. **Only after the desktop prototype succeeds:** decide if client projects join the website frontend workspace and which legacy folders can be retired. Do not move the schedule backend as part of this housekeeping.

## Phase 1 result and limits

This phase is an **index and archive classification**, not a source tree restructure: no tracked application files have been deleted, moved or renamed; no configuration, endpoint, database migration, dependency, user data, build, release, or Cloudflare/Supabase deployment has changed. Future cleanup batches must carry their own verification and rollback notes.
