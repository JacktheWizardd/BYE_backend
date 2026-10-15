# BYE evidence-first and fine-tuning pilots — October 15, 2026

**Recommendation: develop the source-linked extractive baseline first.** Its
displayed quotes stayed supported in this pilot, but evidence selection still
missed material disagreements. None of these prototypes is ready to ship.

This follows the Notion research options and the user's request to include
fine-tuning. It does not replace the earlier paragraph-model record.

## Comparison

All evidence came from saved local files: **zero PCC/RMP requests**. Training used
two saved development professors and eight fictional cases. Evaluation used five
different development professors and six fictional challenge cases. The original
four held-out professor cases remain untouched by inference.

There are 105 saved outputs: five methods × 21 cases. Fifty training-case outputs
are fit diagnostics; **55 outputs on 11 evaluation cases** form this comparison.
Judgments are exploratory Codex source review, not independent human validation.

| Method | Claim/attribution errors | Unusable outputs | Priority themes covered | Cases missing material disagreement |
|---|---:|---:|---:|---:|
| A: exact quotes + templates | 0/11 | 0/11 | 16/18 | 2/11 |
| B: small classifier + same templates | 4/11 | 4/11 | 4/18 | 5/11 |
| C: generated evidence-first paragraph + strict fallback | 0/11 displayed | 0/11 displayed | 16/18 | 2/11 |
| D: task-fine-tuned FLAN-T5-small | 4/11 | 0/11 | 14/18 | 3/11 |
| E: same small model without task training | 0/11 | 10/11 | 0/18 | 5/11 |

Error types differ: B's errors are false insufficient-evidence statements; D's
include incorrect reviewer attribution and duplicated quotations. E's one usable
output is the fixed empty-evidence message, which bypasses the model. Zero invented
claims in a blank output is not success.

**A:** source-linked quotes avoid new factual wording. It still favors short
observations and can miss an important minority account. It omitted the
no-penalty late-work account while retaining the penalty account, and missed
important exam/grade-policy disagreements in another real case. Exact extraction
does not guarantee balanced coverage or a polished 80–120 word paragraph.

**B:** the classifier trained on only 29 reviewed observations. It missed unseen
topics and selected very little useful evidence. It also shares A's rule-based
candidate filter. This is a weak, tiny-data prototype, not evidence that properly
trained encoder classifiers cannot work. Its empty-selection wording incorrectly
describes feedback as insufficient when the classifier simply failed to identify it.

**C:** the raw generated paragraphs had observed unsupported claims in 5/11
evaluation cases, including fabricated conflicts between different topics. All
ten non-empty evaluation cases fell back to A; the empty case bypassed generation.
The displayed result therefore adds model cost without improving A's text. The
checker requires exact approved text, so rejection of the other raw outputs is
not proof those paraphrases were false. A useful semantic verifier remains untested.

## What fine-tuning changed

