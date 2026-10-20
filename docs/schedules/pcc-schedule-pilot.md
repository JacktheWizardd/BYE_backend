# PCC schedule database: Fall 2026 pilot

The pilot imports only Fall 2026 (`202670`) into the existing BYE Supabase project.
It adds an owner-only `pcc_schedule` schema; it does not change the student-review
catalog, reviews, app clients, website, RMP integration, or scheduled jobs.
Availability is a **dated snapshot**, not live information.

## Stored data

| Table | Responsibility |
| --- | --- |
| `terms` | Published-term metadata and active/previous import pointers |
| `import_runs` | Source URLs, retrieval date, raw/canonical hashes, expected counts, findings and publication state |
| `source_rows` | Every original JSON object, source ordinal and links to its normalized section, meeting and instructor assignments |
| `courses` | Official subject/number, all title variants and original course-note HTML |
| `sections` | CRN, course, independent source status/counts, units and source notes/attributes/deadlines |
| `meetings` | Individual date ranges, local times, weekdays, component format/location fields and original meeting data |
| `instructor_assignments` | Primary/secondary instructor slots scoped to a section, without a global name-based identity merge |

All seven tables have RLS enabled without client policies. Schema, table, sequence
and function privileges are revoked from `PUBLIC`, `anon`, `authenticated` and
`service_role`. Do not add this schema to the exposed Data API schemas. The owner
and the Supabase SQL connector can inspect/import; there is no public read API.

Original HTML and unfamiliar fields are stored as inert data. Future clients
must sanitize text and links before rendering. Staff contact fields remain in
private source records. Missing counts are null, and reported negative numbers
are retained rather than silently corrected. Registration status is never
inferred from seats or enrollment. `R`, `X` and other undocumented codes remain
uninterpreted and are not filtered out.

The source's `termCode` must equal `202670`; `defaultTerm` is not used as the
semester identity. Official course labels are retained without a narrow suffix
regex, so `005A`, `005AH`, `005AL` and `C1000H` remain distinct. This phase does
not infer old/new CCN aliases, linked-course relationships, prerequisite
eligibility, or textbook details from natural language.

## Owner workflow

Use your installed Python 3 executable (`python` on Windows or `python3` on
macOS/Linux). Run from this repository root. No third-party Python package is
needed for fetching, normalization, dry runs or SQL generation.

1. Review and apply `supabase/004_pcc_schedule.sql`, then
   `supabase/005_pcc_schedule_source_integrity.sql`, once as the database owner.
   It creates a new schema and fails if that schema already exists. Do not rerun
   the existing review schema or review seed. Check for existing installation
   with `select to_regnamespace('pcc_schedule');`.
2. Fetch the published terms and Fall 2026 once, validate and generate SQL:

   ```sh
   python scripts/pcc_import.py --dry-run --emit-sql
   ```

   Default output is ignored `.local-docs/pcc-schedule/fall-2026/`:
   `source.json`, `terms.json`, `bundle.json`, `report.json` and numbered SQL
   batches with `sql/manifest.json`. The report contains counts and findings,
   not instructor names, emails, review content or credentials. A validation
   error exits nonzero and prevents SQL generation/application. Noncanonical
   identities, conflicting section values and malformed meeting dates are
   blocking errors; unknown statuses are warnings.
3. Inspect `report.json`. Execute the generated SQL batches in manifest order
   using the connected Supabase SQL tool. The final batch calls
   `pcc_schedule.publish_import(...)`; only this changes the active pointer.
   Existing snapshots remain active throughout staging. SQL batches must be
   treated as complete files: never truncate their JSON literals.
4. Alternatively, install `psycopg[binary]>=3.2,<4` into an owner-controlled
   Python environment, supply a **server-side** database connection through
   `PCC_DATABASE_URL`, and run:

   ```sh
   python scripts/pcc_import.py --bundle .local-docs/pcc-schedule/fall-2026/bundle.json --apply
   ```

   This uses a PostgreSQL connection, not an anon/publishable API key. Connection
   values are never printed. A saved bundle is re-normalized from its original
   rows before application; a hand-edited valid flag does not bypass checks.
5. Inspect without a PCC request:

   ```sh
   python scripts/pcc_import.py --inspect
   python scripts/pcc_import.py --inspect --apply
   ```

   Without `--apply`, owner operations only print SQL. With it, they use the
   database connection. Never paste connection strings into chat or commit
   generated source/bundle/SQL artifacts.

Imports have a deterministic content-based ID. Repeating an identical snapshot
does not duplicate records. Row reordering does not create a new snapshot or
section change. Exact duplicate source rows remain individually accounted for,
while normalized meetings/assignments are deduplicated. Counts for the inspected
term are meeting-row counts, not unique-section counts.

Interrupted uploads remain `staging` and can be resumed with the same bundle.
Never edit an already staged bundle in place: generate a new import for changed
data. Database constraints and final reconciliation must pass before publication.
The final pointer switch is transactional and serialized by a term-row lock.
Published snapshot records cannot be updated/deleted through the normal import
path. Older retrieved data cannot replace a newer active snapshot.

Publication records added, changed and removed CRNs compared with the prior
active snapshot. A removal means absent in the new source response, not proof
that a class was cancelled. Earlier snapshots are retained; nothing is removed
from student-review tables.

Select the previous successfully published snapshot without deleting either:

```sh
python scripts/pcc_import.py --select-previous
python scripts/pcc_import.py --select-previous --apply
```

