# Lightweight model selection — October 15, 2026

Isolated research for BYE. No production integration and no PCC/RMP collection.
The seven development and fourteen synthetic cases come from the saved corpus.
The original four held-out professors are excluded from inference.

## Reproduction

Use Python 3.12 and the experiment's isolated environment. Exact installed
versions are preserved in the private `resolved-requirements.txt`; key versions
are also in `requirements.txt`. Run model workloads sequentially.

1. `python3 benchmarks/lightweight-selection/fetch.py metadata`
2. `python3 benchmarks/lightweight-selection/run.py prepare`
3. For each ID in `manifest.json`, run `fetch.py download --model ID`.
4. Run `run.py screen --model ID` with GPU access. The inherited server runs
   under a macOS sandbox that denies external network access; the controller
   also rejects non-loopback connections.
5. Run the experiment Python with `train.py --model ID` under
   `sandbox-exec -p '(version 1)(allow default)(deny network*)'`.
6. Run `run.py diagnostics --model ID` for empty evidence, cancellation, long
   inputs and deliberately forced whole-review overflow.
7. Source-review every output and bind judgments to its output/evidence hashes.

Preparation and completed runs refuse overwrite. Use a new dated experiment
directory for a new protocol; do not overwrite preserved evidence. A failed
screen can only be archived automatically when it generated no case outputs.

## Frozen comparison

All baseline inference uses Q8_0 GGUF, the existing llama.cpp b11559 Metal
runtime, 8,192 context tokens, 512 output tokens, and the earlier revised shared
paragraph prompt. Greedy decoding and non-thinking mode are fixed. These are
untuned baselines; the MLX feasibility adapters are never used in screening.
Publisher/third-party GGUF conversions and native training weights are separate
artifacts; matching upstream conversion revisions are not assumed.

Training uses native publisher weights and ten Adam steps: batch one, seed 42,
learning rate 0.0001, rank eight, scale 16, dropout zero, and adapters on supported
linear layers of the last four blocks. All 39 old training pairs are checked for
template masking and the 2,048-token cap. The same ten shuffled pairs are used
for each model; no truncation is permitted. The test checks finite loss,
changed adapter weights, saving, and reloaded logits. It is neither a quality
comparison of trained models nor a convergence experiment.

Current model implementations, operator support, templates, licenses and exact
artifacts are checked separately. Incompatibility is recorded rather than
silently substituting a runtime or model.

## Measurements and records

Private records live in `.local-docs/lightweight-selection-2026-10-15/`;
downloads and adapters in `.build/bye-lightweight-selection-2026-10-15/`.
Full reviews, model paragraphs, source IDs, output hashes and review judgments
remain local. No model or review upload is part of this experiment.

Record startup including integrity verification, loaded request completion,
100 ms process RSS/footprint samples, MLX allocator peak, and global memory/swap
snapshots. Fresh processes do not imply disk-cold filesystem caches. Diagnostic
timings exclude native UI overhead and do not establish a reliable ten-second
success rate. GPU allocator bytes and process RSS are distinct measurements.

Run focused checks with:

`python3 -m unittest discover -s benchmarks/lightweight-selection -v`

The reused paragraph runner additionally has seventeen existing tests covering
source filtering, duplicates, chunking, and hash-bound quality gates.
