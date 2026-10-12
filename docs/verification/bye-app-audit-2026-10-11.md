# BYE local app audit — October 11, 2026

The authorized corrected pilot finished with 19 paced requests, at least 2.0015 seconds between starts, one active request, and no observed HTTP failures. Four verified profiles yielded 104 source reviews but only 13 exact-course reviews; the six-profile target was not met. Existing development cases remain separate from new held-out evidence.

The instrumented live build reached 1.611 GB sampled RSS (1.615 GB wait4 peak), 1.184 GB sampled physical footprint, and 1.059-second main-thread scheduling delay. Offline cached searches had a 0.117-second median in the latest session. These are measurement-build results, with synchronous recording and bitmap overhead, not unrestricted production benchmarks. RSS and footprint must not be added. Energy per summary was unavailable.

Apple summary tests used three old cases, repeated three times in two offline sessions. All 18 completed, but 15 omitted recurring feedback; three generated “Tough grader” as a positive. Those three were saved but not displayed because no current scheduled instructor matched that case. Six other summaries had verified SwiftUI state observations. These are exploratory judgments, not independent error-rate estimates. No replacement model is release-approved.

The nine rejected model/GGUF-app/ZIP paths were removed (4,906,792,950 logical bytes). Retained runtime, benchmark logs, licenses, caches, and releases matched their pre-cleanup hashes: 1,543 files. Existing releases were not replaced. The mandatory future bundle limit is installed `.app` below 1,500,000,000 bytes; runtime memory and archive size are separate.

The first pilot failed to collect reviews because of POST-body forwarding. A subsequent UI-tool relaunch produced unmetered startup traffic, so an aggregate request total across all attempts cannot be proven. The corrected pilot had separate explicit authorization. Malformed audit startup now exits before constructing network clients. The report preserves both failures and corrections. Both offline sessions denied app networking at the OS level and recorded zero external transport requests.

Final validation: 39 targeted tests passed, optimized audit and ordinary release builds passed, and malformed startup guards passed. The existing full WebKit suite stalled in the host sandbox and was not claimed as passing. CPU-accounting limitations and corrections are recorded in [the erratum](bye-cpu-accounting-erratum-2026-10-11.md).

Reproducible tooling: [app-audit README](../../benchmarks/app-audit/README.md). Complete local report and raw audit evidence are in ignored `.local-docs/app-audit-2026-10-11/REPORT.md`, with resource/request/timing CSVs, quality judgments, frozen corpus, expected facts, retrieval provenance, checksums, build/test logs, and source snapshot. Raw review text must remain local and untracked.
