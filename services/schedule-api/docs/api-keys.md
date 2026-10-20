# BYE client keys

BYE schedule keys identify shared applications (Windows, Mac, website, or other),
not individual students. Generate them in the [local owner dashboard](owner-dashboard.md).
They contain 256 random bits and begin with `bye_pk_`. Send them in the existing
`apikey` header. Students do not need to sign in to browse schedules.

The private registry stores SHA-256 digests and masked metadata only. New plaintext
is returned once; retries of a completed creation return metadata, never plaintext.
An ordinary key has no expiry. App releases do not require new keys.

- Rotate: create an active replacement atomically; the old key retires in 30 days.
- Extend: add 30 days from the later of now/current deadline, or select a later UTC date.
  Restoring an expired key requires explicit confirmation.
- Disable/enable: temporary block; enabling still respects retirement.
- Revoke: permanent block with confirmation, retained in audit history.

Authorization is checked in the database on every schedule read, before ETag/304.
There is no compiled-key fallback or positive authorization cache. The next request
observes revocation; requests already authorized may finish. Network rate limits
are shared across keys, so more keys do not multiply request allowances.

The previously accepted public key's verified digest was registered atomically
with the migration and remains active with no retirement scheduled. It is a
compatibility entry, not a new Supabase project credential.

## Keep the two public key types separate

| Value | Purpose |
| --- | --- |
| BYE key / `BYE_CLIENT_KEY` | Schedule browsing; generated in BYE dashboard |
| Genuine Supabase publishable key / `BYE_PUBLISHABLE_KEY` | Owner email sign-in; public project configuration |
| Owner access JWT | Management only; kept in local-server RAM |
| `BYE_JOB_TOKEN` or `BYE_SERVER_KEY` | Private bootstrap/recovery command only |
| `BYE_JOB_TOKEN_SHA256` | Deploy-time verification digest for the existing private worker |

Creating, disabling, rotating or revoking BYE keys never modifies Supabase project
keys, Auth configuration, review login, or existing app profile choices.

At most 100 non-revoked keys may exist. Successful use timestamps are sampled once
per five minutes. Revoked metadata and audit events are retained 90 days; audit is
also capped at 2,500 records. No student browsing history is collected.

Installed clients do not yet receive replacement keys automatically. Coordinate
that separate integration before retiring a key they depend on.
