# Phase 2 repository cleanup — October 21, 2026

Docs-only physical relocation, based on GitHub `main` at `0891cd3b8642517bed428901dfc967d8a2c6800c`.
Branch: `cleanup/docs-phase2-2026-10-21`. This record describes this branch;
it does not claim the changes are merged, released or deployed.

## Exact physical moves

| Old repository path | New repository path |
| --- | --- |
| `docs/experiments/2026-10-11-local-summarization/COMMIT_GUIDE.md` | [docs/history/experiments/2026-10-11-local-summarization/COMMIT_GUIDE.md](../../docs/history/experiments/2026-10-11-local-summarization/COMMIT_GUIDE.md) |
| `docs/experiments/2026-10-11-local-summarization/README.md` | [docs/history/experiments/2026-10-11-local-summarization/README.md](../../docs/history/experiments/2026-10-11-local-summarization/README.md) |
| `docs/experiments/2026-10-11-local-summarization/RESULTS.md` | [docs/history/experiments/2026-10-11-local-summarization/RESULTS.md](../../docs/history/experiments/2026-10-11-local-summarization/RESULTS.md) |
| `docs/experiments/2026-10-11-local-summarization/VALIDATION.md` | [docs/history/experiments/2026-10-11-local-summarization/VALIDATION.md](../../docs/history/experiments/2026-10-11-local-summarization/VALIDATION.md) |
| `docs/experiments/2026-10-11-local-summarization/data/README.md` | [docs/history/experiments/2026-10-11-local-summarization/data/README.md](../../docs/history/experiments/2026-10-11-local-summarization/data/README.md) |
| `docs/experiments/2026-10-11-local-summarization/data/candidates.csv` | [docs/history/experiments/2026-10-11-local-summarization/data/candidates.csv](../../docs/history/experiments/2026-10-11-local-summarization/data/candidates.csv) |
| `docs/experiments/2026-10-11-local-summarization/data/load-and-resources.csv` | [docs/history/experiments/2026-10-11-local-summarization/data/load-and-resources.csv](../../docs/history/experiments/2026-10-11-local-summarization/data/load-and-resources.csv) |
| `docs/experiments/2026-10-11-local-summarization/data/matched-case-timings.csv` | [docs/history/experiments/2026-10-11-local-summarization/data/matched-case-timings.csv](../../docs/history/experiments/2026-10-11-local-summarization/data/matched-case-timings.csv) |
| `docs/experiments/2026-10-11-local-summarization/data/original-candidates.csv` | [docs/history/experiments/2026-10-11-local-summarization/data/original-candidates.csv](../../docs/history/experiments/2026-10-11-local-summarization/data/original-candidates.csv) |
| `docs/experiments/2026-10-11-local-summarization/data/prototype-bundle-sizes.csv` | [docs/history/experiments/2026-10-11-local-summarization/data/prototype-bundle-sizes.csv](../../docs/history/experiments/2026-10-11-local-summarization/data/prototype-bundle-sizes.csv) |
| `docs/experiments/2026-10-11-local-summarization/data/provenance.json` | [docs/history/experiments/2026-10-11-local-summarization/data/provenance.json](../../docs/history/experiments/2026-10-11-local-summarization/data/provenance.json) |
| `docs/experiments/2026-10-11-local-summarization/data/quality-checkpoint.json` | [docs/history/experiments/2026-10-11-local-summarization/data/quality-checkpoint.json](../../docs/history/experiments/2026-10-11-local-summarization/data/quality-checkpoint.json) |
| `docs/experiments/2026-10-11-local-summarization/data/settings.json` | [docs/history/experiments/2026-10-11-local-summarization/data/settings.json](../../docs/history/experiments/2026-10-11-local-summarization/data/settings.json) |
| `docs/experiments/2026-10-11-local-summarization/data/stages.csv` | [docs/history/experiments/2026-10-11-local-summarization/data/stages.csv](../../docs/history/experiments/2026-10-11-local-summarization/data/stages.csv) |
| `docs/experiments/2026-10-11-local-summarization/data/synthetic-examples.json` | [docs/history/experiments/2026-10-11-local-summarization/data/synthetic-examples.json](../../docs/history/experiments/2026-10-11-local-summarization/data/synthetic-examples.json) |
| `docs/experiments/2026-10-11-local-summarization/data/trials.csv` | [docs/history/experiments/2026-10-11-local-summarization/data/trials.csv](../../docs/history/experiments/2026-10-11-local-summarization/data/trials.csv) |

All listed original files were physically moved. Markdown changes only repair
links or staging-path references. Numeric CSV/JSON data remains unchanged.

## Inspection and coordination

Inspected both current GitHub main trees, all open PR file lists, desktop PR #8's
documentation renames and Windows runtime changes, desktop PR #9's proposal,
and website PR #13's proposal. This branch touches none of their changed paths.
It does not incorporate or rewrite those PRs.

Both owner checkouts contain substantial uncommitted native/Windows/API or browser
work. They were inspected read-only and left untouched; this work uses isolated
copies of the exact GitHub commits above. All eight cached local instruction
hashes matched their source files. GitHub main instructions were also inspected.
The shared board could not run: bundled Windows Python lacks Unix `fcntl`, the
Python Store alias is unusable, and no usable WSL installation was found. No board
state or file claims were fabricated. The configured parent `../AGENTS.md` is absent.

## Dependency checks and preserved boundaries

Searched tracked documentation, scripts, tests and configuration for old paths
before moving. No runtime or deployment consumer uses the relocated paths.
Application code, dependency manifests/locks, build/release scripts, CI configuration,
Supabase migrations/APIs, Cloudflare settings, generated public output, update feeds,
signed artifacts, download routes, branding and fonts are unchanged.

## Verification performed for this cleanup

- Repository-local Markdown path and heading-anchor scan against the base commit:
  241 local links checked, zero broken paths/anchors (including baseline).
- All relocated files exist at their new paths; relocated numeric data matches
  its original Git contents. Reviewed the rename/content diff and whitespace checks.
- No application/runtime/configuration/release changes in the staged diff.
- Offline model-preparation fixtures: 10 tests passed.
- Offline public-record exporter fixtures: 2 tests passed.
- Full model-evaluation discovery cannot import two modules on Windows because
  their unchanged runner imports Unix `fcntl`; this is not a passing full suite.
  Initial sandbox temp/hard-link failures were resolved using workspace temp and
  an unsandboxed run of the preparation fixtures. No inference/download occurred.

## Compatibility and deferred moves

Two small new pointers replace the original `README.md` and `RESULTS.md` at
`docs/experiments/2026-10-11-local-summarization/`. Their full original contents
now live under `docs/history/experiments/`. Existing `docs/testing.md` and PR #8's
proposed `docs/project/testing.md` deliberately keep working through these pointers;
the latter PR also adds an experiment navigation home. Other existing inbound
references were updated to the canonical history paths. No duplicate dataset stays
at the old path. Direct old links to individual data files must use this manifest.

PR #8 owns the broad `docs/{project,windows,reviews,schedules,design,releases}`
reorganization and packaging-path update; PR #9 owns the architecture proposal.
Defer those moves to their existing PRs. `docs/verification/` remains because
benchmark tools recursively inventory that directory or read/write exact paths.
Benchmark code, fixtures, private logs, native apps, Electron v3, schedule service,
release assets and historical browser pointers remain in place. No Swift build,
Mac app relaunch, native packaging, Windows build, or live-service test was needed
for this record relocation; no compatibility claim is made for untested platforms.
