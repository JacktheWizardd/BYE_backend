# BYE native Mac local-model benchmark

Run from the repository root on an Apple Silicon Mac with Xcode command-line tools and Python 3.12+:

```sh
sh scripts/benchmark-bye-mac.sh fetch
sh scripts/benchmark-bye-mac.sh prepare
sh scripts/benchmark-bye-mac.sh run --output docs/verification/bye-local-2026-10-11
sh scripts/benchmark-bye-mac.sh tune --output docs/verification/bye-local-plain-2026-10-11
python3 benchmarks/bye-mac/validate.py --output docs/verification/bye-local-validation-fixed-2026-10-11
python3 benchmarks/bye-mac/calibrate.py
python3 benchmarks/bye-mac/review.py
python3 benchmarks/bye-mac/summarize_report.py
```

`fetch` requires GitHub/Hugging Face network access. All inference uses local paths with llama.cpp offline mode. `prepare` verifies every artifact hash, compiles the Swift host and C memory sampler, creates signed staging apps and ZIPs in `.build/bye-benchmark`, and freezes the corpus. It includes the existing local `dist/BYE Apple AI Beta.app` payload when available, recording the original executable hash. The staging app launches the measurement host; the existing BYE UI is included for sizing but its production summary provider is not changed. ZIPs and model weights are not committed. Existing release apps are never modified.

The pinned release archive contains the Metal backend. Runtime logs and `/props` record the embedded chat template, allocations, supported features, and effective settings. Keep this runtime build fixed throughout comparison. No automatic quantization substitutions are made.

## Measurements

- One request at a time; model order rotates between three rounds. Four CPU threads, full Metal offload, flash attention enabled, 512 batch / 128 microbatch, greedy sampling, seed 42, no repetition penalty, 256 output-token ceiling. A shorter EOS is allowed.
- Prompts are rendered using the GGUF chat template with thinking disabled, tokenized before inference, and rejected if input plus output reservation exceeds context. Every request disables prompt caching. Identical source text can have different token counts across models.
- Readiness includes host startup and model/context initialization; llama.cpp logs separately expose internal loading. `--no-warmup` makes first inference observable. Requests after the first reuse loaded weights. Fresh processes do not establish a disk-cold cache; no system cache purges are performed.
- SSE arrival time measures first nonempty content latency, including local HTTP transport. Total request timing excludes prompt-template preflight. Chunk pipeline timing includes every chunk, reduction, and preflight.
- `proc_pid_rusage` samples resident size, physical footprint, lifetime maximum footprint, and CPU time every 50 ms. The native host records the helper's lifetime peak RSS through `getrusage(RUSAGE_CHILDREN)` after exit (macOS reports bytes). Summed host/helper footprint is a process-accounting proxy; shared mappings may overlap. It is not a unique whole-system unified-memory total. Never add Metal allocation logs to RSS/footprint.
- Environment captures power settings, thermal state, processes, swap, and memory pressure. `powermetrics` failures remain in raw logs. CPU seconds are an activity proxy, not joules or battery drain. No power settings are changed.

The twelve short cases and all long input sources are fictional. Long source selection reserves 256 output tokens and chooses a whole-review prefix that fits every model. Chunking uses that common 2,048-context prefix length. The long source bank is intentionally repetitive and conflicting, not a substitute for a broad real-world corpus.

Raw responses, SSE events, rendered prompts, settings, per-process memory samples, server logs, and environment snapshots are saved under the specified output directory. Existing output directories are refused. `report` rebuilds performance CSV/Markdown from saved results. Manual semantic evaluation and the final recommendation are separate from automated timing aggregation.

`tune` is the shared plain-text follow-up trial. It reuses baseline long-source selections and must run after the baseline. `validate.py` enforces denied network access using macOS sandbox-exec, tests missing/malformed GGUFs, and closes an active response stream before terminating the native helper. `calibrate.py` adds three rotated repeats of short and long inputs including rendering/tokenization overhead. Its output path is fixed; retain/rename existing evidence before a fresh experiment. `review.py` contains persisted agent judgments tied to exact output hashes, not an automatic factuality judge; changed outputs require a new semantic review before reusing those judgments. The final report generator targets this dated experiment.

## Distribution

The mandatory cap is installed logical app bytes <1,500,000,000. ZIP bytes and runtime memory are separate. `sizes.json` measures real staging apps including weights, runtime, notices, native host, and available BYE payload. This benchmark retains the release runtime directory conservatively; production can remove unused tools after dependency verification.

License copies are included. Apache-2.0 requires the license, preserved attribution and any applicable NOTICE, plus modification notices where relevant. llama.cpp is MIT. Liquid's LFM Open License has additional commercial revenue conditions: its definition includes annual revenue of $10M or more, while section 5 uses “exceeding”/“exceeds”; do not assume eligibility at the boundary. Commercial release needs confirmation of BYE's eligibility or a separate license. Benchmarking does not certify distribution eligibility.

No production integration or publication is performed by these tools.

## Existing local RMP cache experiment

`local_rmp.py snapshot`, `local_rmp.py run`, and `local_rmp.py long384` use only existing local Classwise/BYE report caches and downloaded model artifacts. They have no fetch path. The native host/helper is sandboxed to localhost-only networking; the Python controller also refuses external socket connections. Original app caches are read, hashed and left unchanged. Results, source snapshots and profiler logs are saved under ignored `.local-docs/rmp-benchmark-2026-10-11`; real review text is not added to tracked benchmark fixtures.

This experiment tests compact cited overview/positive/concern JSON with the same input per model, seven short cases and two longer cases, three rotated sequential repeats, then a matched 384-token long-output follow-up. `local_rmp_report.py` renders exact outputs and persists agent semantic findings. Its judgments apply only to the reviewed hashes; changed inputs or outputs require fresh review. Existing experiment directories are refused; retain prior evidence before creating another dated experiment. No PCC or RMP endpoint is contacted.
