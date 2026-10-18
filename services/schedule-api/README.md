# BYE schedule API

Independent backend for PCC schedules and availability. It has its own package,
tests, deployment, and versioned contract. Windows, Mac, and website integration
remain separate future work. Fall 2026 (`202670`) is the current pilot.

**Start here: [API documentation folder](docs/README.md).**

| Document | Purpose |
| --- | --- |
| [Architecture](docs/architecture.md) | Service boundaries, data flow, versions and private storage |
| [Setup and operations](docs/guide.md) | Endpoints, local commands, deployment, synchronization and rollback |
| [API keys](docs/api-keys.md) | Current key setup, server credentials and rotation limitations |
| [Verification](docs/verification.md) | Recorded tests, hosted evidence and remaining limitations |
| [Roadmap](docs/roadmap.md) | Implemented features versus queued work |
| [Commit guide](docs/commit-guide.md) | Change groups, checks, and ready-to-paste commit text |
| [OpenAPI contract](openapi.json) | Machine-readable v1 interface, kept beside the package |

Base URL: `https://nahvhampsxtasfwvvfei.supabase.co/functions/v1/bye-schedule-api`.
Requests require the configured publishable key in the `apikey` header.

From this directory, run `npm ci`, `npm test`, `npm run test:db`, and
`npm run check`. Tests use fixtures; hosted checks and deployment are explicit
separate commands. See the operations guide before running owner actions.

Backend source lives in `src/`, tooling in `scripts/`, fixtures/tests in `tests/`,
and ordered additive migrations in `supabase/migrations/`. Generated dependencies,
deployment output and local credentials are ignored by Git.