There is no previous snapshot after the first import. Repeated selection swaps
the active and previous pointers. Rollback changes the selected snapshot, not
its source timestamp or historical content. Retention/cleanup is deferred until
the pilot has been reviewed.

## Verification

Normalization and CLI tests (fixture-only; no network):

```sh
python -I -m unittest discover -s scripts/tests -p test_pcc_import.py -v
```

PostgreSQL integration tests use a pinned, isolated PGlite engine. Install test
dependencies only into the ignored tools folder:

```sh
npm install --prefix .local-docs/pcc-schedule-tools --no-audit --no-fund @electric-sql/pglite@0.3.14
node scripts/tests/pcc_schedule_db.mjs
node scripts/tests/pcc_schedule_db.mjs .local-docs/pcc-schedule/fall-2026
```

Set `PCC_PYTHON` to your Python executable if `python3` is unavailable; optionally
set `PCC_PGLITE_MODULE` to another installed PGlite entrypoint. No live database
credentials are used by these tests. The optional second command rehearses the
complete saved Fall source and all generated batches in a fresh local database.

Acceptance covers suffix/CCN preservation, closed-with-seats status, date-specific
hybrid meetings, co-instructors, blank instructor slots, source HTML, unknown
fields/statuses, missing/negative counts, duplicate/reordered input, malformed
rows, conflicting section data, partial imports, immutability, idempotence,
section diffs, rollback, access denial and preservation of existing review data.

## Pilot results

The first fetched Fall 2026 response contained 5,602 source rows (12,256,542 bytes).
Local normalization and full PostgreSQL rehearsal reconciled all 5,602 rows into:

| Record | Count |
| --- | ---: |
| Courses | 1,101 |
| Sections | 3,607 |
| Meetings | 5,601 |
| Instructor assignments | 3,775 |
| Preserved source rows | 5,602 |

There were zero blocking validation errors. There were 394 uninterpreted-status
findings: 375 `X` rows and 19 `R` rows. Those rows are retained. The checks do not
establish the meaning of these codes or PCC's source update frequency.

Textbook retrieval is deferred: it appears in PCC's section panel but was not
present in the semester response inspected during planning. Course equivalency
mapping and interpretation of free-text enrollment instructions also remain
separate follow-up work. No API, client changes or refresh automation is enabled.

Representative source comparisons (verified locally; repeated against Supabase
after publication):

| Source example | Expected stored result |
| --- | --- |
| MATH 005A, CRN 71655 | Status `C`, enrolled 28, capacity 30, available seats 2; no inferred open status |
| MATH 005A, CRN 80206 | Status `C`, enrolled 21, capacity 28, available seats 7; concurrent-enrollment note retains MATH 105A CRN 80214 |
| ACCT 001A, CRN 81016 | Campus meetings on September 29, October 27 and November 24, plus August 24–December 13 online component |
| Course identifiers | `MATH 005A`, `MATH 005AH`, `MATH 005AL`, `CS 003AL` and `ENGL C1000H` are distinct records |

The automated suite passes 20 Python tests and 15 PostgreSQL integration
scenarios, plus the full saved-source PostgreSQL rehearsal. The private schema's
seven no-policy RLS notices are intentional deny-by-default informational
findings: [Supabase explanation](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).
The existing review-submission permission and Auth password-protection warnings
were present before this migration and were not changed.

The importer emits ASCII-escaped JSON in SQL batches so Windows pipe encodings
cannot alter Unicode text. A database trigger independently checks the actual
stored JSONB content against the source checksum before selecting a snapshot.
Regression coverage includes accented text, punctuation and non-BMP characters,
and verifies that damaged source text cannot become active.

### Live Supabase result

The Fall 2026 snapshot is **published and verified** in the existing BYE
Supabase project. The source was retrieved October 17, 2026 at 7:53 p.m. Pacific.
Only one import is stored; there is no previous snapshot yet.

- All five normalized/raw table counts match the table above. Source ordinals
  span 1–5,602, with every row preserved.
- The independent complete-source JSONB checksum matches between the local
  source and Supabase: `49c48ab48e18f54357d10de5249cec51`.
- Full-record checksums for all five data tables also matched the local bundle
  in the final validation transaction, including Unicode fields.
- Source file SHA-256:
  `537444eddf536e518d2585cb0802d77b6475a778106bc68760b9387324ad0da5`.
- Order-independent source content SHA-256:
  `ab957a3daffb965cbb51e21d944554f6bca7ffcfefdb8f749ed3a21f5193c26a`.
- The representative CRNs, suffix courses and four hybrid meeting components
  were checked against the published tables and match the source.
- The existing review catalog is unchanged: 1,531 courses, 1,425 professors and
  two reviews. The before/after checksum of the complete review records matches.
- Live privilege checks confirm no schema usage for `anon`, `authenticated` or
  `service_role`, no anonymous publication permission, and zero client policies.

The initial connector upload had a Windows pipe-encoding issue affecting 555
raw rows with non-ASCII text. It was corrected atomically against the preserved
original bundle, with complete source and normalized-record checksums enforced
before commit. SQL generation now escapes Unicode as ASCII, and migration 005
adds the database-side checksum gate to prevent recurrence. No review records,
client security policies or app code were changed during the correction.

The pilot satisfies the data-load and verification boundary. Interpreting `R`/
`X`, textbook retrieval, API endpoints, additional semesters, weekly jobs,
live availability refresh and app integration remain deferred.
