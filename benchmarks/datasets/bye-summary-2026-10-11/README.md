# Reusable BYE summary test data

Frozen evidence from the October 11, 2026 experiment, preserved for future local
tests. These files require no network requests or model downloads to read.
Original experiment evidence remains unchanged.

## Local corpus

`private/` is intentionally ignored by Git. It contains:

- `benchmark/corpus-full.json`: complete frozen corpus, including eleven real
  professor/course cases, fourteen synthetic cases and long-input banks.
- `benchmark/selected-cases.json`: the exact ordinary and near-limit subsets
  selected for the replacement-model comparison.
- `benchmark/development-expected-facts.json` and `heldout-expected-facts.json`:
  source-linked expected facts. Held-out annotations were frozen before inference;
  no held-out inference was performed in the stopped run.
- `benchmark/normalized-quality-annotations.json`: review-tool annotation schema.
- `benchmark/prompt-freeze.json` and `settings.json`: the experiment's prompt and
  settings identities; these are historical settings, not required future defaults.
- `audit/`: original frozen real-data corpus, expected facts, duplicate groups,
  retrieval provenance and source manifest.
- `inventory.json`: original paths, byte counts and SHA-256 hashes, verified after
  copying. Absolute source paths inside historical files are provenance, not
  required network locations; use the copied corpus directly.

The original twelve fictional fixtures are also available in the Git-tracked
[`benchmarks/bye-mac/corpus.json`](../../bye-mac/corpus.json). The two
extra synthetic fixtures are frozen inside the complete local corpus and are
constructed in [`run.py`](../../model-eval/run.py).

## Read locally

From the repository root:

```python
import json
from pathlib import Path

dataset = Path("benchmarks/datasets/bye-summary-2026-10-11/private/benchmark")
corpus = json.loads((dataset / "corpus-full.json").read_text())
development = [c for c in corpus["cases"] if c["partition"] == "development"]
held_out = [c for c in corpus["cases"] if c["partition"] == "held_out"]
synthetic = [c for c in corpus["cases"] if c["partition"] == "synthetic"]
```

Keep held-out professors out of training, prompt tuning and model selection on
development data. Keep duplicate content in the same partition and count it as
one independent source. Preserve conflicting reports and exact course labels.
Annotations are exploratory judgments, not certified ground truth.

Use `selected-cases.json` to compare against the exact prior input subsets;
use `corpus-full.json` for new whole-input experiments. New tokenizers/prompts
need fresh context-budget checks. Do not silently truncate reviews or replace
the frozen files. Save new subsets and results in a new dated run directory.

Real reviews and source-linked annotations must remain local. A fresh Git clone
will contain this guide and the tracked fictional corpus, but not `private/`.
Back up the private folder separately if moving computers; GitHub is not its backup.
Reading these files does not resume the stopped benchmark or authorize collection.
