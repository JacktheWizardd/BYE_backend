# Commit handoff: hosted owner dashboard and API records

This guide describes the current pending change group, rather than earlier PCC,
Windows or website commits. The API foundation and registry scaffold already
exist in Git; the current diff finalizes hosted administration, hardens its UI/
retry handling, adds tests, and organizes the delivery records.

Deployment and source control are separate. The Cloudflare dashboard is already
live and was verified; this documentation pass has not staged, committed or
pushed anything. The owner normally commits through GitHub Desktop.

## What belongs together

- The standalone Cloudflare admin Worker/session handler and deployment configuration.
- Its pinned Wrangler/Miniflare dependencies and lockfile updates.
- In-page Rotate, Extend and Revoke forms, plus clearer replacement names.
- The twenty-four-hour mutation retry window and matching dashboard/database tests.
- Local, hosted, UI and runtime security regression coverage.
- The API documentation, plain-language records, handoff and repository index links.

The expected scope is `services/schedule-api/` and `docs/README.md`. Confirm the
actual GitHub Desktop file list before selecting changes; preserve any unrelated
work. Do not include `.env`, `.dev.vars`, OAuth credentials, `.wrangler` state,
node_modules, generated bundles, raw PCC captures or one-time key plaintext.
The genuine Supabase publishable Auth key in Cloudflare configuration is public
configuration, not a database or administration credential.

## Verification to describe accurately

Recorded implementation checks passed: 21 offline tests, Deno type checks,
Cloudflare build and full runtime tests; earlier key-management checks include
22 database scenarios and eight hosted schedule checks. The owner tested the key
lifecycle, then signed in on the hosted site. HTTPS/security and phone/desktop
browser checks passed, and the hosted site worked after localhost was stopped.

For this documentation pass, check local links, content consistency, whitespace
and Git exclusions. Do not describe earlier code/live checks as newly rerun just
because the documentation was edited. No new app build or PCC traffic is needed.
The [verification report](verification.md) retains dated evidence and limitations.

## Ready-to-paste text

**Summary**

Finalize hosted BYE key management and document the delivery

**Description**

Add a separate Cloudflare owner dashboard with secure server-memory sessions,
opaque cookies and bounded rate limits. Fix unsupported browser prompts, make
key selection clearer, and bound mutation retries to prevent duplicate creation.
Add security/UI/runtime regressions and pinned deployment tools.

Organize readable delivery records, design decisions, owner/developer handoff,
operations and verification guides. Record the successful owner lifecycle test,
hosted sign-in and operation with localhost stopped on Cloudflare Free.

Implementation verification: 21 offline tests, Deno checks and full Cloudflare
runtime tests pass; 22 database and eight hosted schedule scenarios were recorded
in the earlier key-management checks. Documentation links, consistency, whitespace
and exclusions were reviewed separately. Client integration and automatic
replacement-key delivery remain future work. The public BYE website and existing
review behavior are unchanged.

**Commit status:** uncommitted; no staging, commit or push performed by this pass.
