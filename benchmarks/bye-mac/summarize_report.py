#!/usr/bin/env python3
"""Build the final comparison from measured artifacts and persisted semantic review."""
import json
import statistics as s
from pathlib import Path
import benchmark as b

BASE=b.ROOT/'docs/verification'
baseline=BASE/'bye-local-2026-10-11'
plain=BASE/'bye-local-plain-2026-10-11'
review=BASE/'bye-local-review-2026-10-11'
rows=json.loads((plain/'results.json').read_text())
peaks=json.loads((plain/'memory-peaks.json').read_text())
sizes=json.loads((b.HERE/'sizes.json').read_text())
corpus=json.loads((plain/'corpus.json').read_text())
short_names={c['name'] for c in corpus['cases']}
names={'lfm':'LFM2.5-1.2B Q4_K_M','qwen':'Qwen3.5-0.8B Q4_0','smol':'SmolLM2-360M Q4_K_M'}
lines=['# BYE local model comparison — October 11, 2026','',
       '**Recommendation: ship none of these three yet under the tested prompts.** All fit the installed-size requirement and respond quickly on this Mac, but each has material quality failures. LFM is the most useful next candidate for summary-specific prompt/quality work; SmolLM2 is the smallest, but its low latency mostly measures copying rather than useful summarization. This is an exploratory recommendation, not a claim that any model passed a release quality standard.',
       '', '## Host, artifacts, and scope','',
       '- Apple M5 MacBook Pro, 10 CPU cores (4 performance + 6 efficiency), 10 GPU cores, 16 GB unified RAM, macOS 26.6.2 (25G83), Xcode 27.0. AC power; Low Power Mode off. Native host thermal state remained nominal in recorded runs.',
       '- llama.cpp b11559, commit `f2cc7282ce0042641df55e0e563b75e824e2b647`. Archive SHA-256 and GGUF identities are in the [manifest](../../../benchmarks/bye-mac/manifest.json). All downloaded artifact hashes matched publisher metadata.',
       '- Metal verified in diagnostic logs: Apple M5 selected, all supported layers offloaded, embedded Metal library enabled. Runtime executable and Metal dylib declare macOS 13.3 minimum; this does not substitute for testing earlier OS/hardware. Only this M5 was benchmarked.',
       '- 300 primary summaries: 138 JSON-input baseline and 162 shared plain-text trial. Each primary short/long test has three identical-output repeats; plain-text chunk pipelines also repeat three times. Eighteen additional timing calibrations include rendering/tokenization overhead. All sources are explicitly fictional; no live professor reviews were used.',
       '- No production provider, existing release, or published package was changed. Staging apps include the existing BYE UI payload but launch a measurement host. This is a packaging prototype, not a release-ready integrated app.',
       '', '## Performance and installed size','',
       'The following latency figures use the plain-text trial, a 2,048-token context, 256-token output ceiling, four inference threads, full Metal offload, greedy decoding, and zero prompt-cache tokens. One request and one model run at a time. Short results pool twelve cases across three rounds; durations vary with actual output length.',
       '', '| Model | Installed staging app MB | ZIP MB | Short request median (range), s | First content median, s | Prompt tok/s | Output tok/s |',
       '|---|---:|---:|---:|---:|---:|---:|']
for key in names:
    a=[r for r in rows if r['model']==key and r['case'] in short_names]; z=next(x for x in sizes if x['model']==key)
    times=[x['seconds'] for x in a]
    lines.append(f"| {names[key]} | {z['staged_app_bytes']/1e6:.1f} | {z['archive_bytes']/1e6:.1f} | {s.median(times):.3f} ({min(times):.3f}–{max(times):.3f}) | {s.median(x['first_token_seconds'] for x in a):.3f} | {s.median(x['timings']['prompt_per_second'] for x in a):.0f} | {s.median(x['timings']['predicted_per_second'] for x in a):.0f} |")
lines+=['', '**Mandatory:** installed logical app bytes <1,500,000,000. All staging apps pass. Size includes weights, native host, runtime directory, notices, and existing BYE payload. Distribution size and runtime memory are independent measurements. Production packaging may remove unused runtime tools after dependency checks.',
        '', '| Model | First observed process readiness, s | Later fresh-process readiness range, s | 4,096-context long summary median, s | Chunk + reduction median, s |',
        '|---|---:|---:|---:|---:|']
