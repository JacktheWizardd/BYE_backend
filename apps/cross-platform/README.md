# BYE cross-platform beta

Separate Electron/React/TypeScript application. The Swift application continues to be the Mac-focused build. This release targets Windows 11 x64; no Mac package of this application is claimed or included.

## Run the Windows ZIP

Extract **all** files, then open `BYE/BYE.exe`. Keep the supporting files beside the executable. No installer, administrator access, Node, Swift, Python, or Ollama is required. The Qwen3-4B Q4_K_M model is included, so the ZIP is several gigabytes. 16 GB RAM is recommended for CPU inference; a dedicated GPU is unnecessary.

PCC schedules and RMP retrieval require internet. Summaries run locally using already retrieved reviews. Ratings remain usable when AI fails. Preferences, raw profile caches, manual choices, and evidence-scoped summaries live separately under `%LOCALAPPDATA%\BYECrossPlatformBeta`. Replacing the extracted application folder preserves that data. Mac data is never imported. This is an unsigned beta with manual updates.

## Development on Windows x64

Use Node 24 LTS (or Node 22.16+), npm, and PowerShell:

```powershell
cd apps/cross-platform
npm ci
npm run runtime:fetch
npm run model:fetch
npm run dev
```

The explicit runtime/model fetch commands are development build steps. Release users do not download runtimes or models. The model is pinned by official revision, file size, and SHA-256; the build refuses an incomplete or altered file. Native CPU binaries ship with the app and runtime compilation is disabled. Dependencies and overrides are pinned in the lockfile.

```powershell
npm run typecheck
npm test
npm run ai:verify
npm run live:verify
npm run build
npm run ui:verify
npm run package:win
npm run verify:zip
npm run packaged:verify
```

Outputs are at the repository root under `dist/`. Packaging produces `BYE-CrossPlatform-0.1.0-beta.1-windows-x64.zip` and `.zip.sha256`. Every build gets a separate staging directory. ZIP verification extracts to a path containing spaces and Unicode; packaged verification launches that extracted executable using isolated user data. Test results and screenshots are ignored under `test-results/`. No upload, tag, auto-update service, or signing certificate is configured.

For staged acceptance before compression, run `node scripts/package.mjs --stage-only`, then `npm run packaged:verify -- <staged-BYE-folder>`. After successful checks, `node scripts/package.mjs --reuse-stage <staging-folder>` packages that exact executable. Rebuild the staging folder whenever application code changes. Required node-llama-cpp metadata stays in ASAR; native CPU libraries stay outside it. AI imports happen only when a summary is requested, so inference initialization failures remain recoverable.

## Architecture and behavior

- `src/shared` contains domain types, course equivalence, schedule grouping, identity matching, filters, and sorting.
- Electron main owns direct API requests, bounded queues, atomic persistence, and CPU inference. Renderer commands are validated and exposed only through the typed preload bridge. The renderer is sandboxed, context-isolated, and has no Node access. Original reviews are rendered as text.
- PCC suggestions/search share a five-minute schedule cache. RMP uses a two-request transport gate, 100 ms spacing, bounded retries/cooldowns, no cookies or redirects, and a 4 MiB response limit. Profile IDs, names, and PCC identity are checked on each page.
- Ambiguity always requires selection. Manual preferences are isolated by instructor/subject and reverified on fresh retrieval. Preview, detail, and summary queues remain independent; queued optional jobs yield to previews. Cancellation and identity/evidence checks guard publication and cache writes.
- Raw caches and summaries last 24 hours. Summaries also depend on provider/policy identity, course, profile, and exact whole-review evidence. Stable review IDs alone do not permit reuse after text changes.
- Local AI uses a non-thinking Qwen chat template with JSON grammar and distinct supplied source-ID pairs. Whole recent reviews fit within the evidence budget. Conservative corroboration/sentiment checks reject unsupported observations, and the overview uses accepted themes only. These checks can omit useful feedback and do not prove general semantic correctness.

See [verification results and limitations](VERIFICATION.md).
