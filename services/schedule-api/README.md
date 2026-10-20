# BYE schedule API and owner dashboard

An independent backend for PCC schedules, seat availability and shared application
keys. The hosted owner dashboard is available without a local development server.
Windows, Mac and public website integration remain separate future work.

**Start here:** [delivery record](docs/records/2026-10-19-delivery.md) and
[owner/developer handoff](docs/records/handoff.md).

- **Owner dashboard:** https://bye-admin.jack-truong2k1.workers.dev
- **Schedule API:** `https://nahvhampsxtasfwvvfei.supabase.co/functions/v1/bye-schedule-api`
- **Supported term:** Fall 2026 (`202670`).

The dashboard uses an explicitly approved BYE account and email code. Schedule
reads use a registered BYE application key in the `apikey` header. That key is
separate from Supabase's public key used for owner sign-in. The apps have not yet
been connected to this service, and installed clients do not automatically receive
replacement keys.

## Find the right guide

| Guide | Purpose |
| --- | --- |
| [Documentation index](docs/README.md) | Complete reading map and accepted state |
| [Project records](docs/records/README.md) | Delivery history, decisions and handoff |
| [Architecture](docs/architecture.md) | Service boundaries, data flow and private storage |
| [API operations](docs/guide.md) | Endpoints, synchronization, deployment and rollback |
| [API keys](docs/api-keys.md) | Shared application keys, lifecycle and credential separation |
| [Hosted dashboard](docs/hosted-owner-dashboard.md) | Cloudflare deployment and security |
| [Owner access/local development](docs/owner-dashboard.md) | Bootstrap, recovery and the optional localhost server |
| [Verification](docs/verification.md) | Dated test evidence and limitations |
| [Roadmap](docs/roadmap.md) | Delivered work versus queued client integration |
| [Commit handoff](docs/commit-guide.md) | Pending change group and ready-to-paste text |
| [OpenAPI contract](openapi.json) | Machine-readable v1 interface |

## Development

Run from this directory: `npm ci`, `npm test`, `npm run test:db`, `npm run check`.
For hosted portal changes also run `npm run test:admin:runtime`. Automated tests
use fixtures; deployment, live probes and owner operations are explicit separate
commands. Consult the relevant guide before running them.

`src/` owns the Supabase service, `dashboard/` owns the shared interface and local/
hosted servers, `scripts/` owns tooling, and `supabase/migrations/` owns additive
database changes. This package owns its dependencies and does not import app or
public-site implementation code. Credentials, dependencies, local state and
build output stay out of Git.
