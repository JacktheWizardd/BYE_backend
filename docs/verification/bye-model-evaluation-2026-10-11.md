# BYE task 2: offline model evaluation

Status: stopped at user request after observed quality failures. No release model has been selected.

The remaining benchmark phases are cancelled. Tested configurations have no release recommendation; unfinished configurations and phases remain untested. All models and audit evidence are retained. Further inference requires a new user instruction.

The 256-token development matrix completed 3,312/3,312 pipelines; the 384-token comparison completed 1,089/3,312 before pause. These counts include recorded failures. Held-out testing has not started. The controller exited and the model unloaded. All candidates and logs remain preserved; resume requires archiving the interrupted partial stage and preserving existing environment snapshots. No automatic resume is scheduled.

The isolated comparison uses all twelve pinned GGUF variants, llama.cpp b11559 with Metal, one model and one inference request at a time, and frozen local evidence. PCC/RMP access and downloads are excluded. Existing releases and previous experiment evidence are preserved.

The mandatory installed `.app` logical-size cap is strictly below **1,500,000,000 bytes**. Model weights, compressed ZIP size, allocated blocks, runtime RSS and physical footprint are separate measurements.

The GitHub-ready [experiment record](../experiments/2026-10-11-local-summarization/README.md) includes the process, [recorded results](../experiments/2026-10-11-local-summarization/RESULTS.md), and [numeric data](../experiments/2026-10-11-local-summarization/data/README.md).

Complete raw evidence remains in ignored `.local-docs/model-eval-2026-10-11/20261012T040851Z/`, with per-case judgments, raw outputs, events and resource logs. The separate local archive is `.local-docs/experiment-records/2026-10-11-bye-local-models/`. See the [tooling README](../../benchmarks/model-eval/README.md) and [conditional integration proposal](../../benchmarks/model-eval/production-integration-proposal.md).

All twelve original artifacts passed pinned-size/SHA-256 verification and initialized the retained Metal runtime. The original runner's 22 fixture checks pass, including overflow, invalid citations, duplicate corroboration, checkpoint protection, cancellation ownership and hash mismatch. The CPU sampler's Mach-time conversion is calibrated against `getrusage`.

The 256-token baseline has observed quality failures in every context/pipeline configuration reviewed so far. This is an interim finding; the larger-budget, held-out, long-input, energy and native workflow phases remain pending. Semantic review is exploratory agent review with model identities hidden in review packets, not independent human certification.

Power changed from AC-but-discharging to charging during the run after the user connected a stronger charger. Power/thermal observations began partway through round one. Those limitations remain in the logs and must qualify timing/resource comparisons. Filesystem cache state is uncontrolled; no genuinely cold-loading claim is made.

Raw review text remains in ignored storage. The experiment was stopped; no complete-run validation or final selection is claimed.
