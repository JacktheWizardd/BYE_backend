# Database plans (proposed)

**Status: design only.** BYE currently retrieves PCC schedule information and RMP professor information directly; neither of the Supabase initiatives below should be described as an implemented production database.

The project has **two distinct Supabase-related initiatives**. They solve different problems and should retain separate schemas, access rules, and implementation plans even if they eventually share infrastructure.

## 1. BYE student-submitted professor reviews

**Goal:** Collect original ratings and review text submitted voluntarily by students, reducing long-term product dependence on RMP for user-generated feedback.

Proposed capabilities:

- Optional, student-originated submissions associated with a college and professor.
- Structured rating fields plus optional review text, course/context, and submission timestamps.
- Moderation/reporting, abuse prevention, edit/deletion handling, and duplicate controls.
- A public-read projection of approved content, distinct from private submission/moderation records.
- Clear attribution, data retention, privacy notice, and user deletion workflow.

Suggested entities for design discussion (not migrations): `schools`, `professors`, `courses`, `student_reviews`, `review_reports`, and `moderation_actions`. Agree on stable school/professor identity keys and the rating scale before implementing tables.

**Security requirements to design first:** least-privilege roles, Supabase Row Level Security (RLS), review submission restrictions, service-role keys only on trusted server processes, server-side validation, spam controls, and moderation before publication. Do not assume a private repository makes a public submission endpoint safe.

**Data boundary:** BYE reviews are not copies of RMP reviews. Do not bulk import or republish third-party review text without appropriate rights.

## 2. PCC class-schedule service and cache

**Goal:** Provide BYE clients with a consistent, faster interface to official PCC class-schedule data while reducing redundant upstream requests.

This is fundamentally a **school-data retrieval and caching service**, not a student review database.

Potential design:

~~~text
BYE desktop or website client
             |
             v
BYE school schedule API
             |
             +--> cache / structured schedule tables (Supabase)
             |
             +--> controlled PCC refresh process --> upstream PCC source
~~~

Suggested entities for design discussion: `schools`, `terms`, `courses`, `sections`, `meetings`, `instructors`, and `ingestion_runs`. These are **concepts**, not deployed tables.

The cache needs a documented source, refresh interval/TTL, data freshness timestamps, schema/version mapping, correction path, request rate limits, cancellation/retries, and behavior during upstream outages. Stale data must be labeled, and official PCC information remains authoritative.

**Feasibility gate:** Confirm that the source can be accessed and refreshed under PCC's applicable permissions and technical constraints. Hosting an API cannot bypass upstream availability or permission limits. Avoid uncontrolled scraping, excessive polling, and assumptions that all schedules can be reproduced indefinitely.

## Separation of concerns

| Area | Student reviews | School schedule cache |
| --- | --- | --- |
| Source | Voluntary BYE student submissions | Official/authorized PCC schedule data |
| Main write path | Review submission + moderation | Controlled ingestion/refresh jobs |
| Main read path | Approved reviews and aggregated ratings | Course, section, term, and meeting queries |
| Access concerns | Personal data, abuse, moderation, RLS | Upstream access, cache staleness, rate limiting |
| Product purpose | Independent review community | Search performance and consistent school data |

Do not mix review submissions with fetched school schedule records, even when some foreign keys (school/course/professor) overlap. Identity mappings should be explicit and auditable.

## Suggested implementation order

1. Confirm both sets of requirements, ownership, data sources, and permissions.
2. Draft separate schemas, RLS/access policies, and API contracts.
3. Create isolated development/test environments with synthetic records.
4. Implement migrations, ingestion/submission validation, and automated tests.
5. Add observability, cleanup/deletion policy, and incident handling.
6. Integrate one feature at a time behind clear flags, then verify before declaring it shipped.

Record actual Supabase project references and credentials only in approved configuration/secret stores, not as copy-pasted developer documentation. The exact schema, hosting architecture, operational cost, and rollout sequence remain open decisions.
