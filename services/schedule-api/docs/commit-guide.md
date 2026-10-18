# Commit preparation and handoff

The working tree contains more than the documentation change. Review the staged
file list in GitHub Desktop before committing; do not unintentionally combine
unrelated work. Nothing was staged, committed or pushed during documentation cleanup.

## Suggested change groups

| Group | Include | Keep separate |
| --- | --- | --- |
| PCC pilot | `docs/pcc-schedule-pilot.md`, `scripts/pcc_import.py`, `scripts/tests/test_pcc_import.py`, `scripts/tests/pcc_schedule_db.mjs`, synthetic pilot fixtures, `supabase/004_pcc_schedule.sql`, `supabase/005_pcc_schedule_source_integrity.sql` | Live source captures and owner SQL bundles |
| Standalone API and docs | `services/schedule-api/`, repository documentation links/status updates, `AGENTS.md` handoff preference | Dependencies, real environment files, generated deployment output |
| Windows fixes | Existing changes under `apps/cross-platform/`, including its fixtures and verification record | Generated executables and packaging output |

If splitting commits, put the pilot foundation before the API. The Windows fixes
are independent. The API package includes its lockfile, OpenAPI contract, source,
six migrations, scripts, tests and documentation together.

## Double-check before committing

1. Review `git status --short` and the intended diff; preserve other-agent work.
2. Check Markdown links, current-versus-future claims, and `git diff --check`.
3. Confirm no real keys, tokens, raw live captures or generated artifacts are staged.
   A template `.env.example` with blank credential values is intentional.
4. For code changes, run the appropriate offline checks. The backend commands are
   `npm test`, `npm run test:db` and `npm run check` from the package directory.
   A saved-feed benchmark is optional and requires the ignored local capture.
5. Keep hosted acceptance and live source checks explicit. Do not repeatedly call
   PCC or RMP just to prepare a documentation commit.
6. Provide **Summary** and **Description**, including checks actually run now and
   any relevant earlier recorded verification. State whether a commit was made.

The [verification report](verification.md) records 11 backend unit/contract/
transport tests, 15 database scenarios and eight hosted acceptance scenarios
from the implementation phase. Documentation cleanup uses link/consistency/Git
hygiene checks; it does not claim those live checks were rerun.

Documentation cleanup on October 17 checked 15 Markdown files, 94 local links,
and 38 API files eligible for Git. Relative links and whitespace checks passed;
no secret-key, long JWT, or private-key patterns were found in those API files.
Git exclusions cover dependency folders, local environment files, generated
deployment output and the ignored live PCC capture. `git diff --check` passed.
Application files and backend runtime code were not edited in this cleanup.

## Ready-to-paste text

Use the entry that matches the files you select.

### PCC pilot commit

**Summary**

Add the private Fall 2026 PCC schedule database and importer

**Description**

Preserve original source rows and complete course, section, meeting and instructor
data in a private schema. Add staged atomic publication, repeat-import handling,
source integrity checks, owner inspection/rollback commands and fixture coverage.
Record the verified Fall 2026 snapshot separately from existing student reviews.

### Standalone API and documentation commit

**Summary**

Add the standalone PCC schedule API and organize its documentation

**Description**

Add an independently deployed v1 API and private Supabase synchronization worker
for Fall 2026. Separate catalog and availability versions, share PCC request
limits, suppress stale counts, and bound storage, retries and rollback history.

Document architecture, setup, keys, operations, verification, queued work and
commit preparation in a dedicated folder. Record the preference to include a
Summary and Description in future commit handoffs.

Implementation verification records 11 unit/contract/transport tests, 15 database
scenarios, eight hosted scenarios and a saved-feed benchmark. Client integration
and multi-key generation/rotation remain future work.

### Windows fixes commit

**Summary**

Fix Windows course suggestions and repeated profile dialogs

**Description**

Keep matching course suggestions visible for complete letter-suffix queries and
preserve keyboard/mouse selection, dismissal and stale-response protections.
Open profile choosers only on explicit request, retaining saved choices and
identity checks. Include regression fixtures and the Windows verification record.
Use that record for exact checks and remaining platform limitations.

### One combined commit, if intentionally selected

**Summary**

Fix Windows search and add the PCC schedule database and API

**Description**

Fix letter-suffix suggestions and repeated professor-profile dialogs in Windows.
Add the private Fall 2026 schedule importer and independently deployed Supabase
API, with shared availability refresh, atomic publication and bounded retention.
Organize the API documentation and record the Summary/Description handoff rule.
Include the relevant fixture tests and verification records. Existing review
data and native Mac behavior remain unchanged; API client integration is pending.
