# BYE experiment tooling

Start with the [experiment record](../docs/experiments/2026-10-11-local-summarization/README.md)
and [recorded results](../docs/experiments/2026-10-11-local-summarization/RESULTS.md).
The stopped experiment selected no release model. Commands are historical tooling,
not authorization for live collection or further inference.

| Directory | Purpose | Status |
| --- | --- | --- |
| `bye-mac/` | Original three-model screening, cached reviews and synthetic fixtures | Historical; original models removed, logs retained |
| `app-audit/` | Bounded collection and instrumented native performance audit | Authorized collection finished |
| `model-prep/` | Pinned nine-candidate/twelve-file download and integrity workflow | Preparation completed; weights remain local |
| `model-eval/` | Sequential offline comparison, review, resource analysis and public export | User stopped remaining inference after quality failures |

Never use the old `bye-mac` fetch action to restore rejected checkpoints.
Local data and weights are intentionally not in Git. Fixture tests are offline;
real-data reproduction needs the separately retained evidence. See each directory's
README for commands and limitations.
