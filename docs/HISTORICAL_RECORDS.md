# Historical records and archive policy

**Purpose:** preserve why past engineering decisions were made without mistaking old results for current behavior.

## Existing records

| Source | What it contains | Status |
| --- | --- | --- |
| [Implementation history](IMPLEMENTATION_HISTORY.md) | Dated design and implementation milestones | Historical; interpret by date |
| [Project status](PROJECT_STATUS.md) | Current and earlier implementation handoffs | Mixed; use the latest verified status and main README |
| [Experiment history](history/experiments/2026-10-11-local-summarization/README.md) | Paused model evaluation, methodology and outcomes | Historical; not authorization to restart inference |
| [Benchmark index](../benchmarks/README.md) | Scripts, datasets, AI quality/performance research | Keep reproducibility references intact |
| [Verification records](verification/) | Dated test JSON/Markdown evidence | Historical, not blanket production approval |
| [Release documentation](RELEASING.md) | Existing signed Mac packaging/update workflow | **Active, release-critical**; do not archive |
| [UI parity](UI_PARITY.md) | Current desktop/web feature differences | Active until replacement is validated |

## Archiving rules

- Prefer Git tags or immutable commit references for obsolete application implementations. Do not copy full source trees into tracked `archive/` folders just to preserve history.
- **The repository root `archive/` is ignored** and used for local build/source snapshots by `scripts/archive-app.py`; never store the only copy of an important tracked document there.
- Historical documents may eventually move to `docs/history/` after checking all inbound references, rewriting links and retaining lightweight pointers for frequently cited records.
- Do not move active scripts, fixtures, migrations, native update feeds, user state or server deployments merely because they were written earlier.
- Avoid carrying private student data, account information, signing material, local caches, GGUF model weights or unlicensed third-party content into Git history.
- Before retiring SwiftUI/Electron code, record verified replacement coverage, build steps, current release commit, stored-data compatibility, update paths, rollback and platform-specific exceptions.
- Keep review-database records distinct from the PCC schedule backend and do not conflate their migration histories.
- A file classified as historical is **not necessarily safe to delete or move**: build scripts, tests and references may depend on it.

## Cleanup checkpoints

This record introduces an index only. No historical source/doc files were relocated, deleted or otherwise modified. See [repository map](REPOSITORY_MAP.md) for active code ownership and proposed order, and the [engineering index](README.md) for operational documentation.

That paragraph records Phase 1. Phase 2 physically relocates the 16-file completed
experiment record into `docs/history/experiments/`, with two small compatibility
pointers for links owned by PR #8. See the [move manifest](maintenance/phase-2-cleanup.md)
and [history home](history/README.md). Benchmark tools and verification output paths
remain in place after checking their callers and recursive preservation inventories.
