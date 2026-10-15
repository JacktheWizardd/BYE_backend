# Testing and verification

Use these commands for **local engineering checks**, not as proof that a build has been published. The historical record of results, constraints, and unverified behavior is in [Project Status](PROJECT_STATUS.md) and `docs/verification/`.

## Native macOS

From the repository root with Xcode/macOS SDK configured:

~~~sh
./scripts/swift.sh build
./scripts/swift.sh test
./scripts/build-test-app.sh
~~~

The wrapper configures the project's SwiftPM toolchain/caches and XCTest handling. The last command prepares `test/BYE Test.app`; **manually launch and inspect** it if the change affects UI or network interactions. It does not publish an app, and the generated bundle is ignored.

Focus regressions on:

- Course aliases, official catalog resolution, term and section matching.
- Meeting-day filters, course sections, and UI/window lifecycle.
- RMP profile identity, explicit ambiguity selection, and no cross-profile mixing.
- Retrieval timeouts, bounded retries, cancellation, partial data, caching, and refresh.
- Disabled AI-summary behavior and preservation of saved user data.
- Sparkle initialization only in correctly configured distribution builds.

Test totals in older verification reports are historical; do not restate them as results for a new commit without rerunning checks.

## Windows/Electron

From `apps/cross-platform/`:

~~~powershell
npm ci
npm run runtime:fetch
npm run typecheck
npm test
npm run build
npm run ui:verify:offline
npm run perf:verify:offline
~~~

Offline UI/performance checks use injected fixtures and blocked network access. They exercise different assumptions than live requests. See [Windows README](../apps/cross-platform/README.md) and [its verification notes](../apps/cross-platform/VERIFICATION.md) for setup and known limitations.

The following are **separate live or packaged checks**, not interchangeable with the offline sequence:

~~~powershell
npm run live:verify
npm run ui:verify
npm run packaged:verify
~~~

Only perform live network verification when the external-service impact is justified and permitted. Observe upstream request limits and record network failures rather than concealing them.

## Packaging and release checks

Distribution requires additional architecture, integrity, signature, privacy, and update testing. Do not run a release/publishing workflow as the default test for a documentation or implementation change.

For the Mac update feed, key handling, packaging, local update tests, and website publication, follow [Releasing](RELEASING.md). Existing reference evidence includes `docs/verification/updater-beta5-2026-10-14.json`. Packaged Windows ZIP validation is documented in the cross-platform README.

## Experimental AI and performance records

Historical local summarization trials, benchmark input boundaries, test fixtures, and stopped runs are retained under:

- [Local summarization experiment](experiments/2026-10-11-local-summarization/README.md)
- [Results](experiments/2026-10-11-local-summarization/RESULTS.md)
- [Model verification record](verification/bye-model-evaluation-2026-10-11.md)
- [App audit](verification/bye-app-audit-2026-10-11.md)

A test that completed does not establish summary quality. Distinguish offline/synthetic tests, live data checks, and end-user verification.

## Recording evidence in a pull request

Include the changed platform/component, exact commands run, result, environment/toolchain, relevant failure logs with private details redacted, and what was **not tested**. For network, privacy, and release changes, note the source, date, conditions, and any unverified assumptions.

Do not commit raw student reviews, private user caches, credentials, model weights, machine-specific paths, or full unredacted logs. Use synthetic fixtures and existing privacy checks.
