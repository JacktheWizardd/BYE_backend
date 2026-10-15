# BYE paragraph-summary evaluation

Isolated implementation of the October 15 plan: select a bundled, offline model
for one paragraph summarizing saved student reviews for the selected class.
Production summaries remain disabled. This tooling does not modify the native app.

## Local data and privacy

Inference reads only the preserved corpus at
`benchmarks/datasets/bye-summary-2026-10-11/private/benchmark/corpus-full.json`.
There is no PCC or RMP client or collection path. The controller rejects external
socket connections during inference, and macOS restricts the model process to
loopback networking. `diagnostics` verifies external TCP denial separately.

Original reviews, source-linked judgments, model outputs, runtime logs, resource
samples and reports remain in ignored `.local-docs/paragraph-summary-2026-10-15/`.
Do not commit those files. A fresh clone cannot reproduce real-review trials
without this private corpus. Previous experiment evidence is left intact.

## Preparation

`manifest.json` pins exactly three initial GGUF artifacts. Downloads are sequential,
resumable, promoted only after exact byte/SHA-256 verification, and kept in
`.build/bye-paragraph-summary-2026-10-15/models/`. `fetch.py` is the only network
preparation action; it contacts Hugging Face and Apache, never review websites.
Publisher/upstream metadata revisions, licenses, notices and tokenizer settings
are preserved locally. Third-party conversion-source revisions are not inferred
from upstream metadata. Packaging must preserve Apache notices and attribution;
preparation does not certify production redistribution.

```sh
python3 -m unittest discover -s benchmarks/paragraph-summary -v
python3 benchmarks/paragraph-summary/fetch.py
python3 benchmarks/paragraph-summary/run.py prepare
python3 benchmarks/paragraph-summary/run.py verify --model qwen35-9b-q4
```

The archived llama.cpp b11559 runtime is required. An unavailable/incompatible
runtime blocks evaluation rather than triggering a replacement download.

## Screening and the single prompt revision

Run one model at a time with the same prompt: 8,192 context, 512 output tokens,
greedy decoding, seed 42, four threads, batch 512/microbatch 128, Metal offload,
no startup warmup, no prompt caching or context shifting, and reasoning disabled.
All seven development cases and fourteen synthetic cases run once. The four
held-out cases are not sent to any model during screening. No live requests occur.

```sh
python3 benchmarks/paragraph-summary/run.py screen --model qwen35-9b-q4
python3 benchmarks/paragraph-summary/run.py screen --model ministral3-8b-q4
python3 benchmarks/paragraph-summary/run.py screen --model qwen35-4b-q5
```

Revision 1 is the sole shared revision: it strengthens the 120-word ceiling,
prohibits unsupported explanations for disagreement, and excludes injected
instruction claims from reported experiences. Apply `--revision 1` to the same
three commands. Each run freezes its exact prompt, settings, corpus and runner
hashes. Existing completed/partial screens cannot be overwritten. Failed setup
attempts with no case outputs are moved into `blocked-attempts/` before retry.

Evidence selection normalizes numeric course spelling without assuming subject
aliases or honors equivalence, keeps complete review text and deduplicates
normalized exact copies. Text/label conflicts still require semantic review.
Oversized inputs use whole-review chunks followed by reduction; original IDs,
chunk boundaries and raw intermediate outputs are retained. One oversized review
or an oversized reduction is rejected explicitly. Empty evidence returns a fixed
insufficient-evidence message. Single-source observations are allowed with clear
attribution; the old two-source abstention rule does not apply.

## Source review and gated measurement

For each screen, write `review/decisions.json`, keyed by the 21 case names. Each
judgment must include `output_hash`, `evidence_hash`, `safe`,
`disagreements_preserved`, `covered_priority_facts`, `eligible_priority_facts`,
`notes`, and reviewer identity. Inspect original evidence and the complete paragraph,
including compound claims, scope, negation, source independence, malicious text,
and material conflicts. Bind any sentence-to-source analysis to the same hashes.
Historical recurring-theme annotations are starting references, not automatic
ground truth for this new paragraph contract. Explicitly annotate changed sparse
and duplicate cases and recalculate eligibility for complete evidence.

`measure` refuses missing/stale judgments, unsafe outputs, lost disagreements,
format/truncation errors, or aggregate priority coverage below 80%. Passing models
receive three repetitions per development case, each with a fresh-process request
and a second loaded-model request. Startup-inclusive timing includes integrity
verification and model loading. Filesystem caches are uncontrolled, never claimed
disk-cold. Record memory pressure/swap before and after, server RSS and footprint
at 100 ms, and corrected CPU time; do not add overlapping memory figures.

```sh
python3 benchmarks/paragraph-summary/run.py measure --model MODEL --revision 1
python3 benchmarks/paragraph-summary/run.py diagnostics --model MODEL --revision 1
python3 benchmarks/paragraph-summary/run.py heldout --model MODEL --revision 1
python3 benchmarks/paragraph-summary/run.py report
```

`diagnostics` runs a labeled startup pilot, saved long-input cases, empty evidence,
stream disconnect/cancellation and recovery. `heldout` requires development approval
and an existing measurement directory, freezes the provisional winner and creates
a new directory without overwrite. Held-out outputs cannot be used for prompt
tuning. Any smaller configuration needs its own pinned artifact, development
review and **fresh** held-out evidence; at most two reductions are authorized by
the plan. If all three revised candidates fail, stop before performance repetitions,
held-out inference or size-reduction trials and report no qualifying model.

## Size and reporting

The complete eventual installed app must be at most 8,000,000,000 logical bytes,
including weights, runtime, native resources and notices. Weights, compressed
download size, allocated disk blocks and runtime memory are separate quantities.
Prototype payload measurements do not certify the final integrated app.

The private `REPORT.md` provides trial status and diagnostic timings; `SAMPLES.md`
places every generated paragraph beside its complete selected source evidence.
Public documentation must contain only aggregate measurements and fictional
examples. Source review is exploratory agent assessment, not independent human
validation or production reliability certification.
