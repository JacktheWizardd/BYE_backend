# BYE local summarization experiment

Work performed October 11, 2026; organized for GitHub October 12, 2026 (Pacific time).

**Outcome: no tested configuration earned a release recommendation.** The user
stopped the remaining benchmark after repeated quality failures. No production
release was replaced. Untested configurations remain untested.

## Purpose and constraints

Evaluate offline summaries with cited pros and cons for BYE's native macOS app.
Any eventual runtime and model must ship inside the app with no setup or downloads.
The mandatory installed `.app` limit is strictly below 1,500,000,000 logical bytes;
weights, ZIP size, runtime memory and allocated disk blocks are separate figures.

## What changed

| Phase | Implementation | Observed outcome |
| --- | --- | --- |
| Initial local screening | Synthetic fixtures, cached-review runner, summary review and resource tooling | Three original checkpoints rejected; evidence preserved |
| Bounded app audit | Shared collection gate, opt-in native instrumentation, isolated storage, resource sampler and transport regression test | Corrected authorized pilot made 19 paced requests and collected 104 reviews across four profiles, including 13 exact-course reviews |
| Cleanup | Narrow inventory/checksum-based removal of the three rejected checkpoints and their app/ZIP copies | Nine paths removed; runtime, logs, caches and releases retained |
| Candidate preparation | Pinned manifest, resumable sequential downloads, byte/hash verification, GGUF inspection and license records | Nine candidates / twelve GGUF files verified; 11,949,057,632 weight bytes |
| Replacement-model benchmark | Sequential Metal runner, two pipelines, frozen evidence, raw/display review, CPU/memory sampling and checkpoint logs | 3,312 development pipelines completed at 256 tokens; 1,089 of 3,312 completed at 384 before stopping |
| Record preservation | Separate local experiment archive, source snapshots and checksums | Both benchmark runs copied and verified; original logs and all twelve candidates retained |

Completed pipeline counts include failures and deterministic repeats. They are not
counts of independent successful summaries.

## Models and protocol

### Original three-model screening

These were the first candidates tested, before the separate nine-candidate
replacement benchmark:

| Model | GGUF quantization | Exact weight bytes | Outcome |
| --- | --- | ---: | --- |
| LiquidAI LFM2.5-1.2B-Instruct | Q4_K_M | 730,895,168 | Rejected after initial screening; model/app/ZIP copies removed, logs retained |
| Qwen3.5-0.8B | Q4_0 | 563,036,064 | Rejected after initial screening; model/app/ZIP copies removed, logs retained |
| SmolLM2-360M-Instruct | Q4_K_M | 270,590,880 | Rejected after initial screening; model/app/ZIP copies removed, logs retained |

The [original pinned manifest](../../../benchmarks/bye-mac/manifest.json) retains
repositories, revisions, filenames, hashes and license identities. A compact
[original-candidate CSV](data/original-candidates.csv) is included in this record.
LFM2.5-1.2B **Instruct** is the retired checkpoint; LFM2.5-1.2B **Thinking** in the
later benchmark is a distinct checkpoint and remains retained. The original
screening is not included in the later 4,401 completed-pipeline count.

### Later nine-candidate comparison

The twelve variants cover Qwen3.5-2B, Qwen3-1.7B, Qwen2.5-1.5B-Instruct,
Granite 4.0 1B and 350M, Llama 3.2 1B Instruct, Gemma 3 270M IT QAT,
H2O Danube2 1.8B Chat, and LFM2.5-1.2B Thinking. Exact filenames, revisions,
hashes and recorded license obligations are in the
[preparation manifest](../../../benchmarks/model-prep/manifest.json).

The retained llama.cpp b11559 runtime initialized all twelve variants with Metal
on an Apple M5 MacBook Pro with 16 GB RAM and macOS 26.6.2. Comparison settings:
one loaded model and one request at a time, 2,048/4,096 contexts, greedy decoding,
seed 42, four CPU threads, batch 512/microbatch 128, full supported offload,
disabled prompt caching and context shifting. Final outputs were capped at 256
tokens, with a partial 384-token supplement; extraction allowed 512 tokens.

Both direct summarization and extraction followed by summarization were tested.
An earlier development pilot was retained separately after excessive quotation
and truncation prompted a common compact-output revision. Held-out inference
had not begun when prompts were revised.

The frozen corpus contains eleven real cases (seven development, four held out),
twelve original fictional fixtures, two additional synthetic cases, and long-input
banks. The replacement benchmark used local data only and made no PCC/RMP requests.
Live access belonged only to the separately authorized bounded collection audit.

## Findings and limits

All 48 baseline variant/context/pipeline configurations had observed quality
failures. Problems included unsupported claims, incorrect or incomplete citation
support, sentiment errors, lost disagreements, false corroboration from duplicate
content, missing priority themes, and malformed or empty displayed summaries.
The current display validator does not establish semantic correctness: it can
discard useful details while retaining incorrect claims.

Semantic review was exploratory agent review with model identities hidden in
packets, not independent human certification. Outputs were not all identical.
These findings reject the tested configurations under the chosen quality gates;
they do not establish that every fine-tuned checkpoint or alternative approach fails.

Loading, timing, token counts, CPU, memory, allocations and raw outputs were logged.
The CPU sampler's Mach-time conversion was corrected and calibrated against
`getrusage`; historical affected files remain unchanged with an erratum.
Power changed from AC-but-discharging to charging, telemetry started partway
through the run, and filesystem cache state was uncontrolled. CPU time is not
battery energy. RSS, footprint and Metal allocations must not be summed as unique
physical memory. No final fair performance or energy ranking is claimed.

Held-out testing, the remaining 384-token matrix, dedicated energy workloads,
full oversized-input/reasoning phases, and final improved native UI validation
were not completed. Prototype staging sizes are not final integration certification.
The latest measurement UI source is included as unfinished tooling, not a tested
production integration.

## Lessons and next options

The repeated quality failures should have triggered an earlier stop/go discussion
before spending more time on performance repetitions. Future screening should
start with a small development quality gate, then benchmark credible candidates.

Compare a deterministic/extractive baseline against small classifiers and templates
before committing to generator fine-tuning. Fine-tuning is a possible experiment,
not a demonstrated fix. Preserve professor-level held-out separation, gather more
independently annotated examples, and measure citation support, disagreement,
attribution and abstention. No next experiment has been started.

## Evidence and navigation

- [Recorded results and comparison tables](RESULTS.md)
- [Public numeric data, provenance and synthetic examples](data/README.md)
- [Validation performed while organizing](VALIDATION.md)
- [App audit summary](../../verification/bye-app-audit-2026-10-11.md)
- [CPU accounting erratum](../../verification/bye-cpu-accounting-erratum-2026-10-11.md)
- [Candidate preparation](../../verification/bye-model-preparation-2026-10-11.md)
- [Stopped benchmark status](../../verification/bye-model-evaluation-2026-10-11.md)
- [App audit tooling](../../../benchmarks/app-audit/README.md)
- [Model evaluation tooling](../../../benchmarks/model-eval/README.md)
- [Conditional integration proposal](../../../benchmarks/model-eval/production-integration-proposal.md)
- [Commit guide](COMMIT_GUIDE.md)

Local-only archive: `.local-docs/experiment-records/2026-10-11-bye-local-models/`.
It contains both benchmark runs, tooling snapshots, a readable account, candidate
inventory and checksums. Raw reviews, source-linked annotations, token streams,
screenshots and per-process logs remain ignored. Weights and runtime/build outputs
remain under `.build/`. The local archive is not a backup to another device.
