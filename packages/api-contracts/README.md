# Frontend API contracts

Backend-owned, versioned public contract artifact for the shared React/Tauri trial.
`src/api.ts`, `types.ts` and `reviews.ts` preserve the existing web/review response
shapes. `schedule.openapi.json` pins the independently deployed schedule API's
checked-in v1 schema. This package neither deploys nor changes those services.

Export an intentional snapshot from this repository:

```sh
node packages/api-contracts/export.mjs ../BYE_website/packages/api-contracts
node packages/api-contracts/export.mjs ../BYE_website/packages/api-contracts --check
```

The frontend works independently after export. `SOURCE.json` records exact
SHA-256 identities of canonical LF text, not a claim that uncommitted work is deployed. Newer local
multi-term schedule work remains a separate workstream; update the schema snapshot
only when that work has been reviewed and its contract verified. The existing
Swift/Windows apps, browser deployments, migrations and release assets are unchanged.
