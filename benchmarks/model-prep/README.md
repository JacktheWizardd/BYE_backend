# BYE model preparation — October 11, 2026

This task downloads nine unproven candidates in twelve GGUF variants (11,949,057,632 bytes). It does not load a model, run inference, contact PCC/RMP, or change existing app releases. The mandatory eventual installed-app cap is strictly below 1,500,000,000 bytes; runtime memory and distribution archive sizes are separate. A weight file smaller than the cap does not establish full-app fit.

The pinned `manifest.json` contains exact publisher repositories, complete revisions, filenames, sizes, SHA-256 values, upstream identities, upstream metadata revisions, and license obligations. Upstream metadata revisions are **not** claimed as conversion-source revisions. Missing conversion provenance remains explicitly unverified. The selected variants use instruction/chat checkpoints; Gemma 270M and Granite 350M are experimental small candidates, and LFM Thinking is a distinct reasoning checkpoint from the rejected LFM Instruct model.

```sh
python3 -m unittest discover -s benchmarks/model-prep -v
python3 benchmarks/model-prep/prepare.py
python3 benchmarks/model-prep/finalize.py
```

The preparation command requires HTTPS access to Hugging Face and official license sites. It uses `/usr/bin/curl` with macOS certificate verification, disables user curl configuration, follows HTTPS redirects, transfers weights sequentially, and retries transient transfer failures at most twice. A `.part` file is retained on failure and resumed on a later invocation. Complete files are reused only after size/hash verification. Existing mismatched final files are preserved and reported as failures, never overwritten. Successful promotion uses an exclusive hard link to prevent overwriting a concurrently created destination. A process lock prevents overlapping preparation runs; after a crash, inspect the PID before manually removing a stale lock.

Weights go only to ignored `.build/bye-candidates-2026-10-11/<candidate-id>/`. Metadata, license/notice documents, commands, timings, errors, inventory Markdown/CSV/JSON, verbatim embedded chat templates, and preservation checks go to timestamped runs under ignored `.local-docs/model-prep-2026-10-11/`. `latest.json` identifies the last completed run. Do not commit weights or raw review data.

GGUF inspection reads metadata and the tensor directory without loading tensor data into an inference runtime. It records architecture, declared context limits, file quantization type, tokenizer type, token-array counts, special-token IDs, and exact embedded chat templates. A valid header and matching artifact hash do not certify runtime support, correct template rendering, or summary quality; task 2 must establish those.

The offline finalizer rechecks all twelve hashes, enriches the CSV with provenance, saves generated required notices and plain-text renderings alongside original license documents, reruns the small fixture tests, and hashes the complete evidence set. It preserves the initial derived report and records the final preparation-tool source. It does not make network requests.

Preservation checks distinguish immutable evidence/runtime/release files from externally mutable user caches. The download run uses a strict before/after comparison and records any discrepancy. The finalizer can report download readiness with documented user-cache changes, while retaining the original failed preservation result; immutable evidence changes still block readiness. It never restores or overwrites user caches.

Qwen, IBM Granite and H2O Danube use Apache-2.0 upstream licenses. Save the canonical Apache text when a repository omits a standalone license, together with the upstream card and all available notices. Llama 3.2 has license/NOTICE, acceptable-use, attribution, and commercial-threshold conditions. Gemma 3 has its own agreement, required Notice and enforceable use-restriction obligations. LFM has commercial revenue conditions; eligibility at the stated $10M threshold must not be assumed. Archived terms and document hashes are evidence, not a certification of production release eligibility. Missing or gated upstream documents are logged explicitly; public third-party GGUF files do not remove upstream obligations.

The old benchmark fetch script must not be used for this preparation: it would restore the three retired checkpoints. Their paths and hashes are checked separately. The existing llama.cpp runtime, retained benchmark/audit evidence, frozen corpus, caches, and release files are inventoried and checked without mutation.

Stop after download readiness. Model compatibility checks involving loading, offline generation, staged-app sizing, quality judgments, timing, memory and energy measurements belong to the next task.

For task 2, carry forward the [CPU-accounting erratum](../../docs/verification/bye-cpu-accounting-erratum-2026-10-11.md): the old benchmark sampler labels Mach CPU ticks as nanoseconds. Use calibrated accounting before interpreting its CPU-time results.
