# Database overview

**Status as of October 16, 2026:** The Supabase review database is live and its core submission, reporting, privacy, and cleanup behavior has been tested. The student-facing login and review form, real email delivery, and Mac app integration remain pending. The separate hosted schedule cache is still proposed; the app continues to retrieve PCC schedules and RMP professor information directly.

Start with [Review database explained](review-database-explained.md) for the plain-language guide. Use [Supabase status and plan](supabase-plan.md) for the migrations, technical decisions, and verification record.

The project has **two distinct Supabase-related initiatives**. They solve different problems and should retain separate schemas, access rules, and implementation plans even if they eventually share infrastructure.

## 1. BYE student-submitted professor reviews

**Goal:** Collect original ratings and review text submitted voluntarily by students, reducing long-term product dependence on RMP for user-generated feedback.

Implemented database behavior:

- Lists of 1,425 professors and 1,531 courses loaded from PCC schedule data.
- Confirmed `@go.pasadena.edu` users submit quality/difficulty ratings, optional review text, and seven optional structured answers through `submit_review`.
- One review per user, professor, and course; one report per user and visible review.
- Three distinct reports automatically hide a review, its answers, and its contribution to comparison counts.
- Public queries expose permitted review fields and counts. Reviewer IDs and report records are private to privileged administrators.

The live tables are `professors`, `courses`, `reviews`, `review_dimensions`, `dimensions`, and `reports`. SQL is saved in [`schema.sql`](../supabase/schema.sql), [`002_write_side.sql`](../supabase/002_write_side.sql), and [`003_helper_permissions.sql`](../supabase/003_helper_permissions.sql). The [manual checks](../supabase/002_write_side_checks.sql) document the test procedure.

**Student experience planned:** Enter a PCC email and verify a one-time code. No student password or profile-management screens are required. Supabase maintains the user identity behind the scenes. Email access does not prove current enrollment or attendance in a particular class.

**Remaining work:** Configure/test email-code delivery and confirmation settings; build the review form and app integration; define retention/deletion handling, moderation review, and additional abuse prevention. Visible reviews are currently published immediately and hidden after three reports; pre-publication moderation and automatic personal-information filtering are not implemented. The expected authenticated `submit_review` Security Advisor warning was reviewed; the two maintenance-helper warnings were fixed.

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

## Remaining implementation order

1. Finish review email-code configuration and real delivery testing, then build the student-facing review form.
2. Integrate review counts into the Mac app after choosing the client approach and implementing the Swift comparison statistics.
3. Define the remaining review moderation, retention/deletion, and operational workflows.
4. Confirm requirements and source permissions for the separate schedule service before implementing its schema or refresh jobs.
5. Verify each student-facing feature before declaring it shipped.

Record actual Supabase project references and credentials only in approved configuration/secret stores, not as copy-pasted developer documentation. The schedule-cache schema, hosting architecture, operational cost, and rollout sequence remain open decisions. Review-database decisions and pending work are tracked in the [Supabase plan](supabase-plan.md).
