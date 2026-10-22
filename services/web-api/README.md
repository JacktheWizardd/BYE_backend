# Prepared backend relocation

This private Worker owns the relocated review and source API implementation.
Production still runs the website checkout's Pages implementation until explicit
Worker deployment, bindings and frontend cutover approval. Git commits/merges do
not install Supabase SQL. BYE student numbers separately require 007 and owner
reservation; private verification migrations remain deferred.

From the backend repository root:

```sh
corepack pnpm install --frozen-lockfile
corepack pnpm typecheck
corepack pnpm test
corepack pnpm build:check
corepack pnpm test:runtime /absolute/path/to/BYE_frontend_relocation
```

Build checks are Wrangler dry-runs. Runtime checks use fixtures, SQLite and workerd
locally; the review test explicitly compiles the supplied frontend Pages functions
and binds WEB_API to this Worker. The argument must name the relocation checkout
containing `platform/forward.ts`, not the live website main checkout. Ordinary
runtime code does not import from a sibling checkout. Neither command contacts
real Supabase, sends mail, or fetches real PCC/RMP data.

`pnpm dev:fixtures` is loopback-only fictional data. `pnpm verify:pcc` is a separate
real-source probe and is not part of these offline checks. Worker configs keep
public Worker URLs disabled. Production deployment and source activation require
separate authorization; do not enable Turnstile for native OTP sign-in.

Source lineage and adapted paths are in `docs/backend-relocation-provenance.json`.
