# BYE paragraph-summary evaluation — October 15, 2026

**Outcome: no qualifying model.** All three candidates still produced unsupported
content after the single shared prompt revision. Do not enable a model in BYE from
this evaluation. Raising the installed-size budget solved the size restriction,
but did not establish summary accuracy.

Completed **126 screens**: three models × 21 saved cases × two prompts. Every output
was reviewed against its supplied evidence. Review is exploratory Codex assessment,
not independent human certification. The corpus is small and these counts are
case-level observations, not population error estimates.

## Candidates and quality

| Candidate | Verified weight bytes | Unsupported-content cases, initial → revised | Revised paragraphs over 120 words | Revised priority themes covered |
|---|---:|---:|---:|---:|
| Qwen3.5-9B Q4_K_M | 5,680,522,464 | 11/21 → 6/21 | 5/21 | 31/32 |
| Ministral 3 8B Instruct Q4_K_M | 5,198,911,904 | 10/21 → 10/21 | 5/21 | 31/32 |
| Qwen3.5-4B Q5_K_M | 3,143,656,608 | 10/21 → 10/21 | 2/21 | 30/32 |

Priority coverage counts applicable annotated themes, with the historical sparse
and duplicate cases recalculated for the new paragraph contract. High theme
coverage does not compensate for unsupported additions, wrong attribution or lost
disagreements. Raw paragraphs were retained without post-generation trimming.

All models loaded with the archived llama.cpp **b11559 / f2cc7282c** and Metal.
Publisher revisions and exact SHA-256 values are pinned in the
[manifest](../../benchmarks/paragraph-summary/manifest.json). Upstream metadata,
Apache-2.0 material and applicable notices are saved locally. Unsloth conversion
source revisions remain unverified; upstream metadata revisions are recorded
separately. No production redistribution is certified.

## Timing and size

Measurements used an Apple M5 Mac with 16 GB memory, 8,192 context, 512 output
tokens, four threads, greedy decoding, seed 42, one model/request at a time,
reasoning disabled, and no prompt caching or startup warmup.

| Candidate | Revised loaded-model median, six real cases | Observed range | Startup-inclusive pilot | Projected installed payload |
|---|---:|---:|---:|---:|
| Qwen3.5-9B Q4_K_M | 11.86 s | 11.68–14.80 s | 15.78 s | 5.720 GB |
| Ministral 3 8B Instruct Q4_K_M | 12.70 s | 10.51–38.23 s | 14.05 s | 5.238 GB |
| Qwen3.5-4B Q5_K_M | 7.29 s | 5.56–8.25 s | 8.99 s | 3.183 GB |

These are diagnostic screens, not the gated three-repetition performance study.
Each startup pilot used the first development case and includes integrity
verification, loading, evidence preparation and complete generation. There is
**one startup pilot per model**: Qwen 9B's comes from a separate diagnostic session;
the other two come from their revised screens. Only Qwen 4B met ten seconds in
that one pilot. This does not establish a reliable under-ten-second rate. No UI
integration overhead is included.

Filesystem cache state was uncontrolled. Background workload and power conditions
were not controlled; the Mac reported AC connection while discharging. The
Ministral run includes substantial timing variation. These observations do not
support a fair throughput or battery-efficiency ranking.

Projected payloads sum each verified model, the complete archived runtime,
the existing native test app, and all saved preparation documents. All are below
8,000,000,000 logical bytes. These are conservative payload projections, **not
measurements or certification of a final integrated/signed app**. Distribution
ZIP size and allocated disk blocks were not measured.

Peak sampled server RSS during the revised screens was 5.41 GB, 6.45 GB and
3.78 GB respectively. Corresponding server physical footprints were 0.63 GB,
1.31 GB and 0.63 GB. These quantities overlap and must not be added; neither is
whole-app or unique unified-memory usage. Raw resource samples and before/after
memory-pressure and swap snapshots are retained locally.

## Representative findings

Concrete failures persisted beyond style or length:

- **Qwen 9B:** merged separate reviews into a new compound claim, included attack
  text in the student-facing paragraph, and imported an explicitly different
  class's summer experience. It also invented different professors or course-label
  conflicts to explain contradictory reports.
- **Ministral 8B:** described negative reviews as belonging to another instructor,
  imported another class's deadline, and merged distinct grade anecdotes into a
  fabricated grade improvement. In a fictional fixture it changed late feedback
  into late submitted work and invented office hours.
- **Qwen 4B:** imported another class's deadline and trips, conflated different
  reviewers' observations, treated a joke about free treats as a real interaction,
  and repeated attack text despite saying it was disregarded.

The following examples use fictional fixtures only. Complete real-review samples
and all supporting sources remain in the private local report.

**Supported sparse summary, revised Qwen 4B:**

> One student noted that the examples in ETH 014 helped them understand the readings. No other reviews were provided for this class.

Its sole source was: “The examples helped me understand the readings.” This is a
useful short paragraph; padding it to 80 words would add no evidence.

**Unsupported detail, revised Ministral:**

The sources describe an instructor who was kind, approachable, available when help
was needed, and made time for questions. The paragraph adds “availability during
office hours.” None of the three sources mentions office hours.

**Incorrect attribution, revised Qwen 4B:**

Fixture p2 praises clear explanations and useful real-world examples. Fixture p3
calls explanations and examples the strongest parts of their experience. The
paragraph attributes “the strongest parts” to **both p2 and p3**, changing which
students actually made the observation.

## Verification and decision

- All testing consumed the preserved local corpus. **Zero PCC/RMP requests**;
  no collection code was invoked. Only public model/license preparation used
  external networking.
- External TCP denial was demonstrated under the inference sandbox. The
  controller additionally rejects external socket connections.
- The source corpus is unchanged. All 126 output/evidence/prompt hashes and the
  three model checksums were verified.
- Both saved long-input banks ran. Exact-copy deduplication reduced the synthetic
  bank enough to fit the context; neither bank required runtime chunk reduction.
  Whole-review chunking and oversized-review rejection pass unit tests, but
  runtime reduction remains untested.
- Stream disconnection released the runtime slot in **0.11 seconds** after the
  first generated token. A subsequent summary succeeded. This verifies generation
  cancellation/recovery in the harness, not native app cancellation or prefill
  cancellation.
- Empty evidence returned the fixed insufficient-evidence message.
- **17 runner tests pass**, covering course boundaries, deduplication, complete
  evidence preservation, chunking, overflow rejection, integrity, and fail-closed
  quality gates.

Following the agreed stop rule, no performance repetitions, held-out inference,
or size-reduction trials were run. The four held-out cases remain untouched by
inference. Production app code and summary enablement are unchanged.

**Recommendation:** retain the artifacts and reject these tested configurations
for shipping. Qwen 4B is a faster reference for a future experiment, not an approved
model. Any further approach needs a new quality screen before shrinking or app
integration; this evaluation does not authorize an automatic follow-up experiment.

The [evaluation guide](../../benchmarks/paragraph-summary/README.md) documents the
reproducible commands. Private reports are at
`.local-docs/paragraph-summary-2026-10-15/REPORT.md` and `SAMPLES.md`; the latter
places every generated paragraph beside its complete selected source reviews.
Raw outputs, source-bound decisions, compatibility logs, hashes, timing data and
resource samples are preserved in the same ignored directory.
