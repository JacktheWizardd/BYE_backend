# Windows beta verification

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
