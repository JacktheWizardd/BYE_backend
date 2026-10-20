# BYE — Before You Enroll

> **Internal developer documentation.** This source repository is private and is not the public BYE download or product website.

BYE is a student-focused course-planning application, currently centered on Pasadena City College (PCC). The implemented experience helps students find course sections, compare professor information, and read original reviews. Broader transfer-plan evaluation is a longer-term product goal, **not an implemented feature**.

## Documents

[Open the documentation home](docs/README.md) for area folders explaining what we built, why we chose it, how it works, and what remains.

[Project](docs/project/README.md) · [Windows](docs/windows/README.md) · [Reviews](docs/reviews/README.md) · [Schedules and API](docs/schedules/README.md) · [Design](docs/design/README.md) · [Releases](docs/releases/README.md) · [AI experiments](docs/experiments/README.md)

## Current status

- **Native macOS application:** Swift/SwiftUI, Swift Package Manager, Apple Silicon, macOS 14+. The version declared in `scripts/beta-version.sh` is **0.4.0-beta.1 (build 8)**. Local preparation, verification, and publication are separate steps.
- **Separate Windows-oriented prototype:** Electron, React, and TypeScript in `apps/cross-platform/`. Its own package version is **0.4.0-beta.1**, matching the Mac 0.4.0-beta.1 design and features; it is a separate app, not the native Mac app.
- **Implemented:** PCC course/section search, schedule filters, professor profile selection, RMP ratings and original review retrieval, sorting, local caches, and failure/retry handling.
- **Temporarily disabled:** AI-generated review summaries in the current prepared Mac beta and the separate Windows beta. Existing experimental code and records remain in the repository.
- **Review database:** Supabase schema, PCC professor/course lists, restricted submissions, reporting, and automatic hiding are live and tested. The website owns student sign-in and submission; Windows now reads public BYE feedback independently from RMP. Native Mac integration remains pending.
- **Standalone schedule backend deployed:** Private Fall 2026 PCC data and an independent Supabase API with shared availability synchronization. Windows API integration is implemented locally, including BYE reviews and freshness-aware availability. Mac and website schedule-API integration remain pending; no new app release is claimed. See the [API documentation](services/schedule-api/docs/README.md).
- **Longer-term proposal:** Educational-plan/transfer requirement evaluation.

For an up-to-date engineering handoff and verified-versus-unverified behavior, read [Project Status](docs/project/PROJECT_STATUS.md). Do not treat this README as a release announcement.

## Quick start

### Native macOS

Requires a Mac with a compatible Xcode installation and macOS SDK. Run from the repository root:

~~~sh
./scripts/swift.sh build
./scripts/swift.sh test
./scripts/build-test-app.sh
~~~

The last command creates the locally generated `test/BYE Test.app` for interactive review; it is ignored by Git. See [Development Setup](docs/project/development.md) for details. Packaging and publication are **not** part of this quick-start workflow.

### Windows-oriented Electron application

On Windows x64, install Node 24 LTS (or Node 22.16+), npm, and development prerequisites. Then:

~~~powershell
cd apps/cross-platform
npm ci
npm run runtime:fetch
npm run dev
~~~

See the [cross-platform README](apps/cross-platform/README.md) before building or testing that application.

## Repository map

| Location | Responsibility |
| --- | --- |
| `Sources/Classwise/` | Native Mac app, UI, workflows, and local state |
| `Sources/ClasswiseCore/` | Shared Swift course/schedule domain logic |
| `Sources/BYEAPI/` | Typed native RMP client and transport |
| `Tests/` | Swift unit and integration tests |
| `apps/cross-platform/` | Separate Electron/React/TypeScript app, scripts, and tests |
| `services/schedule-api/` | Independent schedule API, synchronization worker, contract, migrations, tests and docs |
| `scripts/` | Mac build, verification, packaging, and update tooling |
| `test/` | Local Mac test-app entry point; generated app is not committed |
| `benchmarks/` | Performance and summarization evaluation fixtures/tooling |
| `docs/` | Engineering guides, decisions, experiments, release and verification records |

## Developer guides

- [Documentation index](docs/README.md) — project guides and the standalone API documentation folder.
- [Standalone schedule API](services/schedule-api/docs/README.md) — architecture, keys, setup, deployment, verification and commit preparation.

- [Architecture](docs/project/architecture.md) — application boundaries, data flow, storage, and external services.
- [Development](docs/project/development.md) — setup, local workflow, branches, and configuration hygiene.
- [Database overview](docs/reviews/database.md) — review and schedule data boundaries, with the original database proposal preserved as history.
- [Review database explained](docs/reviews/review-database-explained.md) — a plain-language guide to student verification, reviews, privacy, reporting, and completed tests.
- [Supabase status and plan](docs/reviews/supabase-plan.md) — SQL migrations, implementation decisions, verification results, and remaining work.
- [Review launch record](docs/reviews/review-launch-record.md) — how student reviews went live: the review page, the Mac button, email-code delivery (Brevo), website hosting fix, and troubleshooting.
- [API and integrations](docs/schedules/api.md) — direct client integrations and the independently deployed schedule API.
- [Testing](docs/project/testing.md) — commands, offline versus live checks, and evidence requirements.

Existing reference material:

- [Project status and handoff](docs/project/PROJECT_STATUS.md)
- [Implementation history](docs/project/IMPLEMENTATION_HISTORY.md)
- [Mac release and update procedure](docs/releases/RELEASING.md)
- [Prepared release notes](docs/releases/GITHUB_PRERELEASE.md)
- [Windows development/verification](apps/cross-platform/README.md)
- [RMP client design](Sources/BYEAPI/README.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

## Contribution and change workflow

1. Branch from the current `main` for a single change or coherent workstream.
2. Make focused changes, keeping new or unfinished features clearly marked as experimental.
3. Run the relevant checks in [Testing](docs/project/testing.md), and record what was **not** tested.
4. Open a pull request and review the diff before merging into `main`.
5. Update the relevant docs when behavior, dependencies, data handling, or release steps change.

Do not commit credentials, student-submitted content, raw personal data, model weights, build products, or local machine-specific logs. Verify the Git diff even when a path is ignored. A private repository is **not** a substitute for secret management or access controls.

## Scope and distribution

This repository serves authorized BYE developers and collaborators. Product marketing, end-user installation, feedback collection, and public downloads belong on the separate BYE website/distribution channel. The Mac update feed and release artifacts are handled as documented in [Releasing](docs/releases/RELEASING.md).

BYE is an independent project and is not affiliated with PCC or Rate My Professors. Class, professor, and transfer information should be verified against authoritative sources; RMP uses an undocumented endpoint and can change. Do not infer permission to republish third-party data from its technical accessibility.