[FLAN-T5-small](https://huggingface.co/google/flan-t5-small) was trained locally on
the Mac using 39 source-reviewed/teacher-derived pairs: 29 labeled observation
examples plus ten deterministic extractive case targets. The base artifact is
307,867,048 bytes. Model revisions, hashes, tokenizer/configuration and the trained
checkpoint are preserved locally.

The bounded run used 120 AdamW steps, batch 4, learning rate 0.0001, seed 42,
512 input tokens and 192 target/output tokens. It ran on the Mac's MPS backend
in approximately **25.8 seconds**. Training loss fell sharply; this demonstrates
fitting, not generalization or factual accuracy.

The untouched model produced whitespace or instruction-like text for ten
non-empty evaluation inputs under this particular JSON-evidence input contract.
The fine-tuned model produced a paragraph for every evaluation case. Training
therefore improved compliance and copying **in this controlled pilot**.

It did not eliminate attribution errors. In a fictional deadline fixture, two
different students said:

> In my section the deadlines stayed predictable throughout the course.

> In my section deadlines changed unexpectedly several times.

The fine-tuned paragraph joins them with **“The same review added”**. The quote
bodies are copied, but their attribution is false. In other cases it duplicated
one quotation as another student's statement or dropped a priority observation.

CPU/GPU sanity checks produced matching token sequences on two simple prompts.
An identical-input CPU control also reproduced the untouched model's whitespace
output. This rules out a GPU-only explanation for that checked example; it does
not prove an optimal FLAN-T5 prompt or establish that fine-tuning always beats
prompting. The training set is very small, includes teacher-derived targets, and
synthetic cases share vocabulary. Broader conclusions require better labels and
a fresh, independently reviewed evaluation set.

Loaded-model diagnostic medians were approximately 0.0005 s for A, 0.0012 s for B,
2.08 s for C, 0.46 s for D and 2.09 s for E across non-empty evaluation cases.
These exclude initialization/training/native UI costs, use mixed short and real
cases, and are **not** complete-app ten-second measurements or Pi estimates.

## Why the previous models failed

“Local” specifies deployment location; it does not identify the cause of an error.
The previous runs demonstrated concrete failures: merging separate reviewers'
facts, importing another class's experiences, inferring unmentioned causes, and
adding plausible details. They did not isolate deployment location, quantization,
model size, prompting and fine-tuning in a controlled causal experiment.

This pilot shows that task training can improve the output contract while
attribution errors remain. The architectural opportunity is to keep course
filtering, duplicate handling, counts, source IDs and attribution deterministic,
then use a model only where it adds measured value. Every displayed claim still
needs support. A fluent paragraph or low training loss is insufficient.

## Raspberry Pi server feasibility

**User-proposed second deployment option; no Pi is available and none was tested.**
Train the task model on the Mac, then serve inference from a Pi on the local
network. The Mac would send already-retrieved evidence with course/source IDs;
the Pi would not collect PCC/RMP data. Return source-bound results for the Mac to
render. This optional architecture requires hardware/setup and differs from the
self-contained bundled-app requirement.

A small classifier/template pipeline or the roughly 308 MB fine-tuned checkpoint
is a more plausible starting candidate than assuming the earlier multi-GB models
will meet ten seconds on a Pi CPU. This is a feasibility inference, not a Pi
benchmark or hardware purchase recommendation. Actual CPU/runtime compatibility,
quantization effects, peak memory and request latency need device testing.

Raspberry Pi documents the [Pi 5's hardware](https://www.raspberrypi.com/products/raspberry-pi-5/)
and an [AI HAT+ 2 with generative-AI support](https://www.raspberrypi.com/products/ai-hat-plus-2/).
The [official AI HAT comparison](https://www.raspberrypi.com/documentation/accessories/ai-hat-plus.html)
distinguishes the earlier AI HAT+ from the generative-capable AI HAT+ 2. Do not
assume a custom fine-tuned T5 architecture can run on that accelerator: this pilot
did not verify a supported conversion/compiler path. TOPS specifications cannot
substitute for summary latency measurements.

Next hardware feasibility checks are a CPU-compatible artifact/runtime, the same
frozen evidence requests, source/attribution validation, cold and loaded request
latency, memory, cancellation and unavailable-server handling. No LAN service,
port exposure, hardware purchase or Pi deployment was performed here.

## Records and next direction

The original corpus is unchanged. Source IDs, exact offsets/quotes, split and
training settings, raw/fallback outputs, checkpoint hashes and 55 bound judgments
are retained in `.local-docs/evidence-summary-2026-10-15/`. Private `SAMPLES.md`
places all outputs beside their selected evidence. **Ten focused runner tests
pass.** There are no production app changes or release-approved models.

Prioritize A's missing-disagreement and selection issues. Improve labels and
confidence calibration before interpreting B's result as a model-family verdict.
Any future generation should keep reviewer attribution in deterministic code and
be evaluated against direct source spans. The Pi option can reuse that same
pipeline after accuracy is established; changing the machine does not itself
repair the model's factual errors.

Implementation details and reproduction limits are in the
[pilot guide](../../benchmarks/evidence-summary/README.md).
