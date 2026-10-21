# Private review verification — staged local implementation

October 20, 2026. No production migration, deployment or Auth-account deletion has been performed.

The website repository implements the replacement review sign-in system: school-mailbox HMAC identifiers, direct Brevo code delivery, opaque one-hour sessions, shared rate limits and private administrator bans. It no longer uses Supabase email Auth for the new review flow. The currently deployed legacy flow continues retaining addresses until an explicitly authorized rollout and separate cleanup.

Schema changes are split into `supabase/migrations/*_private_review_verification.sql` (prepare) and `*_private_review_cutover.sql` (replace Auth foreign keys and disable old writes). Neither file deletes Auth users. Backfill preserves author/reporter UUIDs and all review/report/answer data. Do not blindly run CLI `db push`: existing SQL files were provisioned manually and their migration history must be reconciled first.

The operator/backfill tool and full instructions live in [the website private-email runbook](../../BYE_website/docs/reviews/PRIVATE_EMAIL_VERIFICATION.md). Run the explicit database rehearsal from the website with `pnpm test:reviews:db ../BYE_Before_You_Enroll/supabase`. Normal website builds/unit tests remain independent of the app checkout.

Ban/unban uses a reference review UUID. Bans persist until lifted, revoke sessions and block submission/reporting; only explicitly selected reviews are hidden. Runtime credentials cannot administer bans or read Auth users.

After email cleanup, rollback disables writes while preserving reviews and private identities; it must never silently restore email collection. Provider delivery records, historical logs/backups and self-identifying review text remain separate privacy considerations. The private author identity and HMAC key are not proof of complete anonymity.
