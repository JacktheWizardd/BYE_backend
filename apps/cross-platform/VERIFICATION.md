# Windows beta verification

## Windows search and profile-dialog fixes — October 18, 2026

Fixed the disappearing exact-course suggestion: `MATH 005A` stays visible while typing, and `math 005a`, `math 5a`, and `MATH5A` resolve to the official course. `005B` remains separate. Selection, Escape, blur and submission dismiss suggestions; editing reopens them. Responses from old queries, semesters or dismissed requests cannot reopen or replace the current list.

Profile dialogs now open only through an explicit Choose profile or Change profile action. Concurrent background ambiguity, missing profiles, retries and identity failures leave status on the cards without opening or queuing dialogs. One requested dialog owns focus; closing during discovery stays closed when results arrive. Loading, empty results, discovery failures and retries are shown in the requested dialog. Identity failures no longer incorrectly claim that multiple profiles exist. Existing saved choices, identity checks, IPC commands and cache formats are retained; the snapshot adds only an optional `discoveryLoading` field.

Verified on Windows x64: all **42 unit tests**, TypeScript checks and the production build pass. `npm run ui:verify:offline` passes against the production Engine, bridge, renderer and preload, with all network blocked. Added fictional MATH fixtures cover exact/shorthand suffixes, mouse and keyboard selection, delayed dismissal and old-query/semester responses, several ambiguous professors, no match, identity failure, empty/error/retry dialog states, refresh without dialogs, and search when suggestions fail. Existing professor switching, review filters/sorts, progressive reveal, cancellation, persisted manual choices and fresh-process restoration also pass. Screenshots of the exact suggestion, neutral MATH results and explicitly requested chooser were visually inspected. Evidence: ignored `test-results/offline-ui-ZjTsyh/report.json` and adjacent PNGs.

Local Windows x64 build staged at ignored `dist/cross-platform-build-qDD6n2/BYE/BYE.exe` using `node scripts/package.mjs --stage-only`. Embedded package policy/structure checks and privacy scans of the app and unpacked ASAR pass. No ZIP was published, and the staged production entrypoint was not launched because it requests live sources; UI acceptance above uses the built production code with injected fixtures.

The sandbox prevents Electron launch and some atomic rename operations in its temporary directory; the complete successful unit/UI checks ran outside the sandbox. No PCC/RMP test requests were sent. Live source availability, full Narrator/display-scaling acceptance, signing and clean-machine acceptance remain unverified. AI stays disabled. Mac and website sources were not changed. The shared agent-board script remains unavailable on Windows because it imports Unix-only `fcntl`; it was not modified.

## Windows 0.4.0-beta.1 — October 18, 2026

The renderer was rebuilt to match the Mac 0.4.0-beta.1 screens and the shared domain gained the Mac's section details, meeting places, class-day filter, format labels, six review sorts, preferred review filter, HTML-entity decoding and the BYE review link. The Electron main process opens the review link only from the current search's professor and course. Network, caching, identity, queue and AI-policy code is unchanged; summaries stay disabled.

Checked in a Linux development container, not on Windows: TypeScript checks, the production build and 37 regression tests pass, and the offline UI acceptance (`scripts/verify-offline.mjs` without the Windows-only guard, under Xvfb with Electron 44.7.0) passes every check: production bootstrap and isolation, search, professor switching, review filters and sorts, progressive reveal, profile chooser and saved choice, cancellation, hidden summary cache and fresh-process restoration, with no network requests.

Still to run on Windows before release: `perf:verify:offline`, `package:win`, `verify:zip`, and the live `ui:verify`/`packaged:verify` checks. The scripts were updated for the new screens (results open on a course overview, so each check opens a professor first) but have not been run on Windows yet.

## Windows 0.1.0-beta.2 baseline — October 10, 2026

AI summary generation is temporarily disabled in the renderer, summary engine and local provider. New packages omit GGUF weights and record their version, AI status and weight inclusion in `resources/build-info.json`. The implementation, runtime dependencies, model metadata, credits, development weights and existing local caches are retained. Native Mac AI and previously published releases are unchanged.

TypeScript checks, the production build and 35 regression tests pass. Coverage includes disabled requests, byte-preserved summary caches, packaging without weights, the retained enabled weight-integrity path, staging mismatches, embedded package metadata and overwrite refusal. `ai:verify` confirms direct calls stop before model verification or inference.

