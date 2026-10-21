# BYE task 2 — sequential offline model evaluation

**Experiment status: stopped by the user after observed quality failures.** The
256-token development matrix completed; the 384-token comparison is partial.
Held-out inference and the remaining integration/energy phases did not run.
Commands below describe the tooling, not authorization to restart this experiment.
See the [experiment record](../../docs/history/experiments/2026-10-11-local-summarization/README.md)
for completed work, limitations, and the commit scope.

The real-review corpus and source-linked `expected-facts.json` are intentionally
local and ignored by Git. A fresh clone can run the small fixture tests, but cannot
reproduce the real-data experiment without separately supplied local evidence.

This runner consumes the twelve verified artifacts in `benchmarks/model-prep/manifest.json`. It has no download path and never calls PCC/RMP. Each runnable variant receives the complete comparison matrix, one loaded model and one generation request at a time. No production release is replaced.

```sh
python3 -m unittest discover -s benchmarks/model-eval -v
python3 benchmarks/model-eval/run.py prepare
python3 benchmarks/model-eval/run.py preflight
python3 benchmarks/model-eval/run.py run
python3 benchmarks/model-eval/run.py report
python3 benchmarks/model-eval/analyze.py
python3 benchmarks/model-eval/review.py export
python3 benchmarks/model-eval/review.py show --count 12
python3 benchmarks/model-eval/review.py inherit
python3 benchmarks/model-eval/review.py aggregate
python3 benchmarks/model-eval/report.py
```

`prepare` refuses an existing run directory. Other actions use the run recorded in ignored `.local-docs/model-eval-2026-10-11/latest.json`, or an explicit `--run`. A filesystem lock prevents two evaluation controllers from running together. macOS must allow execution of the instrumented native binaries and `sandbox-exec`; the OS profile still denies external networking. The Python controller additionally rejects non-loopback socket connections. Record a successful external-TCP-denial fixture and the runner tests before `run`. No certificate, access-control or model license bypass is involved.

## Evidence and matrix

Frozen source: seven development professor/course cases, four held-out cases, twelve original fictional cases, two added synthetic abstention/duplicate cases, and complete real/synthetic long-source banks. Original review text, IDs, labels and source manifests stay in ignored storage. The development fact annotations are source-reviewed before inference; existing held-out annotations are retained. They are exploratory agent judgments, not independent human validation.

Ordinary real cases use a common whole-review prefix of at most six reviews. Synthetic cases retain their entire fixture where every tokenizer/pipeline can fit it. Evidence is identical between variants and ordinary 2048/4096-context trials. Near-limit prefixes are selected jointly across compatible tokenizers and both pipelines; achieved token counts, not nominal characters, define utilization. Full long sources are evaluated through model-specific whole-review chunk boundaries, whose differences are recorded. No review text is cut to make an input fit. A single oversized review or reduction is rejected explicitly.

Both direct and extraction/reduction pipelines run three rounds at both context sizes. Variant order rotates by four positions per round. Final output is 256 tokens; intermediate extraction is 512. If any development final output hits its ceiling, all variants receive a separately labeled 384-token final-output matrix before held-out testing. LFM Thinking receives a separate 1024-token final-generation-budget experiment; it has no embedded `enable_thinking` switch. Extra budgets do not replace or improve the reported baseline retroactively.

The prompts/settings and expected facts are frozen before replacement-model generation. Held-out trials run only after development and the budget decision; no held-out output is used for tuning. Keep deterministic repeats as performance/reproducibility measurements, not independent evidence of general accuracy.

The first development-only pilot is retained separately. Its excessive quotations frequently exhausted the output budget. The comparison restarts all twelve variants with a common compact-v2 contract: overview at most 24 words/180 characters, points at most 10 words/96 characters, extraction observations at most 14 words/140 characters. No held-out output existed at refinement. Source selection reserves 384 tokens for direct output and 512 for extraction. Both output-budget matrices use the same frozen evidence. Reduction includes the original source ledger and model-generated observations; any resulting overflow is rejected explicitly and is not a completed summary.

The LFM 1024-token supplement removes JSON grammar so natural reasoning can be observed. Save reasoning verbatim, and judge the separately extracted final answer against original sources. Its larger total allowance is not an identical-budget baseline.

## Measurements

