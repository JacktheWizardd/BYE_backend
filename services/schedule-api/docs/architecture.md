# Architecture and ownership

The API is an independently deployed service with a stable `/v1` contract.
An app UI update needs no API deployment; a compatible backend fix needs no app
rebuild. Windows, Mac and website clients will use the same contract when their
integration phases are implemented.

## Data flow

```text
PCC published terms + Fall schedule feed
                 |
       private synchronization worker
        validate -> stage -> publish
                 |
       Supabase private schedule data
                 |
        public BYE read API (/v1)
                 |
       future app / website clients
```

Public reads do not wait for PCC. One-minute server ticks decide whether a source
check is due; the global deadline prevents more than one semester fetch per five
minutes. There is one demand lease for the term, not a separate PCC poller for
each student. Source failures retain the last validated snapshot.

## Package boundaries

| Location | Owns |
| --- | --- |
| `src/api.ts` | Registry-gated reads, bounded routes, errors, ETags and CORS |
| `src/contract.ts` / `openapi.json` | Versioned machine-readable contract |
| `src/domain.ts` | Complete course identity, normalization, validation and hashes |
| `src/sync.ts` | Private worker, publication workflow and deadline cleanup |
| `src/database.ts` | Server RPC access and bounded streaming source reads |
| `src/admin.ts` | Owner-authenticated key management; random key generation and one-time display |
| `dashboard/public/` | Shared owner interface and in-page lifecycle forms |
| `dashboard/hosted/` | Separate Cloudflare Worker, session routing and bounded quotas |
| `dashboard/server.ts` | Optional loopback-only development server |
| `scripts/` | Deployment, owner commands, saved-feed benchmark and hosted checks |
| `tests/` | Synthetic fixtures and offline regression/database tests |
| `supabase/migrations/` | Ordered additive schema, scheduler and integrity changes |

The native Swift module named `BYEAPI` is the existing RMP client. It is a
different component from this hosted schedule service.

## Database boundaries

- `pcc_schedule`: original private Fall pilot, preserved in place. The bootstrap
  action reads its verified source data once; the dedicated importer remains available.
- `bye_schedule`: backend read model, current/previous catalogs, section
  definitions, availability rollback evidence, staging, activity and bounded logs;
  also private owner approvals, key digests, audit events and retry receipts.
- Existing public student-review tables: unchanged. This service neither imports
  RMP reviews nor changes review IDs, submissions, moderation or profile choices.

Ordinary callers cannot read private source rows or invoke the machine gateway.
The public handler exposes only curated read operations. Owner/cron credentials
stay on the server, and the cron credential is stored in Supabase Vault.

## Versions and fidelity

Catalog and availability versions are independent. Seat-only changes update the
changed availability records without producing another full catalog snapshot.
An unchanged source check refreshes successful-check time without adding a data
generation. Retention keeps current/previous catalogs and one availability
rollback delta; it does not accumulate a full history every minute.

Official codes preserve zeros, CCN prefixes and complete suffixes. Each section
has distinct meetings and section-scoped instructor assignments. Source HTML is
data, not executable markup. Missing counts stay unknown, and PCC's registration
status is independent of available seats. The operations guide defines exact
freshness and rollback behavior; the OpenAPI document defines response shapes.

Future v1 changes must be additive. Breaking changes belong in v2 while v1
remains supported for installed clients.

## Owner access and key authorization

The hosted owner path is:

```text
Approved BYE account → Cloudflare dashboard/session server
                    → Supabase owner management function
                    → private owner/key registry
```

Cloudflare hosts a separate `bye-admin` Worker, not a route in the public website.
It uses only public Supabase Auth configuration. Login access tokens remain in a
bounded server-memory map; the browser receives a secure opaque session cookie.
The singleton Durable Object keeps sessions routed consistently and persists only
three aggregate rate-limit counters. Restarts can require another sign-in. They
do not change the registry in Supabase. `dashboard/server.ts` provides optional
local development and is not part of the hosted service's availability.

The management Edge Function validates the signed-in user and passes that user's
JWT to narrowly exposed database functions. Those functions independently check
`auth.uid()` against the explicit owner table. There is no public self-approval.
Cloudflare does not receive a database, service-role or cron credential.

Schedule keys identify shared clients rather than students. The read handler
sends a key digest into the database read operation. That operation validates
status and retirement before returning schedule data or allowing a 304 response;
there is no positive authorization cache or compiled-key fallback. Rate limits
remain shared by network identity, so extra keys cannot multiply that allowance.

The key registry and the schedule API are already deployed. Client consumption
and delivery of replacement keys to installed apps remain future integration
work. Read the [handoff](records/handoff.md) for the practical boundaries and the
[key guide](api-keys.md) for lifecycle rules.
