# CPU accounting erratum — October 11, 2026

The original `benchmarks/bye-mac/memory.c` and the initial app-audit sampler wrote `proc_pid_rusage` CPU counters directly into columns named `runtime_cpu_ns` or `cpu_ns`. On this Apple M5, those counters are Mach ticks. The measured timebase is **125/3 nanoseconds per tick**. CPU seconds derived by dividing the original counters by one billion are therefore understated by a factor of about 41.667.

Original benchmark CSVs and reports are preserved unchanged for auditability. Treat their CPU percentages or CPU-time energy proxies as invalid unless recalibrated. This correction does not change wall-clock timing, output quality, RSS, physical footprint, or the decision to reject the three tested models. CPU time, including corrected CPU time, does not establish battery energy per summary.

The app-audit sampler now converts ticks at capture. Its `--self-test` compared 0.062556667 seconds of converted process CPU with 0.062555000 seconds from `getrusage` (difference 0.000001667 seconds). Calibration and self-test records are saved in ignored `.local-docs/app-audit-2026-10-11/`. Derived `resources-calibrated.csv` files correct the initial app-audit CPU counters while retaining the raw files. Legacy event/sample clock alignment is approximate because the original sampler used `CLOCK_MONOTONIC` and app events used system uptime.
