# Evidence-first text-summary pilots

Implements the research options from the user's Notion page, including the
explicitly requested fine-tuning pilot. Production app code is unchanged.

## Data and experiment boundaries

Only the frozen local October 11 corpus is read. No PCC/RMP collection code is
present. The original four held-out professor cases are never sent to a model.
Two development professors and eight fictional cases are training data; five
different development professors and six fictional challenge cases are evaluation
data. Outputs on the ten training cases are **fit diagnostics**, not independent
evaluation. Synthetic fixtures share vocabulary and are not a representative
sample of future reviews.

Private source annotations, training pairs, outputs, checkpoints and reviews remain
in ignored storage. `freeze.json` records source hashes, the professor-disjoint
split, settings and the limitations of teacher-derived targets. Source IDs, offsets,
complete quotes and hashes are retained. A fresh clone requires the private local
corpus and annotations to reproduce these pilots.

## Prototypes

- **A — extractive:** exact course filtering, conservative duplicate removal,
  explicit text/label conflict exclusion, instruction-sentence removal, aspect
  rules, conflict-first selection, and an exact-quote paragraph template.
- **B — classifier:** word/character TF-IDF and one-vs-rest logistic regression,
  trained on 29 source-reviewed observations; probability threshold 0.5. It shares
  A's candidate-sentence filter, so it is not an end-to-end encoder comparison.
  Final phrasing is the same exact-quote template. The tiny label set is not
  sufficient to assess classifier architectures generally.
- **C — hybrid:** Qwen3.5-4B Q5_K_M sees A's selected evidence ledger, then its raw
  paragraph is checked against an exact approved-paragraph whitelist. Rejected
  text falls back to A. This deliberately restrictive checker is not an NLI or
  semantic-support proof; rejection alone does not mean a paraphrase is false.
- **D — fine-tuned:** FLAN-T5-small, pinned revision
  `0fc9ddf78a1e988dac52e2dac162b0ede4fd74ab`, trained for 120 steps with 39
  source-reviewed/teacher-derived pairs. Batch 4, AdamW at 0.0001, seed 42,
  input limit 512 and target/output limit 192 tokens. Teacher outputs are
  deterministic extractive paragraphs, not independent human-written summaries.
- **E — control:** the same pretrained FLAN-T5-small, with the same input contract
  and decoding settings, without the additional task training.

Both small-model variants receive A's evidence selection; they cannot recover
observations A omitted. Inputs are rejected rather than silently truncated. Raw
outputs remain available even when unusable. CPU/GPU sanity probes and one
identical-input CPU control distinguish blank control behavior from an assumed
GPU failure. This does not establish a general comparison of untuned and tuned
models or an optimal prompt for FLAN-T5.

## Commands

Dependencies are isolated under `.build/bye-evidence-summary-2026-10-15/venv/`.
Direct package versions are in `requirements.txt`; the resolved environment must
be saved alongside a run. Model files are downloaded separately from the pinned
public repository and verified before inference. The base safetensors file is
307,867,048 bytes with SHA-256
`495fa51e204676f1a857a9fc13c4c89f3f5ba9f480b898cebca02add25e6d749`.

```sh
python3 -m unittest discover -s benchmarks/evidence-summary -v
python3 benchmarks/evidence-summary/run.py freeze
.build/bye-evidence-summary-2026-10-15/venv/bin/python3 benchmarks/evidence-summary/run.py baselines
.build/bye-evidence-summary-2026-10-15/venv/bin/python3 benchmarks/evidence-summary/run.py hybrid
```

The fine-tuning actions are `train`, `control`, and `evaluate` in `finetune.py`.
Run them sequentially inside the macOS policy
`(version 1)(allow default)(deny network*)`, using the isolated Python runtime.
Model loading sets `local_files_only=True`, `HF_HUB_OFFLINE=1` and
`TRANSFORMERS_OFFLINE=1`. The hybrid runtime is restricted to loopback. The Python
controllers also reject external socket connections. No automatic uploads occur.

Existing frozen data, baseline results, hybrid results or fine-tuned checkpoints
cannot be overwritten by their corresponding actions. Source-linked judgments in
`reviews.json` must match exact output/evidence hashes. `analyze.py` verifies those
bindings and creates private `SUMMARY.json` and `SAMPLES.md`. All 105 case outputs
are preserved; only 55 outputs on the 11 evaluation cases contribute to the
reported comparison.

Timings are loaded-model diagnostics on the Mac, not complete app startup or Pi
latency. No model or prototype is release-approved by this pilot. The separate
report describes observed quality failures, limited data, coverage and next steps.