`ui:verify:offline` uses the shared production startup and real Engine with the built renderer/preload, unchanged command bridge, IPC validation and security settings. Saved schedule rows are paired with fictional instructor profiles/reviews. Search, professor switching and profile selection, review pagination, filtering, sorting, cancellation, and fresh-process cache restoration pass. Cached summaries remain stored but hidden. A fast warm-cache selection race was corrected so repeated searches keep a selected report. Storage is isolated and unexpected network access is blocked; no PCC/RMP requests were made. Fixture entrypoints and generated reports are excluded from release packages.

`perf:verify:offline` completed three fresh launches, one initial search and twenty warm searches per launch (60 warm). The sampler started before Electron and included main, renderer, GPU and utility processes, excluding the controller and monitor.

| Metric | Observed result |
|---|---:|
| Sampled whole-app peak RSS | 416,268,288 bytes |
| Sampled whole-app peak private memory | 276,307,968 bytes |
| Strict whole-app RAM threshold | < 1,500,000,000 bytes: **PASS** |
| Warm report-loading P95, nearest rank | 72.73 ms |
| Fresh-process launch to initial report | 558.16 / 545.50 / 527.34 ms |
| AI warm P95 < 3 seconds | **UNVERIFIED — summaries disabled** |

Hardware: Intel Core i7-12700KF, 20 logical CPUs, 17,006,034,944 bytes installed RAM; Windows 11 Pro 10.0.26200; Electron 44.7.0. Cold startup and first-search timings, all warm observations and raw memory samples are retained in ignored local reports. These are fixture measurements, not live-service latency. OS/filesystem caches were not flushed. Sampling targets 100 ms plus enumeration overhead and can miss short spikes or processes. Summed working sets can double-count shared pages; private memory is reported separately. Instrumentation can affect scheduling. Report loading includes IPC, cache/Engine work, React presentation and two browser frames; it does not establish AI speed.

ZIP verification checks SHA-256, extraction to a path containing spaces and Unicode, embedded policy agreement, required structure and runtime metadata, absence of GGUF weights, and privacy in extracted files and unpacked ASAR. The live PCC/RMP verification scripts are separate from this offline acceptance sequence.

## Earlier enabled-build verification

Verified on October 10, 2026, on the current Windows development host. The Swift Mac app is a separate product build.

- TypeScript checks and production build pass. All 29 regression tests pass, covering shorthand, identity ambiguity/recovery, transport bounds, cancellation, partial pagination, cache invalidation and stale results.
- Live PCC/RMP retrieval passed for Winter 2027 MATH 005A: eight sections, seven professors, three sampled verified profiles with three-review previews. The sequential sample retrieval took 2.27 seconds; this is not a full-course benchmark.
- Seventeen fictional embedded AI cases passed the acceptance assertions, including supported positives and concerns, disagreement, negation, isolated complaints and malicious review instructions. Generation was tested with network fetch disabled. Conservative evidence checks omit many themes; these cases do not establish general semantic correctness.
- CPU measurements: Intel Core i7-12700KF, 15.84 GiB installed memory, no inference GPU. First process summary including model integrity verification: 10.08 seconds; subsequent fictional cases: 3.96–5.26 seconds. Peak sampled inference-process RSS: 4.78 GiB. This is not whole-system peak memory or a minimum hardware specification; 16 GB RAM is recommended.
- Packaged BYE.exe launches, generates embedded summaries from whole course reviews (eight to ten in sampled runs), preserves original reviews and filters, and restores cached profiles/summaries after quit/relaunch. Missing and incomplete models were tested in the packaged executable: both show actionable summary errors while reviews remain usable. Runtime metadata is checked inside unpacked ASAR before ZIP creation. AI runtime initialization is deferred so a loading failure cannot crash startup.
- Renderer isolation, profile chooser dismissal, keyboard focus, reduced motion, 125% zoom and minimize/restore passed on the development host.
- Distribution privacy checks pass on application files, native binaries and unpacked ASAR. ZIP size is approximately 2.60 GB (2.42 GiB), including the 2,497,280,256-byte model. Exact release size and SHA-256 accompany the ZIP.
- Clean Windows 11 machine without development tools: not yet verified.
- Full Narrator session and all display scaling settings: not yet verified.
- Windows code signing: unsigned beta.
- Application-folder replacement with real user data, older/unsupported CPUs, and an offline full cold search are not verified. PCC/RMP retrieval needs internet; inference needs no remote service.

The bundled model is Qwen3-4B Q4_K_M, pinned in models/manifest.json. AI is experimental. No Mac build of this separate application is included.
