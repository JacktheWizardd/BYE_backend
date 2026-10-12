# BYE candidate preparation — October 11, 2026

Task 1 downloaded and verified **nine candidates in twelve GGUF files**, totaling **11,949,057,632 bytes**. All files matched their pinned sizes and SHA-256 values. GGUF metadata and declared quantization types passed local inspection. No model loading, inference, benchmark, or PCC/RMP request was performed by this preparation workflow.

| Candidate | Variants |
|---|---|
| Qwen3.5-2B | Q4_K_M |
| Qwen3-1.7B | Q4_K_M |
| Qwen2.5-1.5B-Instruct | Q4_K_M, Q5_K_M |
| Granite 4.0 1B | Q4_K_M, Q5_K_M |
| Granite 4.0 350M | Q8_0 |
| Llama 3.2 1B Instruct | Q4_K_M, Q8_0 |
| Gemma 3 270M IT QAT | Q4_0 |
| H2O Danube2 1.8B Chat | Q5_K_M |
| LFM2.5-1.2B Thinking | Q4_K_M |

The pinned [manifest](../../benchmarks/model-prep/manifest.json) records repositories, full revisions, filenames, exact bytes, hashes, upstream identities, and license obligations. Conversion-source revisions remain explicitly unverified. Read the [tooling README](../../benchmarks/model-prep/README.md) before resuming or reusing preparation.

Weights are in ignored `.build/bye-candidates-2026-10-11/<candidate-id>/`. Complete logs and evidence are in ignored `.local-docs/model-prep-2026-10-11/20261012T003156Z/`, including `REPORT.md`, `inventory.csv`, GGUF metadata, verbatim chat templates, source snapshots, license/policy documents, generated notices, and checksums. There are no remaining partial weight files.

Ten preparation-tool fixture tests passed. All nine candidates have saved license text and applicable policy evidence. Some gated upstream metadata requests were denied and remain logged. Llama's complete use policy was extracted from its saved pinned upstream model card; Gemma terms and prohibited-use policy came from Google's public documentation. No access controls were bypassed. These records do not certify production distribution eligibility.

The strict initial preservation check returned a nonzero result because nine existing BYE user-cache files changed or disappeared during the session. A separately installed BYE app was observed already running; the exact writer was not traced. The preparation workflow did not launch that app or write existing caches, and no cache was restored or overwritten. Original before-hashes and failed checks are preserved. Immutable benchmark evidence, frozen data, runtime and release files were rechecked and remained unchanged. The three retired checkpoints and their app/ZIP copies remain absent.

Final readiness is **complete with observed mutable-cache changes**. Compatibility, full staged-app sizing, summary quality, time, memory, and energy remain for task 2. No release model is selected. The mandatory installed-app limit remains strictly below **1,500,000,000 bytes**; total development downloads, runtime memory, and distribution archive size are separate quantities.
