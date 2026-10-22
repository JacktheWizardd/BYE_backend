# Backend migration boundary

This first milestone establishes backend-owned public contracts and an explicit
versioned frontend snapshot. It changes no server behavior or deployment identity.
The repository root now provides a private pnpm workspace for `packages/*`, with
contract typechecking and explicit snapshot check/export commands. The schedule
service and legacy apps retain their independent tooling.
The shared React/Tauri trial is implemented in BYE_website; Electron has no role
in the target architecture. Existing SwiftUI/Windows apps remain available.

After actual Windows and Mac preview acceptance, move website API implementation,
source Worker, tests and deployment tooling here. Planned backend destinations
are `services/web-api/` for website API logic and `services/source-worker/` for the existing source Worker;
neither directory has been created or populated. Keep only same-origin forwarding
functions in the frontend, using service bindings. Preserve service names, URLs,
Durable Objects, databases, migrations, review cookies/origins/auth, rate limits,
status/error shapes and independent review/schedule service boundaries. Verify
staging and a tested rollback before requesting production cutover authorization.

No implementation moves occur yet: real Mac acceptance and comparative performance
are pending. Desktop PR #8 and newer local schedule integrations remain separate.
No release, merge, deployment, legacy deletion or data import is part of this change.
