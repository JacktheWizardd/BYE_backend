# API keys: current behavior and future management

The API currently accepts **one configured publishable key**. Supabase generates
that key; BYE does not yet have its own Generate key screen, key-management
endpoint, or per-platform key registry.

## How an app will use it

The client needs a stable API base URL and the accepted publishable key:

```http
GET /v1/terms/202670/courses?q=math5a
apikey: <configured-publishable-key>
```

The read handler hashes the supplied key and compares it with the configured
digest before serving curated schedule data. Missing or mismatched keys return
401. Rate limits and private database permissions are enforced separately.

A shipped app's public key is extractable. It identifies a calling component;
it does not prove that the caller is an authentic BYE installation or identify a
student. Browsing requires no student login. The key does not grant import,
administration or direct private-table access.

The same public key can remain in use across app releases. A UI change does not
need a new key, and students should not have to create or paste their own key.
No client has been connected to this API in this phase.

## Configure the current service

1. In the existing BYE Supabase project's Settings → API Keys, obtain the enabled
   default publishable key. Do not select a secret/service-role key.
2. Provide it as `BYE_PUBLISHABLE_KEY` in the backend deployment shell.
3. Follow [deployment setup](guide.md) for the project ref and job-token digest.
   `npm run deploy` injects the public-key digest into the function configuration.
4. Later client integration will configure that same key and base URL in the app.

Creating a different Supabase key does **not** automatically make BYE accept it.
This implementation validates its configured digest, not every key in the project.

## Credentials by purpose

| Value | Where it belongs | Purpose |
| --- | --- | --- |
| Publishable client key | Client configuration and deployment shell | Public schedule requests |
| `BYE_PUBLISHABLE_KEY` | Backend deployment shell | Select the accepted public key |
| `BYE_JOB_TOKEN_SHA256` | Backend deployment configuration | Non-secret digest used to verify the private machine token |
| `BYE_JOB_TOKEN` | Owner-only shell; token stored in Vault | Private sync, inspect, pause and rollback commands |
| `BYE_SERVER_KEY` | Owner-only shell, optional alternative | Privileged server credential accepted by owner tooling |
| Supabase server credential | Edge Function environment only | Server-to-database RPC access |

The example environment file contains names and blank credential values. Real
environment files, generated deployment output and tokens remain outside Git.

## Replacement and future rotation

Today, replacing the accepted public key requires a backend redeployment.
The handler accepts only one digest, so the old key stops working immediately.
Revoking a key in Supabase alone must not be treated as revoking BYE's explicit
allowlist: the backend configuration must also be updated.

Before keys are embedded in shipped clients, the next key-management phase should
support named Windows/Mac/web keys, creation and revocation, and overlapping
rotation without a backend redeployment. Installed clients still need a defined
way to receive replacement configuration before an old key is retired. These
are future features, not capabilities delivered by the current API.
