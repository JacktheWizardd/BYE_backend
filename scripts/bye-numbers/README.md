# BYE number database rehearsal

From this directory, install once with `npm ci --no-audit --no-fund`, then run
`npm test`. Node 22; pinned embedded-postgres 17.10.0-beta.17 (PostgreSQL 17.10)
and pg 8.23.1. The lockfile records transitive dependencies. No Homebrew, Docker,
global database service, Supabase credential or production connection is used.

Installation needs package-registry access. Tests run offline, with loopback-only
PostgreSQL, a random local password, a temporary cluster, and independent clients.
A sandbox must permit loopback listeners and subprocess execution. The runner
stops its server and removes its own temporary cluster in finally. It never
accepts an external database URL. Fictional addresses exist only as test data.

The runner loads the actual 007 and 006 files, with minimal Auth/schema/role stubs
matching 002. It executes the commented owner block from 007 so that the tested
operator SQL cannot drift from the documented version. It verifies permissions,
sequence behavior, owner assignment, explicit same-user lock contention,
different-user concurrency, repeat installation, schema drift, and deletion.
See `../../supabase/007_bye_numbers_checks.sql` for manual disposable checks.

This is PostgreSQL verification, not a complete Supabase emulator: hosted Auth,
PostgREST schema exposure, deployed event triggers, delivery, and native end-to-end
acceptance remain separately approved production checks. `RESTRICT` is deliberate;
future private identity cutover must migrate the number FK and claim authentication
before deleting Auth accounts. Never infer migration compatibility from UUIDs alone.
