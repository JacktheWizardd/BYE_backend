# Working alongside another agent (Claude Code + Codex)

Claude Code and Codex may both be working in this checkout at the same time. They coordinate through
`scripts/agents.py`, which keeps a shared board in the git-ignored `.agents/` folder. Use your own name
(`claude` or `codex`) in every command.

- **Before starting a task**, run `python3 -I scripts/agents.py inbox <you>` to see what the other agent did
  and is doing. Then claim the work with
  `python3 -I scripts/agents.py start <you> "short task description" --files <paths you expect to edit>`.
  If it prints a WARNING that the other agent holds one of those files, don't edit that file. Pick other
  work, or log a `note` and wait.
- **While working**, log meaningful progress with `python3 -I scripts/agents.py update <you> "what changed"`.
  Use `blocked <you> "what you need"` when waiting, and `note <you> "message"` to tell the other agent something.
- **When finished**, run `python3 -I scripts/agents.py done <you> "summary, tests run"`. This releases your files.
- `python3 -I scripts/agents.py status` shows both agents and the last 15 events.
- Claude Code does some of this automatically through hooks in `.claude/settings.json`: it reads its inbox on
  every prompt and logs each file it edits. Codex runs the commands above by hand, at the start and end of each task.
- Never edit, delete or reset `.agents/` by hand, and never revert the other agent's uncommitted changes.
- In temporary worktrees, coordinate through the existing board in the original `BYE_Before_You_Enroll` checkout rather than creating a separate worktree board.

# Local Mac testing workflow

- After completing native Mac app changes, run `./scripts/build-test-app.sh` to update `test/BYE Test.app` with the latest source.
- The user opens the visible `test` folder to test development builds. Use this stable app location when sharing the latest build.
- Relaunch the updated test app after finishing Mac development so the user can test immediately. Close an older running BYE development instance first.
- Keep generated test apps out of Git. This workflow is local testing; publishing requires a separate user request.

# Commit handoff preference

- Whenever double-checking changes or preparing/completing a commit, always
  provide a ready-to-paste **Summary** and **Description** for GitHub Desktop.
- Base both on the actual reviewed changes. Include verification results and
  material remaining limitations in the description; distinguish checks run now
  from earlier recorded verification.
- State whether changes were committed or remain uncommitted. Preparing a
  handoff does not by itself request a Git commit or push.

# Backend workspace and repository ownership

- This repository owns backend contracts, the schedule service and its owner dashboard, and database migration records. Website API/source implementations remain in `BYE_website` until desktop acceptance; future destinations here are `services/web-api/` and `services/source-worker/`. Those directories are not implemented yet.
- New shared frontend work belongs in `BYE_website` (`packages/app`, `apps/preview`, `apps/desktop`, UI/core/tokens and client adapters). Keep retained SwiftUI/Electron code and release tooling here intact; Electron is legacy only.
- The root pnpm workspace covers only `packages/*`, currently `packages/api-contracts`. Use Node 22.16+, pnpm 11.25.0, `pnpm install --frozen-lockfile` and `pnpm typecheck`. TypeScript is pinned to 5.9.3.
- Run `pnpm contracts:check <explicit-frontend-contract-directory>` to verify an existing snapshot without writing it. `pnpm contracts:export <explicit-frontend-contract-directory>` intentionally writes a snapshot; do not run it as a routine check. Runtime code must not import from a sibling checkout.
- `services/schedule-api/` is outside this workspace and retains npm, its own lockfile and Node 24.3+ requirement. Root typecheck does not verify that service, Swift or Electron. Read [the repository map](docs/REPOSITORY_MAP.md) before changing ownership or paths.
- **2026-10-21 structure preparation:** Backend root contract tooling and frontend/backend ownership guides are prepared locally. No API implementation, Worker, migration, service identity or release asset was relocated. Desktop acceptance and subsequent staging/rollback remain prerequisites for relocation/cutover.

# Area guides

- The browser app migrated to `../BYE_website/apps/web/`; read that repository’s `AGENTS.md` and `apps/web/AGENTS.md`. The old `apps/web/README.md` is a migration pointer; its older area guide is historical.
- The website lives in a separate repository (`../BYE_website`) with its own `AGENTS.md`.


<!-- BEGIN shared development policy: 2026-10-19 -->
## Development roles and shared quality rules

