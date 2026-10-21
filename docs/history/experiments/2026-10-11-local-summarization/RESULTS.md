# Recorded results

This is a stopped exploratory experiment, not a completed model ranking. The tables below are derived from committed numeric data. Counts include failed or structurally invalid attempts. A fast invalid answer is not a successful summary.

The earlier screening tested **LFM2.5-1.2B-Instruct Q4_K_M**, **Qwen3.5-0.8B Q4_0**,
and **SmolLM2-360M-Instruct Q4_K_M**. All three were rejected and their weight/app/ZIP
copies removed with logs preserved. Their pinned identities are in
[original-candidates.csv](data/original-candidates.csv). The measurements below
belong to the later nine-candidate/twelve-variant experiment, not that first screening.

## Completion

| Phase | Completed pipelines | Planned pipelines |
| --- | ---: | ---: |
| Development, 256 output tokens | 3,312 | 3,312 |
| Development, 384 output tokens | 1,089 | 3,312 |
| Held-out inference | 0 | Not executed |

The export contains 5,848 recorded stages belonging to completed pipelines and 108 fresh-process loading/resource sessions, including preflight. The interrupted unfinished pipeline remains in local raw evidence and is outside completed-trial tables.

## Baseline timing and runtime memory

Latency below uses ordinary cases, direct summarization, 2,048 context, 256 output tokens. It includes template rendering, tokenization, inference and validator work. It includes structurally invalid results when execution completed, and excludes execution failures/checkpoint-reconstructed timing. Cases differ in length; use matched-case-timings.csv for comparisons on the same evidence.

Memory below is the maximum sampled llama-server RSS across the variant’s 256-token development sessions at both context sizes, including near-limit cases. It is not whole-app or unique unified-memory usage. Decimal MB = 1,000,000 bytes. No speed/memory rejection threshold was set.

| Variant | Timed trials | Median s | Min–max s | Helper peak RSS MB |
| --- | ---: | ---: | ---: | ---: |
| danube2-18b--Q5_K_M | 63 | 1.556 | 1.070–4.092 | 1696.5 |
| gemma3-270m-qat--Q4_0 | 63 | 0.337 | 0.192–0.928 | 621.6 |
| granite4-1b--Q4_K_M | 63 | 1.158 | 0.729–3.745 | 1579.2 |
| granite4-1b--Q5_K_M | 63 | 1.344 | 0.840–3.562 | 1732.1 |
| granite4-350m--Q8_0 | 63 | 0.362 | 0.138–1.258 | 707.9 |
| lfm25-thinking--Q4_K_M | 63 | 0.726 | 0.310–2.083 | 955.6 |
| llama32-1b--Q4_K_M | 63 | 1.002 | 0.552–2.339 | 1191.4 |
| llama32-1b--Q8_0 | 63 | 1.430 | 0.940–3.355 | 1706.8 |
| qwen25-15b--Q4_K_M | 63 | 1.135 | 0.377–3.102 | 1476.3 |
| qwen25-15b--Q5_K_M | 63 | 0.912 | 0.383–3.366 | 1645.0 |
| qwen3-17b--Q4_K_M | 63 | 1.514 | 0.986–3.594 | 1948.0 |
| qwen35-2b--Q4_K_M | 63 | 1.737 | 1.102–3.796 | 1710.3 |

Power/thermal state and background workload were not constant. Observation began partway through round one and charging changed during the run. Filesystem cache state is uncontrolled. These are recorded distributions, not clean-room causal comparisons. No battery-energy ranking is available. RSS, physical footprint, supervisor memory and Metal allocation figures overlap and must not be added.

## Quality checkpoint

All 48 baseline configurations (12 variants × 2 contexts × 2 pipelines) had observed quality failures. The saved checkpoint also contains partial larger-budget review. Repeated deterministic answers can share one hash-bound semantic judgment; trial totals are not independent judgments.

| Variant | Baseline configurations with observed failures |
| --- | ---: |
| danube2-18b--Q5_K_M | 4/4 |
| gemma3-270m-qat--Q4_0 | 4/4 |
| granite4-1b--Q4_K_M | 4/4 |
| granite4-1b--Q5_K_M | 4/4 |
| granite4-350m--Q8_0 | 4/4 |
| lfm25-thinking--Q4_K_M | 4/4 |
| llama32-1b--Q4_K_M | 4/4 |
| llama32-1b--Q8_0 | 4/4 |
| qwen25-15b--Q4_K_M | 4/4 |
| qwen25-15b--Q5_K_M | 4/4 |
| qwen3-17b--Q4_K_M | 4/4 |
| qwen35-2b--Q4_K_M | 4/4 |

Read quality-checkpoint.json for per-configuration review counts, technical failures, raw/display safety findings, priority-theme coverage and readability denominators. It is the saved review checkpoint, not a claim that all 4,401 pipelines received complete semantic review. Failed extraction can leave no final answer. Such failures are not successes.

synthetic-examples.json contains six illustrative reviewed fixture/output pairs across variants, selected in saved packet order while preferring different variants. They are not a representative accuracy sample or a per-model ranking. These fixtures are fictional; no real student review text is published.

## Prototype bundle measurements

These are the initial measurement bundles, not the unfinished final SwiftUI staging build. Legacy sizing sums regular-file logical bytes and does not duplicate symlink targets; symlink-entry overhead is not included. Values are recorded evidence, not final shipping-size certification. The release cap remains strictly below 1,500,000,000 installed logical bytes. ZIP and weights are separate.

| Variant | Weight bytes | Prototype installed bytes | ZIP bytes |
| --- | ---: | ---: | ---: |
| qwen35-2b--Q4_K_M | 1,280,835,840 | 1,320,427,210 | 1,273,324,697 |
| qwen3-17b--Q4_K_M | 1,282,439,584 | 1,321,898,439 | 1,268,485,945 |
| qwen25-15b--Q4_K_M | 1,117,320,736 | 1,156,766,988 | 1,106,778,759 |
| qwen25-15b--Q5_K_M | 1,285,494,304 | 1,324,940,556 | 1,289,810,567 |
| granite4-1b--Q4_K_M | 1,023,645,440 | 1,063,114,308 | 1,019,571,199 |
| granite4-1b--Q5_K_M | 1,178,310,400 | 1,217,779,268 | 1,188,714,579 |
| granite4-350m--Q8_0 | 378,138,016 | 417,605,950 | 375,550,938 |
| llama32-1b--Q4_K_M | 807,694,464 | 847,201,861 | 805,282,155 |
| llama32-1b--Q8_0 | 1,321,083,008 | 1,360,590,398 | 1,280,188,642 |
| gemma3-270m-qat--Q4_0 | 241,410,624 | 281,126,293 | 237,014,586 |
| danube2-18b--Q5_K_M | 1,301,789,856 | 1,341,198,537 | 1,313,901,758 |
| lfm25-thinking--Q4_K_M | 730,895,360 | 770,428,251 | 729,603,202 |

## Decision

Stop further inference for this experiment. No release candidate selected. Retain the candidates and all local audit evidence. Screen a simpler extractive/template baseline before committing to fine-tuning. Held-out, dedicated energy, full long/chunk/reasoning and final native UI checks remain untested.
