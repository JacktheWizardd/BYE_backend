# Frontend API contracts

Backend-owned, versioned public contract artifact for the shared React/Tauri trial.
`src/api.ts`, `types.ts` and `reviews.ts` preserve the existing web/review response
shapes. `schedule.openapi.json` pins the independently deployed schedule API's
checked-in v1 schema. This package neither deploys nor changes those services.

From the repository root, use Node 22.16+, pnpm 11.25.0 and the pinned TypeScript
5.9.3 toolchain:

```sh
pnpm install --frozen-lockfile
pnpm typecheck
pnpm contracts:check ../BYE_website/packages/api-contracts
```

`contracts:check` is read-only and requires the explicit frontend contracts
directory. For differently named worktrees, pass their real paths. Neither
repository imports runtime code from the other checkout. The root workspace
covers `packages/*` only; the schedule service retains its own npm workflow and
Node 24.3+ requirement.

Export an intentional snapshot only when a contract update is intended:

```sh
pnpm contracts:export ../BYE_website/packages/api-contracts
```

The underlying commands remain available without pnpm:

```sh
node packages/api-contracts/export.mjs ../BYE_website/packages/api-contracts
node packages/api-contracts/export.mjs ../BYE_website/packages/api-contracts --check
```

The frontend works independently after export. `SOURCE.json` records exact
SHA-256 identities of canonical LF text, not a claim that uncommitted work is deployed. Newer local
multi-term schedule work remains a separate workstream; update the schema snapshot
only when that work has been reviewed and its contract verified. The existing
Swift/Windows apps, browser deployments, migrations and release assets are unchanged.
