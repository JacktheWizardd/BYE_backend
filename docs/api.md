# API and external integrations

This document distinguishes **current direct client integrations** from the
**independently deployed BYE schedule API**. For the backend's current contract,
keys and operations, use the [API documentation folder](../services/schedule-api/docs/README.md).
For client internals, see [Architecture](architecture.md).

## Current: PCC schedule data

The native Mac app fetches PCC schedule/catalog data directly, then resolves courses and sections using local Swift parsing/domain logic. Matching includes official course labels and common user shorthand. The Windows/Electron implementation has its own PCC client/cache path.

Important properties:

- The selected term and authoritative course/section identity matter.
- Network failures, cancellation, and changes to upstream schemas must be handled.
- Date/time and delivery formats must be interpreted carefully for weekday filtering.
- School data can change; retrieved information is not an enrollment guarantee.

The hosted schedule API is deployed, but these clients have not been connected
to it yet. Backend availability and client integration are separate milestones.

## Current: Rate My Professors

The native `Sources/BYEAPI/` Swift module communicates with an undocumented RMP GraphQL endpoint. It is **not** a standalone hosted BYE API.

The documented transport uses bounded concurrency, request spacing, retries and timeouts; identity checks protect against accidentally combining similarly named professors. Students explicitly resolve ambiguous profiles. The app preserves original source context and differentiates professor-wide ratings from course-specific review coverage.

Consult [BYEAPI's module README](../Sources/BYEAPI/README.md) for details. Because this integration is unofficial, it may break or become unavailable and requires continued review of permitted usage. Do not assume an accessible endpoint grants redistribution rights.

## Current: Mac app updates

Distribution builds use a Sparkle appcast and signed update archives hosted on the separate BYE Cloudflare Pages website. This is a **release delivery service**, not a course-schedule API. Follow [Releasing](RELEASING.md) for its integrity and operational requirements.

## Current: standalone BYE schedule API

The backend is deployed independently of app and website releases. It serves
Fall 2026 only through `/v1/terms` and the term's manifest, catalog, course search,
sections and availability endpoints. The stable contract is
[OpenAPI](../services/schedule-api/openapi.json).

Daily baseline and shared demand-driven source checks feed private Supabase
storage. Public reads return stored data; no user request waits for PCC.
Catalog and availability versions are independent, stale availability is
suppressed, and retention and source request budgets are bounded.

Public reads use one configured publishable key without student login. Key
management, multi-key rotation and client integration remain future work. See
[key behavior](../services/schedule-api/docs/api-keys.md),
[operations](../services/schedule-api/docs/guide.md), and
[verification](../services/schedule-api/docs/verification.md).

Earlier multi-school route proposals are superseded by this PCC-first contract.
Additional semesters, schools and adapters require a separate future phase.

## Separate proposed reviews API

Student review submission and reading are a different service/data contract from the PCC schedule API. Design moderation and Row Level Security before enabling public writes. See [Database plans](database.md). Never expose Supabase service-role credentials in the desktop client.

## Changes and verification

Any external API change should include a recorded sample contract (with private data removed), error handling, rate-limit behavior, deterministic tests/fixtures, and a separately authorized live check. Mark unverified third-party behavior explicitly.
