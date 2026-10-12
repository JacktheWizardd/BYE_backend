# BYE bounded collection and performance audit

This tooling stages an optimized native measurement app separately from `dist` and user caches. Instrumentation compiles only with `BYE_AUDIT`. The live session authorized on October 11 is finished; these commands do **not** authorize another live run.

All raw source text, HTTP recordings, outputs, screenshots, and measurements belong in ignored `.local-docs/app-audit-2026-10-11`. Never commit those files. The dated paths are intentional so this audit remains separate from later experiments. Preserve failed attempts as well as successful runs.

```sh
# Build only; no PCC/RMP requests.
python3 benchmarks/app-audit/run.py stage

# Mocked gate, transport and app-model tests; no live services.
CLASSWISE_TEST_FILTER='ClasswiseCoreTests.CollectionGateTests,BYEAPITests.RMPClientTests,ClasswiseAppTests.AppModelTests' ./scripts/swift.sh test -Xswiftc -DBYE_AUDIT

# New offline session; refuses to overwrite existing events.
# Uses recorded PCC responses and previously used development reviews.
python3 benchmarks/app-audit/run.py offline --session-name offline-next --apple

# Rebuild derived reports; does not fetch data.
python3 benchmarks/app-audit/verify.py
python3 benchmarks/app-audit/report.py
```

The runner uses macOS `sandbox-exec` to deny external networking for offline runs, as well as a recording-only transport with no fallback. The app needs normal macOS launch access. The measurement app refuses startup without a valid `--audit-session` argument. Do not reopen it through Finder or UI automation after it exits; use the runner. A normal build has no audit entry point.

For a separately authorized future live session, `run.py live --session-name UNIQUE --maximum-requests 40 --duration 300` supplies the injected policy. The app bounds settings to at most 40 requests and 300 seconds, one active PCC/RMP request, and at least two seconds between starts. Startup and pagination count. Automatic RMP retries are disabled, redirects are refused, and rate limits, access denial, repeated server/GraphQL failures, transport errors, and the deadline stop collection. Limits are per process, so a new live process requires a new authorization. Do not extend an expired session automatically.

`manage.py cleanup DIRECTORY` is deliberately restricted to the nine rejected `.build/bye-benchmark/{lfm,qwen,smol}.{gguf,app,zip}` paths and refuses a second cleanup record. It inventories retained evidence before deletion and preserves the runtime, tools, results, caches, and existing releases. It has already run for this audit.

`resources.c` samples the app every 500 ms. It reports RSS and physical footprint separately and converts Mach CPU ticks using the machine timebase. Run its compiled executable with `--self-test` to compare CPU accounting against `getrusage`. Old files are retained unchanged; see [CPU accounting erratum](../../docs/verification/bye-cpu-accounting-erratum-2026-10-11.md).

The report distinguishes live pacing, server work, warm-cache timing, next-main-turn observation, and UI state observation. Neither scheduling delay nor an NSView bitmap measures input-to-pixel latency. Shared Apple inference-service memory and energy cannot be assigned entirely to BYE. CPU time is not battery energy. Instrumentation adds overhead, especially when recording large schedules and capturing view bitmaps.

The current report includes the initial POST-body forwarding failure, incomplete preview observations, and the first Apple display-harness failure. Repeated Apple outputs are exploratory semantic judgments, not independent human evaluation or a production reliability result. No replacement model has been downloaded or approved.
