# Schedule API setup and operations

Standalone backend, released independently of Windows, Mac and the website.
No client source or review/RMP integration is included. Fall 2026 (`202670`) is
the only supported term. Existing clients still use their existing sources.

Base URL:
`https://nahvhampsxtasfwvvfei.supabase.co/functions/v1/bye-schedule-api`

## Read contract

The complete OpenAPI 3.1 specification is [openapi.json](../openapi.json), also served
at `/v1/openapi.json`. Every read requires `apikey: <BYE client key>`. Generate
shared application keys using the [local owner dashboard](owner-dashboard.md).
The existing key remains registered for compatibility. A BYE key is public app
identification; it is not a student identity or database write credential. The
genuine Supabase publishable key is used separately for owner sign-in.

```js
const response = await fetch(`${base}/v1/terms/202670/courses?q=math5a`, {
  headers: { apikey: clientKey }
});
const { data, meta } = await response.json();
```

- `/v1/terms` lists imported terms, never a feed's default semester.
- `/v1/terms/202670/manifest` is a small version/freshness response.
- `/catalog` returns compact course definitions suitable for local suggestions.
- `/courses?q=…` returns up to 20 matches, with exact normalized codes first.
- `/courses/{courseKey}/sections` returns sections and structured meetings.
  URL-encode the complete key, e.g. `MATH%20005A`.
- `/availability?crns=71655,80206` returns up to 100 unique five-digit CRNs.

Successful responses use `{data, meta}`. Errors use
`{error:{code,message,retryable}}`: 400 invalid query, 401 missing/invalid client
key, 404 missing course/CRN/unsupported term, 429 rate limit, 503 unavailable.
429 includes `Retry-After: 60`. Limits are 120 reads per minute per server-hashed
network address, with at most 2,000 active rate buckets; shared networks share a
limit. This is abuse mitigation, not authentication. No raw addresses are stored.

Catalog/search/sections/availability support `ETag` and `If-None-Match`. A 304 has
no body; retain the cached representation. Catalog metadata excludes availability
freshness, so seat checks cannot invalidate catalog ETags. The manifest is small
and always revalidated. The service has no unbounded process cache.

Status is PCC's raw code, never calculated from counts. Unknown values are null;
`R`, `X`, and unfamiliar codes have no inferred meaning. A closed section can
still show seats. Instructor assignments remain section-scoped and contain no
email field. Source HTML is inert data: display as text, or sanitize it before
rendering. Do not inject it directly into a page.

Availability becomes stale after 15 minutes without a successful source check.
Stale section/count responses contain `availability: null`, with timestamps and
`stale: true`. The five-minute collection target cannot establish PCC's own
upstream update frequency or guarantee enrollment.

## Independent development and deployment

Run commands from `services/schedule-api/`. Requires Node 24.3+, npm and the pinned tools installed by `npm ci`.

```sh
npm ci
npm test
npm run test:db
npm run check
npm run benchmark -- /absolute/path/to/saved/source.json
```

Unit and PostgreSQL tests use this package's synthetic fixtures and no network.
The optional full-feed benchmark uses a saved PCC file; it does not fetch PCC.
The pilot default path points to the existing ignored local capture.

`supabase/migrations` contains the ordered, additive backend migrations. Apply
each once as the database owner, recording it through Supabase's migration tool.
The hosted project already has these migrations applied. Do not replay initial
CREATE statements or push the desktop repository's unrelated migrations.
Bootstrap needs the existing private pilot; a fresh installation can instead
initialize through a controlled `run` against the requested published term.

For repeat function deployments, authenticate the CLI (`npx supabase login`),
set `BYE_PROJECT_REF`, `BYE_PUBLISHABLE_KEY`, and `BYE_JOB_TOKEN_SHA256`, then:

```sh
npm run deploy
```

This builds only the three backend functions (read, sync, owner management). It does not build or publish an app,
website, or database migration. The deployment injects the public Auth key and private job-token
**digest**; server credentials are read from Edge Function environment
variables. JWT gateway checks are off because each handler verifies its own
registry key, owner Auth token, or private machine credential. Handler checks remain mandatory.

The job-token digest can be obtained without revealing the token:

```sql
select encode(extensions.digest(decrypted_secret,'sha256'),'hex')
from vault.decrypted_secrets where name='bye_schedule_cron';
```

