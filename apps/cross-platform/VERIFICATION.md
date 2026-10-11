# Windows beta verification

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
