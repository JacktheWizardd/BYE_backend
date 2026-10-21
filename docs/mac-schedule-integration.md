# Native Mac schedule integration

Implemented October 20, 2026, Pacific time. Local source and test-app acceptance;
not a deployment or release.

## Starting point and ownership

The current checkout started clean on `main` at `c035b5b`. Only the native
`Sources/` and `Tests/` changes from schedule handoff `2497c4b` were applied,
then reviewed and corrected on this Mac. The backend, Windows adapter and
website changes from that commit were not copied into this checkout.

The SwiftUI interface remains in place. Normal `AppModel` construction uses
`PCCClient.sharedBackend()` and the new `ScheduleAPIClient` actor. Explicitly
injected legacy `PCCClient(session:)` remains available for existing tests and
research paths. A backend failure never switches the normal app to direct PCC
or sample data. The existing `BYEAPI` module remains the separate RMP client.
AI remains disabled and Sparkle/update-feed behavior is unchanged.

## Behavior and corrections

- Terms and course catalogs come from the configured `/v1` read API. Term refresh
  retains the chosen semester; a failed background discovery retains the existing
  list. Codes preserve complete suffixes, official prefixes and leading zeros.
- Course-only disk catalogs retain up to three semesters. Suggestions revalidate
  before publication and can use that semester's saved catalog offline. Sections,
  instructor identities and seat counts are not persisted in this catalog cache.
- Manifest reads retain unchanged catalogs/sections; catalog changes fetch sections,
  while availability changes request displayed CRNs in batches of at most 100.
  Response caches, term catalogs and course entries are bounded. Conditional reads
  reuse only that resource's cached representation. Cross-semester responses and
  catalog-generation races fail instead of mixing snapshots.
- The adapter retains co-instructors, meetings, term-part labels, dates, locations
  and units. Sections with no meetings or no assigned instructor remain visible.
  Missing delivery metadata is labelled unavailable. Official catalog membership
  does not depend on registration status, as established in the source handoff.
- Visible, active, online windows poll approximately every minute with jitter;
  failures back off to fifteen minutes. Retry-After is enforced independently by
  the transport. Minimize/hide/inactive/offline states stop automatic polling;
  returning to an eligible state initiates a refresh. Term discovery is hourly.
- Source timestamps determine freshness. Unknown, invalid, future-skewed or
  fifteen-minute-old checks hide seat/waitlist counts. Expiry runs locally even
  when network refresh fails; changing the stale flag restarts the expiry task.
- Refresh preserves valid professor/profile/review state and filters. A removed
  instructor or a meeting change that hides the selected professor returns to the
  neutral overview. Removed assignments never inherit a previous profile. New
  assignments require explicit profile retrieval. Generation/cancellation checks
  precede publication, including initial-search metadata and refresh failures.
- Fixed a missing return that prevented the source handoff from compiling. The
  default API transport is ephemeral, disables persistent cookies/credentials and
  URL caching, refuses redirects, and accepts HTTPS or loopback HTTP only.

## Configuration and rollout boundary

Use `BYE_SCHEDULE_API_URL` and `BYE_SCHEDULE_API_KEY` in the launch environment,
or `BYEScheduleAPIURL` and `BYEScheduleAPIKey` in the app bundle's Info.plist.
Environment values take precedence. The URL is the API function base, before
`/v1/terms`, for example the base recorded in the backend's OpenAPI document.
Only the public application identification key belongs in an installed client;
never use a Supabase service-role, owner, job or cron credential.

Builds (October 20, 2026): `scripts/schedule-api-config.sh` gives both builds the
hosted API base above by default and reads the BYE application key from the Git-ignored
`config/schedule-api.local` (`KEY=bye_pk_…`, format in `config/schedule-api.example`),
or from `BYE_SCHEDULE_API_KEY`. It refuses Supabase publishable or secret keys, JWTs,
other prefixes and the example placeholder, and accepts only HTTPS or loopback URLs. It
never prints the key. `build-test-app.sh` embeds the key when present and says so;
`build-app.sh` stops without one. Tests: `scripts/tests/test_schedule_api_config.py`.
Create a dedicated "Mac app" key in the owner dashboard. Installed apps do not receive
replacement keys yet, so do not retire a key a shipped build depends on.

No production configuration was present in the inspected environment or local
client env files. Without a key the test build embeds no schedule settings. Launching
it without configuration displays “The BYE schedule service is not configured.”
The UI acceptance used a temporary loopback configuration and fictional TBA data;
that configuration was removed afterward. No production key was read or saved.

The backend's semester-aware migration/deployment and hosted synchronization
outage remain separate gates. The Mac source does not prove those are resolved.
A compatible staged backend and approved public application key are needed for
live acceptance. No backend mutation, PCC/RMP collection, email, commit, push,
paid resource, deployment or release was performed for this work.

## Verification

- `./scripts/swift.sh test`: **207 tests passed, zero failures**. Existing WebKit fixture
  tests require macOS service access; sandboxed attempts stalled during WebKit
  initialization and were stopped. The full suite was rerun outside that sandbox.
- New core fixtures cover API versions and conditional reads, co-instructors and
  meetings, complete course suffixes, unknown/stale counts, empty assignments,
  term isolation, publication races, rate limiting and course-only disk recovery.
- New app fixtures cover preserved profiles/reviews/selection/filters, assignment
  replacement, meeting changes, superseded initial searches and refreshes,
  overlapping refresh suppression, cancellation, local fifteen-minute expiry,
  offline recovery and term discovery without automatic semester switching.
- `./scripts/build-test-app.sh`: release build and strict ad-hoc signature
  verification passed; stable output is `test/BYE Test.app`.
- Visible native fixture acceptance: `math5ah` suggestion selected `MATH 005AH`;
  search showed neutral overview, section, source timestamp and three open seats.
  Stale mode hid counts; simulated HTTP 503 retained readable schedule/report;
  recovery restored seats/waitlist while retaining the selected report. No live
  sources were requested. Native Window → Minimize paused polling for about seventy
  seconds; restoring the window refreshed immediately and retained the selected
  report. Visual layout and accessibility labels were inspected.
- Full VoiceOver, a physical network-disconnection test, another Mac and live
  hosted acceptance were not performed. Existing Swift wrapper deprecation
  warnings remain; no toolchain/dependency upgrade was made.

## Files for GitHub Desktop

Include the native changes in `Sources/Classwise/` (AppModel, ClasswiseApp,
ContentView and new ScheduleLifecycle), `Sources/ClasswiseCore/` (new
ScheduleAPIClient, Services, Models and CourseSuggestions), the new schedule API
and refresh tests plus updated core assertions in `Tests/`, this document and
`docs/PROJECT_STATUS.md`. Generated apps, local fixtures and logs stay out of Git.
The website repository has no changes from this task.

Summary:

```text
Complete native Mac schedule API integration and verification
```

Description:

```text
Apply the native schedule adapter from 2497c4b and fix Swift compilation, contract mapping, semester/version isolation, source expiry and stale-result publication. Preserve valid profiles, reviews, filters and selections during bounded lifecycle refreshes. Keep offline course suggestions separate from availability, require configured API access and prevent direct PCC fallback. Add native fixture regressions and document local acceptance. Mac tests and test-app build pass; live API configuration and compatible hosted rollout remain pending. Changes remain uncommitted; no push, deployment or release.
```