for key in names:
    starts=[json.loads((baseline/f'round{i}-{key}-2048/startup.json').read_text())['seconds'] for i in [1,2,3]]
    a=[x for x in rows if x['model']==key]
    lines.append(f"| {names[key]} | {starts[0]:.3f} | {min(starts[1:]):.3f}–{max(starts[1:]):.3f} | {s.median(x['seconds'] for x in a if x['case']=='long_4096'):.3f} | {s.median(x['pipeline_seconds'] for x in a if x['case']=='chunk_reduction'):.3f} |")
lines+=['', 'Readiness includes native host, dynamic-library loading, model/context setup and health polling, with runtime warmup disabled. First launches are not proven disk-cold: OS file caches, loader validation and Metal caches were uncontrolled. Do not equate readiness with GGUF disk-read time. Generation first-token timing includes prefill and local streaming transport. Main request timing excludes template rendering/token-count preflight; the calibration below includes those steps.',
        '', '| Model | Short total summary median, s | Long 2,048-context total median, s | Template/token-count preflight median, ms |',
        '|---|---:|---:|---:|']
cal=json.loads((BASE/'bye-local-total-time-2026-10-11/results.json').read_text())
for key in names:
    a=[x for x in cal if x['model']==key]
    lines.append(f"| {names[key]} | {s.median(x['total_summary_seconds'] for x in a if x['case']=='repeated_positives'):.3f} | {s.median(x['total_summary_seconds'] for x in a if x['case']=='long_2048'):.3f} | {s.median(x['preflight_seconds'] for x in a)*1000:.2f} |")
lines+=['', 'Long tests use the same 33-review source at 2,048 context and 75-review source at 4,096 context. Baseline input counts are 1,696/1,744/1,742 tokens and 3,686/3,807/3,805 tokens for LFM/Qwen/Smol respectively (see raw files for exact counts). Each reserves 256 output tokens. Oversized inputs were explicitly rejected for all three. Chunk tests split 99 reviews into three whole-review chunks and reduce generated summaries; their timing includes every stage and preflight.',
        '', '## Memory and power','',
        '| Model | Runtime lifetime peak RSS GB | Runtime lifetime peak footprint GB | Max sampled host + helper footprint GB |',
        '|---|---:|---:|---:|']
for key in names:
    a=[p for p in peaks if '-'+key+'-' in p['run']]
    lines.append(f"| {names[key]} | {max(p['runtime_lifetime_peak_rss'] or 0 for p in a)/1e9:.3f} | {max(p['runtime_lifetime_peak_footprint'] for p in a)/1e9:.3f} | {max(p['summed_process_peak_footprints'] for p in a)/1e9:.3f} |")