The fixed b11559 runtime uses four threads, one slot, full supported Metal offload, batch 512/microbatch128, greedy decoding, seed42, disabled prompt caching, no context shifting and no startup inference warmup. The exact embedded template is rendered by the runtime; tokenization parses its special tokens without adding another BOS. Actual runtime prompt counts are compared with preflight counts. Filesystem cache state is uncontrolled; fresh processes are not claimed disk-cold.

The C sampler uses the corrected Mach timebase and validates CPU time against `getrusage`. Sampling is 100ms. RSS, physical footprint, lifetime footprint and exit-time peak RSS are separate figures. Allocation logs do not get added to them. App, host and helper samples may overlap in shared mappings and do not establish unique unified-memory consumption. CPU seconds are activity, not battery joules.

The fixed five-summary workload repeats in three rounds per variant. `powermetrics` permission failures are retained and energy counters are labeled unavailable. System-wide energy, when available, cannot be uniquely assigned to BYE. Power source/mode, swap, pressure and background processes are captured. The optional read-only observer records competing workloads without stopping apps.

The native harness links the actual unchanged `SummaryBuilder.validate`. The `BYE_MODEL_EVAL` Swift compilation flag adds an isolated `SummaryProvider` and drives the actual BYE SwiftUI views using labeled fictional fixtures. Normal builds retain existing defaults. Programmatic view/model actions, main-thread scheduling delay and app-owned view snapshots are proxies; none is hardware input-to-compositor latency. The measurement controller demonstrates 30-second idle unloading; it is not a production implementation of provider lifecycle ownership.

The final UI build is compiled only after inference and fixed-workload energy runs, then staged in separate APFS clones. Its signed binary identity, source, whole-app and ZIP sizes are recorded separately from original prototype bundles. Actual focused text editing and scroll bounds are logged; an unavailable editor or nonmoving scroll view is a shortfall rather than a passed interaction test.

## Preservation and interpretation

Weights remain in `.build/bye-candidates-2026-10-11/`. Staging apps/archives and compiler products are isolated in `.build/bye-model-eval-2026-10-11/`. Each app has cloned weights, bundled runtime, notices and native payload. Logical installed bytes must be strictly below 1,500,000,000; ZIP, allocated-disk bytes and runtime memory are separate. Logical sizes exclude symbolic-link target duplication; APFS allocated blocks are not unique physical allocation estimates.

Every stage saves raw output before validation, streamed events, inputs, token IDs, stop reasons, commands and timestamps. Checkpoints prevent overwriting completed stages. Failures remain failures, not automatic inference retries. A resumed pipeline reconstructed from stage checkpoints is labeled and excluded from latency aggregates where controller overhead cannot be recovered.

JSON validity and citation membership do not prove that sources support a paraphrase. Score raw claims and actual displayed output separately, including sentiment, coverage, independence, attribution, conflicts and readability. Blinded review exports and manual decisions must remain tied to exact hashes. Never promote the automatically generated timing report into a quality certification. No release model is selected while semantic review or required integration checks are incomplete.

Full-claim support is strict: a source saying “messages” does not establish “email,” and praise for examples does not establish “real-world examples” or a comparative “strongest” ranking. A compound point earns priority-theme coverage only when its complete cited claim is supported. Diagnostic error counts describe reviewed error groups, not an exhaustive atomic-claim factuality percentage. Display-detail supplements keep original judgments intact and bind overrides to the same output and evidence hashes. The long synthetic bank has frozen qualitative checks, not post-hoc numeric priority-theme annotations; its missing themes and duplicate corroboration are judged qualitatively.

`review.py inherit` reuses a manual judgment only when parsed answer, original evidence, display, extraction and structural results are identical; JSON whitespace and citation order may differ. Each inherited decision keeps its own output/evidence hashes and identifies the original review. Model/pipeline/context/budget configurations are scored separately. Unreviewed packets remain pending and cannot pass.

`analyze.py` reports stage metrics and per-case repeat statistics. Only first inference in a process can have observed startup-inclusive latency; adding loading time to a warm request is labeled as a hypothetical sum. Power/thermal telemetry began partway through the first revised development round, and unobserved intervals remain labeled. A charger transition occurred during that round; power cohorts must be separated in interpretation.

The old runner is left for historical reproduction; never invoke its `fetch` action, which restores retired models. Its CPU conversion bug is fixed for future invocations, while historical CSVs and the published erratum remain unchanged.
