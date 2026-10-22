# Owner and developer handoff

**Last updated:** October 19, 2026, Pacific time.

This page is the starting point for someone taking over BYE's schedule backend
or online key manager. The [delivery record](2026-10-19-delivery.md) explains the
history and reasoning; linked guides hold the implementation details.

## Understand the current boundary first

The standalone schedule API and online key manager are deployed. App integration
is still pending. Do not assume that publishing a new key updates installed apps,
or that the public BYE website already reads from this API.

The supported schedule term is Fall 2026 (`202670`). Existing student reviews,
professor choices and RMP behavior remain separate.

## Where the owner goes

Open **https://bye-admin.jack-truong2k1.workers.dev** and sign in with an approved
BYE account using its email code. This means a user under Supabase Authentication,
not the account used to log into the Supabase, Cloudflare or GitHub consoles.

Owner access is granted explicitly through the private bootstrap command. Signing
up for an ordinary BYE account does not grant administration. If access is lost,
follow [owner bootstrap and recovery](../owner-dashboard.md); never solve it by
making a public key administrative or disabling owner checks.

The hosted site is the normal management address. `npm run admin` is an optional
local development tool; it is not needed for the hosted site. Login sessions last
at most an hour and can end after a Cloudflare restart or deployment. Signing in
again restores access to the same persistent registry and audit records.

## Handle a key change carefully

Use descriptive labels such as “Windows production” or “Website preview”. Save a
new key when it appears; the dashboard cannot recover its plaintext later.

For a planned replacement: rotate the intended key, save the replacement, deliver
it to the appropriate clients, verify their use, and only then allow the old key
to retire. The thirty-day overlap buys time; it is not a delivery mechanism.
Extend retirement if the transition needs longer. Permanently revoke only the key
that should stop working, checking the name, mask and ID in the confirmation form.

If creation reports an uncertain result, use Retry uncertain request rather than
clicking Create repeatedly. Retries use the same request ID for up to twenty-four
hours. If the page was closed, the retry window expired, or plaintext was lost,
inspect the list and audit history before revoking an unrecoverable key and
intentionally creating another.

BYE schedule keys, Supabase public sign-in keys, and private machine credentials
serve different purposes. Revoking a BYE key must not revoke a Supabase project key.
Never paste keys, login codes or private credentials into records, commits or issues.
See the [key guide](../api-keys.md) for the full lifecycle.

## Where developers work

All schedule service and admin code belongs to `services/schedule-api/` in the app
repository. It owns its dependencies and does not import app or public-site code.
The public BYE website lives in a different repository.

| Area | Main source | Consult before changing |
| --- | --- | --- |
| Schedule endpoints and response compatibility | `src/api.ts`, `src/contract.ts`, `openapi.json` | [Architecture](../architecture.md), [operations](../guide.md) |
| PCC parsing and safe publication | `src/domain.ts`, `src/sync.ts`, `supabase/migrations/` | [PCC pilot](../../../../docs/schedules/pcc-schedule-pilot.md), [verification](../verification.md) |
| Key authorization and lifecycle | `src/admin.ts`, registry migration | [Key guide](../api-keys.md), [owner guide](../owner-dashboard.md) |
| Dashboard forms | `dashboard/public/` | [Owner guide](../owner-dashboard.md) |
| Hosted sign-in and session routing | `dashboard/hosted/` | [Cloudflare guide](../hosted-owner-dashboard.md) |
| Optional localhost server | `dashboard/server.ts` | [Local owner workflow](../owner-dashboard.md) |

Changes to the read API must preserve v1 response compatibility. Seat-only changes
should not invalidate the catalog. Never substitute semesters, infer PCC status
from counts, or merge official suffixes because their names look similar.

For authentication changes, preserve owner checks in the API and database, secure
opaque cookies, server-memory login tokens, and confirmation of destructive actions.
The Cloudflare object stores only three aggregate rate-limit counters on disk;
it does not store login tokens or a separate copy of the key registry.

## Test and release the right component

From `services/schedule-api/`, install with `npm ci`. Routine backend checks are
`npm test`, `npm run test:db` and `npm run check`. For hosted-portal changes also run
`npm run test:admin:runtime`; it builds and exercises the actual Cloudflare runtime
with mocked upstream responses. Automated tests must not email real users or
request PCC/RMP data. Hosted probes and source synchronization are explicit operations.

| Change | Release path | Important consequence |
| --- | --- | --- |
| Shared key status or retirement | Owner dashboard | Applies through the registry; no code deployment needed |
| Hosted dashboard/session code | `npm run admin:deploy` | Deploys only `bye-admin`; owners may need to sign in again |
| Supabase API/management/worker code | `npm run deploy` with documented configuration | Separate Edge Functions release; preserve the worker's existing verification digest |
| Database structure or functions | Reviewed additive migration | Apply once through the proper migration workflow; preserve existing reviews |
| Client behavior or key delivery | Future client integration/release | Backend deployment alone does not change installed apps |

Review the [Cloudflare guide](../hosted-owner-dashboard.md) before deployment.
Keep its worker name, exact allowed origin and Durable Object history consistent.
No paid upgrade has been authorized. Free limits may reject requests; do not
change plans automatically to get a deployment or load test through.

Git source control is separate from deployment. Review the actual diff, exclude
local credentials and generated output, and give the owner a ready-to-paste
Summary and Description. Do not imply a commit or push happened unless it did.

## When something goes wrong

| Symptom | First thing to check |
| --- | --- |
| Dashboard asks for sign-in again | Session expiry or a Cloudflare restart; sign in again rather than creating a new account |
| Owner sign-in is denied | Correct BYE account and explicit owner approval; do not relax access checks |
| Email code does not arrive | Address, delivery settings and rate-limit window; repeated sends can make this worse |
| A schedule key receives 401 | Key status and retirement date, even if the client has cached data |
| A change reports conflict | Refresh the key list; another action may have changed its revision |
| Seat values are missing | Check freshness; suppressing stale availability is expected behavior |
| Schedule synchronization fails | Preserve the last successful data and inspect worker state/backoff using the operations guide |
| Dashboard is unavailable | Check the separate Cloudflare service; the Supabase read API may still work independently |

For a bad code deployment, restore a tested compatible version. Do not restore the
old compiled-key fallback: it could let revoked keys bypass the registry. Schedule
snapshot rollback and owner-account recovery are separate procedures in the
[operations](../guide.md) and [owner](../owner-dashboard.md) guides.

## Next phase

Start with an explicitly scoped Windows integration. Configure the API and a shared
Windows key, then verify suggestions, structured sections, source freshness,
Refresh, visible-client polling, cancellation and bounded caches. Preserve review
and professor-choice behavior. Define replacement-key delivery before promising
that installed clients can complete a rotation automatically. Mac and website
integration remain separately scoped releases.
