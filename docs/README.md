# Engineering documentation

Use the standalone API folder for the newly deployed schedule backend. Native
and Windows clients still use their existing integrations; backend deployment
does not mean the clients have been connected.

## PCC database and standalone API

| Guide | Purpose |
| --- | --- |
| [API delivery record](../services/schedule-api/docs/records/2026-10-19-delivery.md) | Owner/developer account of what was built, why, and what remains |
| [API handoff](../services/schedule-api/docs/records/handoff.md) | Start here to operate the service or take over development |
| [Standalone API documentation](../services/schedule-api/docs/README.md) | Main index: architecture, setup, keys, operations, verification and roadmap |
| [PCC Fall 2026 database pilot](pcc-schedule-pilot.md) | Original private schema, importer and first published snapshot |
| [API commit preparation](../services/schedule-api/docs/commit-guide.md) | Pending change groups, checks and ready-to-paste Summary/Description |
| [API and external integrations](api.md) | Distinguish the hosted schedule service, direct client integrations and RMP module |

## Cross-platform architecture decision (proposed)

- [Cross-platform consolidation and repository options](cross-platform-migration-proposal.md) — why Windows/macOS UI drift matters, the Tauri/Electron/Capacitor alternatives, shared-code plan, benchmarks, safety gates, and the open repository-layout decision.
- [UI parity map](UI_PARITY.md) — what currently differs among web, Windows, and native Mac, before any migration.

The proposal does **not** assert that Tauri, Capacitor, a new monorepo, or new AI features have been implemented. The existing apps and release channels remain unchanged.

## Application development

- [Project status and handoff](PROJECT_STATUS.md)
- [Architecture](architecture.md)
- [Development setup](development.md)
- [Testing](testing.md)
- [Windows app guide](../apps/cross-platform/README.md)
- [Windows verification](../apps/cross-platform/VERIFICATION.md)

## Student reviews

- [Database overview](database.md)
- [Review database explained](review-database-explained.md)
- [Supabase decisions and history](supabase-plan.md)
- [Review launch record](review-launch-record.md)
- [Website redesign record](website-redesign-record.md)

## Releases and historical records

- [Mac release procedure](RELEASING.md)
- [Prepared prerelease notes](GITHUB_PRERELEASE.md)
- [Implementation history](IMPLEMENTATION_HISTORY.md)
- [Repository overview](../README.md)

Older dated entries describe the state at the time they were written. For the
schedule API's delivered behavior, use its dedicated docs and verification
report. Public website source and its own documentation live in the separate
`BYE_website` repository.
