# API and external integrations

This document distinguishes **current direct integrations** from a **proposed BYE-hosted schedule API**. For client internals, see [Architecture](architecture.md); for the related cache proposal, see [Database plans](database.md).

## Current: PCC schedule data

The native Mac app fetches PCC schedule/catalog data directly, then resolves courses and sections using local Swift parsing/domain logic. Matching includes official course labels and common user shorthand. The Windows/Electron implementation has its own PCC client/cache path.

Important properties:

- The selected term and authoritative course/section identity matter.
- Network failures, cancellation, and changes to upstream schemas must be handled.
- Date/time and delivery formats must be interpreted carefully for weekday filtering.
- School data can change; retrieved information is not an enrollment guarantee.

The project does **not** currently expose its own hosted PCC API to clients.

## Current: Rate My Professors

The native `Sources/BYEAPI/` Swift module communicates with an undocumented RMP GraphQL endpoint. It is **not** a standalone hosted BYE API.

The documented transport uses bounded concurrency, request spacing, retries and timeouts; identity checks protect against accidentally combining similarly named professors. Students explicitly resolve ambiguous profiles. The app preserves original source context and differentiates professor-wide ratings from course-specific review coverage.

Consult [BYEAPI's module README](../Sources/BYEAPI/README.md) for details. Because this integration is unofficial, it may break or become unavailable and requires continued review of permitted usage. Do not assume an accessible endpoint grants redistribution rights.

## Current: Mac app updates

Distribution builds use a Sparkle appcast and signed update archives hosted on the separate BYE Cloudflare Pages website. This is a **release delivery service**, not a course-schedule API. Follow [Releasing](RELEASING.md) for its integrity and operational requirements.

## Proposed: BYE school schedule API (not shipped)

A future service could cache official PCC term/course/section records and return normalized responses to BYE clients.

Candidate read operations (illustrative only; **no routes are committed or deployed**):

~~~text
GET /v1/schools
GET /v1/schools/{schoolId}/terms
GET /v1/schools/{schoolId}/courses?term=...
GET /v1/schools/{schoolId}/sections?term=...&course=...
~~~

Before selecting endpoints, define:

1. **Upstream agreement:** source terms, permissions, access method, permitted caching and refresh rates.
2. **Normalization:** stable IDs, course aliases, term mapping, instructor identifiers, and meeting times.
3. **Freshness contract:** last-fetched timestamps, TTL, stale responses, refresh jobs and change detection.
4. **Performance:** indexes, pagination, response size, cache key design and client retry/backoff.
5. **Security:** user-versus-service credentials, per-client rate limits, allowed origins, audit logs, and protection from open proxy abuse.
6. **Resilience:** upstream errors, partial term ingestion, idempotent refresh, rollback, and observability.
7. **Multi-school evolution:** PCC-first conventions with extensible school adapters; do not assume another school's feed is identical.

Caching may reduce repeated network requests and improve response time, but it still relies on authorized upstream access and periodic refresh. No claims about measured speedups should be made until benchmarks exist.

## Separate proposed reviews API

Student review submission and reading are a different service/data contract from the PCC schedule API. Design moderation and Row Level Security before enabling public writes. See [Database plans](database.md). Never expose Supabase service-role credentials in the desktop client.

## Changes and verification

Any external API change should include a recorded sample contract (with private data removed), error handling, rate-limit behavior, deterministic tests/fixtures, and a separately authorized live check. Mark unverified third-party behavior explicitly.
