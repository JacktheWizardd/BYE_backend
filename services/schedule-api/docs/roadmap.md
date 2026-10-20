# Implemented state and queued work

## Delivered backend

- Independently deployed read API and private synchronization worker.
- Fall 2026 catalog, sections and availability in the existing Supabase project.
- Stable v1 contract, aliases, suffix preservation, conditional reads and errors.
- Shared source request budget, demand lease, daily checks and scheduled refresh.
- Stale-count suppression, atomic publication, rollback and bounded retention.
- Fixture/database tests, saved-source benchmark and recorded hosted acceptance.

## Delivered key management and hosted owner access

The private registry, owner management API and separate Cloudflare dashboard are
deployed. Shared keys can be created, rotated, extended, disabled and revoked
without a read-API redeployment. Owner sign-in and the temporary-key lifecycle
walkthrough passed. Test keys are revoked; the original key remains active with
no expiry. The hosted site works with the local development server stopped.

See the [delivery record](records/2026-10-19-delivery.md) for decisions and the
[handoff](records/handoff.md) for taking over. Installed-client key delivery is
still separate from the completed management controls.

## Later: client integration

Connect clients in separately agreed phases. The integration requirements are:

- Use cached catalog data immediately; check the API on startup and Refresh.
- Use one 60-second loop while visible, with one request in flight.
- Pause while hidden, minimized or offline; cancel obsolete work and back off.
- Fetch changed data and visible CRNs only; replace bounded caches.
- Update seats without resetting professor choices, reviews or filters.
- Show source-check timestamps and suppress expired availability.

Windows, native Mac and website changes are not part of the delivered backend.
The public website rollout is separate from connecting a test preview.

## Other queued items

- Additional semesters and schools after explicit scope and source validation.
- PCC's actual update cadence and any efficient seat-only/conditional endpoint.
- Meaning of undocumented `R`/`X` statuses and unfamiliar source fields.
- Verified textbook retrieval, linked-course interpretation and CCN equivalencies.
- Windows build-folder naming cleanup and further app review.
- Longer-duration operational observations before broader use; no unapproved paid upgrade.

Keep these items separate from the original student-review database and Mac
release/update infrastructure.
