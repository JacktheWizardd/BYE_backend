# Developer setup and workflow

This is the working guide for authorized contributors to the private BYE source repository. The root [README](../README.md) provides the overview; [Project Status](PROJECT_STATUS.md) documents verified behavior and current blockers.

## Prerequisites

**Native macOS track:** macOS with Xcode, command-line tools, and an SDK compatible with the checked-in Swift package. The native app package targets macOS 14+, and current distribution builds target Apple Silicon. Use the repository's wrapper script, which selects the Xcode toolchain and keeps SwiftPM caches within the repository.

**Windows/Electron track:** Windows x64, PowerShell, Node 24 LTS (or Node 22.16+), and npm. Its app and dependencies are separate from the Swift package.

Access to the private GitHub repository is required to clone it. No Supabase credentials are required to work on the current native app.

## Native Mac development

From the repository root:

~~~sh
./scripts/swift.sh build
./scripts/swift.sh test
./scripts/build-test-app.sh
~~~

- `scripts/swift.sh` wraps the Swift toolchain and local cache/test configuration; prefer it to a bare `swift` invocation.
- `scripts/build-test-app.sh` compiles a release-configured local test bundle at `test/BYE Test.app`. The generated app is **not tracked**.
- Open the generated app manually to exercise the UI. Rebuild it after changes to native functionality.
- Do not run packaging, signing, notarization, or publishing as part of ordinary iteration. Refer to [Releasing](RELEASING.md) for those gated operations.

If tests or builds fail due to missing macOS SDK/toolchain support, record the toolchain version and full error before changing build settings.

## Windows/Electron development

From the repository root:

~~~powershell
cd apps/cross-platform
npm ci
npm run runtime:fetch
npm run dev
~~~

Run checks from the same application directory:

~~~powershell
npm run typecheck
npm test
npm run build
npm run ui:verify:offline
npm run perf:verify:offline
~~~

The explicit runtime fetch is a setup operation. AI summary behavior is currently disabled in the Windows beta. Read [the app-specific instructions](../apps/cross-platform/README.md) for additional checks, environment constraints, and packaging.

## Branches and pull requests

- Start from an up-to-date `main`; name branches for the change (for example, `feature/course-filters`, `fix/profile-selection`, or `developer-docs`).
- Keep unrelated experiments and platform-specific work in separate branches.
- Make focused commits with a summary of behavior and the reason for the change.
- Run relevant tests and document evidence/limitations in the pull request.
- Review changes before merging. Do not commit generated builds, temporary evidence, personal caches, or credentials.

The `docs/` folder already contains historical experiments and verification records. Preserve them rather than rewriting history to make failed approaches appear successful.

## Configuration and secrets

The current checked-in applications make direct PCC and RMP requests; **Supabase is only planned**. Do not add a hosted database credential to a desktop app or commit it to the repository.

- Use environment variables or a local ignored secrets file if future services require credentials.
- Put public/client-safe and privileged/service-role credentials in distinct locations; service-role secrets must stay on a trusted backend.
- Confirm the ignore rules before adding new generated directories. The root `.gitignore` excludes `.build/`, `dist/`, app bundles, local records, model weights, and common caches.
- Use test/synthetic data for documentation, fixtures, and screenshots unless there is explicit authorization for other data.

## When changing external integrations

Changes involving the PCC source, RMP, or future hosted services should document upstream terms/permissions, caching policy, failure recovery, schema changes, rate limits, and privacy implications. Start with [API and integrations](api.md) and [Database plans](database.md).

## Release workflow

Do not infer published status from a prepared beta version, a local DMG, or prerelease notes. The release procedure is a separate, reviewed workflow in [Releasing](RELEASING.md); the current technical handoff is in [Project Status](PROJECT_STATUS.md).
