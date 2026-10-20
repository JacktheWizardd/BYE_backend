# BYE cross-platform beta

Separate Electron/React/TypeScript application. The Swift application continues to be the Mac-focused build. This release targets Windows 11 x64; no Mac package of this application is claimed or included.

Version `0.4.0-beta.1` follows the Mac 0.4.0-beta.1 release: the BYE design system (ivory and stone grounds, Jet Black type, yellow only for the wordmark, rating bars and progress meter, Libre Baskerville headings), neutral results that open on a course overview, class cards with seats, waitlist, campus, term part and units, the class-day and fully online filters, six review sorts, and a "Write a review" link to the BYE website. The screens mirror `Sources/Classwise/Views`; shared rules mirror `Sources/ClasswiseCore/Models.swift`. In-app updates (Sparkle on the Mac) are not part of the Windows build.

## v3 redesign (in progress, 2026-10-19)

The renderer now follows the approved playful v3 design (see [UI parity](../../docs/UI_PARITY.md) and the [mockup](../../docs/design/app-mockup-v3.html)):
- **First run:** a welcome screen and "What should we call you?" next to a live student ID card. The name stays on this PC.
- **Frame:** a sidebar with Search (Ctrl K), Home, Your classes (up to five, removable) and your profile.
- **Home:** search-first.
- **Results:** "I'm free" day bubbles, a sliding segmented sort and a sliding selection.
- **Professor page and menus:** a professor page in the sticker style, a command menu, and a Settings sheet (name, updates, about).

How it's built:
- **Shared code:** tokens, domain helpers and shared React screens are copied from the website repository into `vendor/bye-shared/` by `node ../../scripts/sync-bye-shared.mjs`. `vendor/bye-shared/SOURCE.json` names the website commit. Don't edit `vendor/`; change the website, commit, then sync.
- **App-only screens** are in `src/renderer/src/app/`.
- **Preferences** (name, first-run flag, recent classes) are saved through the separate `window.byeApp` bridge to `%LOCALAPPDATA%\BYECrossPlatformBeta\settings.json`; `src/main/settings.ts` validates every update.
- **Update check:** "Check for updates" asks only `https://bye-before-you-enroll.pages.dev/windows/latest.json`, only when pressed, and opens only links on the BYE website. Nothing is installed automatically.

## Run the Windows ZIP

Extract **all** files, then open `BYE/BYE.exe`. Keep the supporting files beside the executable. No installer, administrator access, Node, Swift, Python, or Ollama is required. Version `0.4.0-beta.1` omits GGUF model weights to reduce download and disk size.

**AI summaries are temporarily disabled in this Windows build.** Automatic generation, the summary button, cached-summary display and backend inference requests are disabled. The implementation, runtime dependencies, model metadata, credits, development model files and existing local summary caches are retained. One policy, `src/shared/features.json`, controls TypeScript and packaging. `resources/build-info.json` records each package's version, AI status and weight inclusion. Previously published ZIPs retain their original behavior; native Mac AI is unchanged.

PCC schedules and RMP retrieval require internet. Ratings and original reviews remain available. Preferences, raw profile caches, manual choices, and evidence-scoped summaries live separately under `%LOCALAPPDATA%\BYECrossPlatformBeta`. Replacing the extracted application folder preserves that data. Mac data is never imported. This is an unsigned beta with manual updates.

## Development on Windows x64

Use Node 24 LTS (or Node 22.16+), npm, and PowerShell:

```powershell
cd apps/cross-platform
npm ci
npm run runtime:fetch
npm run dev
```

The explicit runtime fetch is a development setup step. Disabled builds do not require `model:fetch` or any local weights. The retained enabled packaging path verifies the pinned model's revision, file size and SHA-256 and includes its weights. Native CPU dependencies remain packaged; runtime compilation is disabled. Dependencies and overrides are pinned in the lockfile.

```powershell
npm run typecheck
npm test
npm run ai:verify
npm run build
npm run ui:verify:offline
npm run perf:verify:offline
npm run package:win
npm run verify:zip
```

Outputs are at the repository root under `dist/`. Packaging produces `BYE-CrossPlatform-0.4.0-beta.1-windows-x64.zip` and `.zip.sha256` and refuses to overwrite either. Every build gets a separate staging directory. ZIP verification extracts to a path containing spaces and Unicode, checks the embedded package policy, model inclusion, checksum, structure and privacy. An optional ZIP path can be passed to `verify:zip`; verification follows that package's metadata. Test results are ignored under `test-results/`. No upload, tag, auto-update service, or signing certificate is configured.

For staging before compression, build first and run `node scripts/package.mjs --stage-only`. `node scripts/package.mjs --reuse-stage <staging-folder>` accepts only a package whose embedded version and policy match the built source. Rebuild staging whenever application code changes. Required node-llama-cpp metadata stays in ASAR; native CPU libraries stay outside it. Disabled requests stop before model verification or AI imports.

The offline commands build and use the production startup, Engine, renderer, preload, IPC validation and security settings with injected local fixture services. They use saved schedule rows with fictional instructor profiles/reviews, isolated storage and blocked network access. Fixtures and generated entrypoints/reports are excluded from release packages. Performance verification runs three fresh processes with one initial and twenty warm searches each, samples the complete Electron process tree, and checks both peak RSS and private memory against **1,500,000,000 bytes**. Warm report-loading P95 is informational. The under-three-second **AI** P95 requirement remains unverified while summaries are disabled. Sampling limitations and hardware are recorded in each local report.

`live:verify`, `ui:verify` and `packaged:verify` are separate, explicitly live PCC/RMP checks. They are excluded from the offline acceptance sequence above.

## Architecture and behavior

- `src/shared` contains domain types, course equivalence, schedule grouping, identity matching, filters, and sorting.
- Electron main owns direct API requests, bounded queues, atomic persistence, and CPU inference. Renderer commands are validated and exposed only through the typed preload bridge. The renderer is sandboxed, context-isolated, and has no Node access. Original reviews are rendered as text.
- PCC suggestions/search share a five-minute schedule cache. RMP uses a two-request transport gate, 100 ms spacing, bounded retries/cooldowns, no cookies or redirects, and a 4 MiB response limit. Profile IDs, names, and PCC identity are checked on each page.
- Ambiguity always requires selection. Manual preferences are isolated by instructor/subject and reverified on fresh retrieval. Preview, detail, and summary queues remain independent; queued optional jobs yield to previews. Cancellation and identity/evidence checks guard publication and cache writes.
- Raw caches and summaries last 24 hours. Summaries also depend on provider/policy identity, course, profile, and exact whole-review evidence. Stable review IDs alone do not permit reuse after text changes.
- The retained local AI implementation uses a non-thinking Qwen chat template with JSON grammar and distinct supplied source-ID pairs. Whole recent reviews fit within the evidence budget. Conservative corroboration/sentiment checks can omit useful feedback and do not prove general semantic correctness. Generation is currently disabled before model verification or runtime loading.

See [verification results and limitations](VERIFICATION.md).