These rules apply to websites, web apps, desktop applications and mobile
applications where present. They add to the existing project and area guides;
preserve specific product constraints, workflows and release gates. They do not
authorize a redesign, platform port, feature rollout or infrastructure change.
Current explicit user instructions take precedence over these role preferences.

### Preferred responsibilities

- **Codex is the preferred backend, systems, API, database and security engineer.**
  Lead service architecture, domain logic, persistence, authentication and
  authorization, validation, migrations, reliability, performance profiling and
  security review, including local native-app systems and desktop IPC.
- **Claude Code is the preferred frontend, UI and UX engineer.** Lead interface
  design and implementation, navigation, layout, styling, interaction, motion,
  accessibility and visual polish across web, desktop and mobile interfaces.
- These are defaults, not exclusive ownership or a claim about model ability.
  Either agent may complete an explicitly assigned task across the stack, fix a
  nearby integration issue, write tests or review the other's work. Do not stall
  a task solely because the preferred agent is unavailable. Seek a second review
  for security-sensitive or cross-boundary work when available; never imply that
  a review happened without evidence.

### Preserve behavior and integration contracts

- Read the applicable instructions and current code before editing. Preserve
  working behavior, approved designs, user data, privacy promises, feature flags,
  release assets and existing tests. Keep changes focused; avoid unrelated
  refactors, dependency upgrades and speculative abstractions.
- Agree on shared types, API routes, request/response fields, errors, auth rules
  and loading/empty/offline states before parallel frontend/backend work. Preserve
  compatibility across browser, native and Electron clients. For a necessary
  breaking change, document the migration and coordinate consumers and contract
  tests before integration; never silently change a shared contract.
- Prefer the simplest maintainable solution using the existing stack. Favor
  local/offline operation and existing free-tier services where suitable. Bound
  requests, retries, polling, storage and background work. Explain recurring
  costs, quotas and tradeoffs before adding services; obtain explicit approval
  before enabling paid resources. Cost savings must not weaken security or
  correctness.

### Platform quality, accessibility and security

- Web: responsive, mobile-first layouts; semantic HTML, keyboard operation,
  visible focus, screen-reader labels, readable contrast, usable touch targets,
  reduced motion and clear loading/error/empty states. Check supported browsers
  and small/large viewports; preserve demo disclosures and noindex gates.
- Desktop/native: follow platform conventions for windows, menus, shortcuts,
  focus, accessibility, permissions and lifecycle. Keep UI work responsive; bound
  CPU, memory and background/network use. Preserve update/signing behavior and
  Electron process/IPC security boundaries.
- Mobile, when implemented: respect safe areas, system back gestures, touch
  targets, text scaling, screen readers, app lifecycle and intermittent networks;
  avoid unnecessary battery use. Prefer platform-appropriate behavior over
  forcing identical interactions everywhere. Do not introduce new platforms
  solely to satisfy this policy.
- Validate at trust boundaries and enforce authorization server-side or at the
  appropriate native boundary. Use least privilege, safe queries and secure
  session/secret storage. Never expose privileged keys in clients or commit
  credentials, private signing material, personal data or sensitive logs.

### Cooperation, verification and authorization

- Use the existing shared coordination board before editing; respect file claims
  and record meaningful progress and handoffs. Parallel work requires disjoint
  file ownership or an agreed handoff. Preserve other agents' and the user's
  uncommitted work; never reset, stash, clean, overwrite or revert it to make your
  task easier. Re-read files and review the diff before integrating changes.
- Run the existing checks appropriate to the changed area. Add meaningful
  regression tests for behavior changes and contract/security tests for relevant
  boundaries. Verify UI changes visually and with accessibility interactions.
  Report checks actually run, failures and untested platforms honestly. For
  instruction-only edits, inspect content, imports, scope and diffs; app builds
  and native test-app relaunches are unnecessary unless runtime code changes.
- **Obtain explicit user authorization covering each commit, push, deployment,
  release or destructive action before performing it.** Preparing changes or a
  commit message is not authorization to execute those actions. A push that
  triggers deployment also needs authorization for that deployment. Destructive
  actions include deleting data, resetting work, rewriting history and applying
  destructive migrations. Explain scope, impact and recovery before approval.
  Respect authorization already given for the specific action; do not infer it
  from a general request to develop or test.
- Finish with changed files, verification and limitations, plus separate
  ready-to-paste GitHub Desktop Summary and Description for each changed
  repository. Leave changes uncommitted unless explicitly authorized otherwise.
<!-- END shared development policy -->