lines+=['', 'RSS includes resident memory-mapped weights; physical footprint uses different macOS accounting and can be much smaller. Lifetime RSS comes from macOS child resource usage; lifetime footprint comes from `proc_pid_rusage`. Sampled host/helper sums may double-count shared pages and do not establish unique whole-system unified-memory use. Metal mapped model buffers, KV/recurrent state and compute allocations are logged separately; none are added to RSS/footprint. Full production BYE UI/browser activity was not running, so whole-product peak memory remains unmeasured.',
        '', '`powermetrics` required superuser access and was unavailable. There are no measured joules, watts, or battery-impact rankings. Raw logs retain runtime CPU nanoseconds, power configuration, memory pressure, swap and background process snapshots. CPU time is only an activity proxy. AC charging results cannot establish unplugged battery drain.',
        '', '## Quality findings','',
        '- **LFM:** readable and concise, particularly on long reviews, but baseline treats duplicate copies as independent cost complaints and incorporates injected instructions as evidence. Plain-text trial fabricates negative experiences, reverses untimed-quiz anxiety evidence, and misattributes late feedback to late submissions. Long summaries omit important sides of pace/deadline/feedback conflicts.',
        '- **Qwen:** fluent but frequently adds explanations absent from the sources, including underfunding, student retention and learning-level mismatch. Plain-text trial reverses quiz/stress evidence, misattributes courses, invents insufficient example depth and treats agreeing reports as contradictory.',
        '- **SmolLM2:** smallest and fastest but baseline echoes JSON. Plain-text trial mainly lists paraphrased reviews, fails duplicate handling and does not produce a useful synthesis. Long outputs and reductions truncate; plain reductions loop a heading.',
        '- Repeated source text, conflicts, negation, sparse evidence, course attribution and prompt injection all have explicit fixture checks. Raw and displayed outputs differ only by trimming whitespace. No grammar, validator, or claimed factuality filter hides failures.',
        '- [Per-case judgments and rubric](../bye-local-review-2026-10-11/RUBRIC.md), [quality CSV](../bye-local-review-2026-10-11/quality.csv), and [anonymized output packet](../bye-local-review-2026-10-11/anonymized-outputs.json) are saved. This is agent review, not an independent blinded human assessment. Numerical scores are exploratory; no new release pass threshold was imposed.',
        '', '## Validation and redistribution','',
        '- All three complete fresh-process inference with empty HOME/model caches and OS-enforced denied network access. All reject missing or malformed model files. Downloaded GGUFs are also SHA-256 verified.',
        '- Initial active-stream shutdown could stall. Closing the client response before terminating the helper fixed it: all three cancellation retests passed in about 0.05–0.09 seconds. Partial output is discarded. Both original failures and [corrected checks](../bye-local-validation-fixed-2026-10-11/results.json) are preserved.',
        '- Qwen and upstream SmolLM2 declare Apache-2.0; llama.cpp is MIT. Include license/copyright notices, applicable NOTICE files and modification notices. GGUF provenance, snapshots and hashes are saved; license snapshots were retrieved from upstream and preserved locally.',
        '- LFM uses the [LFM Open License](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct/blob/main/LICENSE), including redistribution conditions and commercial revenue limits. Its definition says $10M annual revenue or more, while section 5 uses exceeds/exceeding. Do not assume boundary eligibility. BYE commercial eligibility was not supplied or certified; confirm it or obtain a separate license before commercial distribution.',
        '', '## Practical native bundling plan','',
        '1. Keep the current production provider unchanged until a candidate has an agreed factual-quality gate and a broader corpus. Next test LFM with compact evidence-only prompts and explicit duplication preprocessing; preserve the current regressions. If failures persist, expand candidates rather than ship a misleading smaller model.',
        '2. Implement a `LlamaSummaryProvider` conforming to the existing `SummaryProvider`. Use a dedicated actor with one active generation, immutable model/prompt/cache identity, bounded context, whole-review evidence selection, cancellation checks before publication, and no automatic inference retry that could publish stale evidence.',
        '3. Prefer linking the pinned llama C API through a small Swift/C bridge to avoid shipping an HTTP server. Bundle the winning GGUF, required ARM64 libraries/embedded Metal kernels, manifest and notices inside app resources/frameworks. Verify checksums during packaging and on initial model validation. Sign nested binaries, sign the app, then notarize the final distribution. Test a clean offline install on every supported deployment target.',
        '4. Load lazily on the first explicit summary request. Keep one context while active; unload model/context after 60 seconds idle, on memory pressure or when leaving the workflow. Preserve deterministic ratings/reviews and a clear unavailable state when weights are missing/corrupt or no supported summary exists. No runtime/model download path, Apple Intelligence setup dependency, API key, or separate user software is required.',
        '5. Map supported evidence into the existing `ReviewSummary` interface. Use model-generated prose or structured points only after source-attribution validation; lexical agreement alone is not a semantic proof. Deduplicate by stable review identity before prompting. Preserve opposing reports rather than majority-voting them away. For oversized input, test chunking/reduction against original evidence before enabling it; current reduction failures make automatic release unsuitable.',
        '6. If a helper process is retained instead, use a private local IPC channel, close active client streams on cancellation before stopping the helper, and measure BYE UI plus helper together. Add foreground responsiveness, native UI memory, plugged/unplugged energy, Intel policy, and earlier-Apple-Silicon coverage before release. No model is currently selected for this production work.',
        '', '## Reproduce and inspect','',
        'See [benchmark instructions](../../../benchmarks/bye-mac/README.md). Runtime/model downloads and staging apps are under ignored `.build/bye-benchmark`; raw benchmark evidence is under the neighboring verification directories. `benchmark.py report` rebuilds timing tables, `review.py` persists reviewed judgments, and `summarize_report.py` rebuilds this comparison. Existing result directories are never overwritten.',
        '', 'Limits: one M5 machine; fictional and intentionally repetitive long sources; greedy decoding only; two prompt formats; no independent human review; no unique whole-system memory or energy measurement; no integrated production-provider UI test. These results describe these artifact revisions and settings, not all possible prompts or model capabilities.']
(review/'REPORT.md').write_text('\n'.join(lines)+'\n')
