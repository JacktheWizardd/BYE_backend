# Hosted BYE owner dashboard (Cloudflare)

Live: **https://bye-admin.jack-truong2k1.workers.dev**.
Deployed October 19, 2026 (Pacific) to the existing Cloudflare Free account.
Worker version: `7fb9ee13-a222-424c-89c1-29e779dba956`.
Owner-assisted sign-in/key listing and independence from the stopped local server
are verified.

This is a separate `bye-admin` Cloudflare Worker, with static assets and one
SQLite-backed Durable Object. It does not deploy or change the public BYE website,
review login, source synchronization, Supabase keys, or application clients.

## Deploy independently

From `services/schedule-api/`:

```powershell
npm ci
npx wrangler login
npx wrangler whoami
# Verify this name is available; inspect any existing Worker instead of overwriting it.
npx wrangler deployments list --name bye-admin
npm test
npm run check
npm run test:admin:runtime
npm run admin:deploy
```

The deployment configuration is `dashboard/hosted/wrangler.jsonc`. It contains
only a genuine public Supabase Auth key and URLs. No Supabase service-role, database,
cron, or Cloudflare credential is included. Wrangler uses its own account login.
Use the existing account's Free plan; do not upgrade the plan to deploy this site.
The SQLite Durable Object configuration is Free-plan compatible; free quotas can
still cause requests to fail. A site being hosted does not guarantee zero outages.

Before the first deployment, verify the intended account, ensure no unrelated
`bye-admin` Worker exists, and make `PUBLIC_ORIGIN` exactly match the returned HTTPS
origin. Alternate origins are denied. Preview-version URLs are disabled. Deploy
changes to this Worker independently using `npm run admin:deploy`; no app release
or public website rebuild is needed. Git commit/push remains a separate owner step.

## Access and credentials

Use the same approved Supabase account and email code as the local dashboard.
Existing owners, client keys and audit history are shared through the deployed
`bye-key-admin` service. Public visitors see a sign-in page; key operations require
an approved owner user JWT checked by Supabase Auth and the database on every action.
The Cloudflare site uses no database or machine credential.

The browser receives a random `__Host-bye_admin` cookie with Secure, HttpOnly,
SameSite=Strict, Path=/ and a lifetime of at most one hour. Auth access tokens stay
only in the server's bounded RAM (8 sessions); refresh tokens are discarded. No
Auth tokens are stored in browser storage, cookies, Cloudflare SQLite, or Supabase
session tables added by this project. The cookie is an opaque random identifier.
The browser keeps only the CSRF value and one-time copied key display in memory.

One Durable Object routes all admin sessions consistently. While sessions are
active, a 30-second cleanup timer retains RAM and purges expired sessions; it stops
when no sessions remain. Cloudflare deployments/runtime restarts can clear sessions,
so sign in again if that happens. The site and Supabase registry remain available
independently of this chat and the local development server. A new release resets
hosted sign-in sessions; it does not alter client keys.

## Resource and request controls

- Exact HTTPS origin, Host-equivalent URL validation, JSON/custom-header checks
  and CSRF for mutations. No cross-origin management API or framing.
- CSP, HSTS, no-store, noindex, nosniff and restrictive Permissions-Policy.
- 8 concurrent operations, 8 sessions, 8 KiB bodies, bounded upstream timeouts.
- Global portal budget of 120 API calls/minute, 3 email sends/10 minutes and
  20 code verifications/10 minutes, in addition to Supabase/management limits.
- Only three aggregate quota records persist in the Durable Object; counters
  survive restarts and overwrite expired windows. Denied requests do not append
  records or repeatedly write an already exhausted counter. No emails, IPs,
  browsing events, JWTs or key plaintext are stored in those records.
- No polling, PCC download, scheduler, or background network request is added.
  The only timer purges bounded server memory. Cloudflare enforces its Free-plan CPU limit; custom CPU settings are omitted
  because they require a paid plan.

The static assets directory contains only index.html, app.js and style.css. Build
output, local `.env`, `.dev.vars`, `.wrangler` state and dependencies are ignored.
The pinned deployment/runtime tools are owned by this standalone backend package.

## Verification and final acceptance

Passed locally: 21 unit/security/UI tests; Deno type checks; Cloudflare dry-run
build; full workerd + SQLite runtime with mocked outbound Auth/API traffic. Runtime
checks cover secure cookies, non-owner denial, CSRF, alternate hosts, session loss
on restart and persistence of email quotas across runtime restarts. All automated
checks use fixtures and send no PCC, RMP or real email traffic.

Hosted verification passed: HTTPS page/assets and security headers; signed-out
session and 401 management denial; 403 cross-origin sign-in denial without email;
404 unknown route; browser checks at 390px and 1280px with no horizontal overflow
or JavaScript errors. The owner signed in and confirmed the same key list. The
verified local process on port 4178 was then stopped; the hosted page and session
API still returned HTTP 200. No localhost server or running chat is required.
No public website, source Worker, schedule synchronization or client was deployed.
The new worker name was confirmed absent before creation. A paid-only custom CPU
setting was rejected during the first attempt and removed; the successful deployment
uses Cloudflare Free defaults, with no plan upgrade.

## Recovery

Redeploy a tested revision of this hosted Worker while keeping its Durable Object
class and migration history. Deploying clears RAM sessions, so owners sign in
again. Shared keys/audit records remain in Supabase. For owner-account recovery,
use the private `npm run owner -- owner-add <verified-uuid>` command from the
[owner dashboard guide](owner-dashboard.md). Never put its machine credential in
the Cloudflare site, frontend assets, repository or browser.