Use a stable base URL and `/v1` contract in future clients. Additive backend
changes need no client release. UI fixes need no backend deployment. Breaking
contract changes require `/v2` alongside `/v1`; never silently remove v1 fields.
The API accepts registered BYE application keys and checks their status in the
database. Creating or changing a key through the hosted owner dashboard requires
no read-API redeployment. Rotation creates an active replacement while the old key
has a thirty-day transition period. Delivery to installed clients remains future
work. See the [key guide](api-keys.md) and [handoff](records/handoff.md) before
changing a key used by shipped clients.

## Source synchronization and storage

Supabase Cron ticks every minute. The worker checks metadata and the whole
Fall feed daily on the first tick at/after 10:00 UTC. Public reads renew a single
10-minute demand lease at most once per five minutes; other ticks fetch the
semester only while demand exists. Without demand only the daily fetch remains.
The shared five-minute minimum plus scheduler timing gives an expected active
collection interval of five to six minutes. Cheap ticks do not fetch PCC when
the deadline has not elapsed.

All entry points share a 140-second lock and a next-fetch deadline. No more than
one semester fetch begins per five minutes, including owner runs and retries.
Public reads return stored data and never await PCC. No speculative seat-only
endpoint, per-user PCC polling, or unverified conditional request behavior is used.

The worker bounds source bodies to 32 MiB, metadata to 1 MiB, rows to 25,000,
network requests to 40 seconds, and staging batches to 100 records with an
approximately 1 MiB target and 2 MiB hard database limit. It releases response byte views as they are decoded and
hashed. Source redirects are rejected. Complete validation precedes atomic
publication. Conflicting CRNs/counts/dates or an interrupted job leave active data
unchanged. Two delayed retries precede a 30-minute failure cooldown;
`Retry-After` can extend it, capped at 24 hours.

Catalog identity hashes every original field except the seven availability
fields, independently of row order. New/unknown fields therefore remain source
evidence and invalidate catalog identity when changed. Duplicate original rows
are retained. Only catalog changes stage all original JSON rows. Seat-only checks
stage changed sections and their exact source evidence; unchanged availability
records are not rewritten.

Storage is bounded to current/previous catalogs, current availability plus one
rollback delta, seven days/2,500 synchronization events, expired staging cleanup
after 30 minutes, two minutes of rate buckets and seven days of this cron job's
execution history (also capped at 2,500 completed runs). PostgreSQL reuses freed space; physical database size need not
shrink immediately after cleanup. The original pilot and student reviews remain
untouched.

## Owner operations and rollback

Set `BYE_JOB_TOKEN` from the server-only `bye_schedule_cron` Vault secret, or set
`BYE_SERVER_KEY` in a server-side shell. Do not store these in a client or Git.

```sh
npm run owner -- state
npm run owner -- run
npm run owner -- cleanup
npm run owner -- disable
npm run owner -- rollback
npm run owner -- rollback-catalog
npm run owner -- enable
```

`run` shares the source cooldown; it cannot bypass the request budget. `bootstrap`
is a one-time option that initializes from the already verified pilot without a
PCC request. `rollback` swaps the last availability generation; `rollback-catalog`
swaps the last catalog. These are separate because they have independent
versions. Both disable automatic fetching and mark availability stale. Inspect
the result, perform a successful owner `run`, then re-enable fetching.

Cron's machine token lives in Vault; no plaintext credential occurs in the job
definition. For a complete scheduler stop/start as owner:

```sql
select cron.alter_job((select jobid from cron.job
  where jobname='bye-schedule-sync'), active:=false); -- true to start
```

A normal `disable` keeps cheap scheduler ticks but prevents scheduled PCC reads.

## Later client integration

On launch, use the bounded cached catalog immediately and check the manifest in
the background. Refresh reads BYE's API, not PCC. Use one 60-second scheduler per
visible client, one request in flight, finite timeouts, cancellation on query or
semester changes, and backoff on errors. Pause when hidden/minimized/offline;
resume with one check. Fetch only changed catalog data and currently viewed CRNs.
Replace bounded cache entries rather than appending snapshots. Update seats
without resetting reviews, filters, or professor choices. Show source timestamps
and suppress expired counts. These client changes are not part of this release.

Verification evidence and known limits: [verification.md](verification.md).
