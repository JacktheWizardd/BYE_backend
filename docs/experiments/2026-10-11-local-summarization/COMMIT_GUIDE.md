# Suggested commit scope

No files were staged or committed as part of organization. Review the diff first.
The instrumented native views share audit/evaluation changes, so keep those changes
together rather than splitting interdependent compilation flags across commits.

## Suggested commit

Title: `Add local summarization experiment tooling and document stopped evaluation`

Description:

> Add bounded collection/performance instrumentation, pinned model preparation,
> and sequential offline summarization evaluation with raw/display quality review.
> Preserve experiment summaries and document the stop decision after observed
> factual failures. Keep generated evidence, reviews and model weights local.
>
> The 256-token development matrix completed 3,312 pipelines; the 384-token
> comparison stopped after 1,089. No release model is selected. Remaining held-out,
> energy and final native integration checks are untested.

## Explicit staging paths

From the repository root, after reviewing the changes:

```sh
git add -- .gitignore README.md benchmarks/README.md \
  Sources/BYEAPI/Transport/RMPTransport.swift \
  Sources/Classwise/AppModel.swift \
  Sources/Classwise/AppleSummaryProvider.swift \
  Sources/Classwise/ClasswiseApp.swift \
  Sources/Classwise/Views.swift \
  Sources/Classwise/AppAudit.swift \
  Sources/Classwise/ModelEvaluation.swift \
  Sources/ClasswiseCore/CollectionAudit.swift \
  Tests/BYEAPITests/RMPClientTests.swift \
  Tests/ClasswiseCoreTests/CollectionGateTests.swift \
  scripts/swift.sh scripts/benchmark-bye-mac.sh \
  benchmarks/app-audit benchmarks/bye-mac benchmarks/model-prep benchmarks/model-eval \
  docs/experiments/2026-10-11-local-summarization \
  docs/verification/bye-app-audit-2026-10-11.md \
  docs/verification/bye-cpu-accounting-erratum-2026-10-11.md \
  docs/verification/bye-model-preparation-2026-10-11.md \
  docs/verification/bye-model-evaluation-2026-10-11.md
git diff --cached --stat
git diff --cached --check
```

The directory adds honor `.gitignore`, including local real-review expected facts.
Do not force-add ignored experiment outputs, `.local-docs/`, `.build/`, models,
user caches, or release archives. This is source/documentation for an incomplete
experiment, not a production-model integration or a release-readiness claim.

The fresh-clone fixture suites need no model downloads or live collection:

```sh
python3 -m unittest discover -s benchmarks/model-prep -v
python3 -m unittest discover -s benchmarks/model-eval -v
```

See `VALIDATION.md` for checks performed while organizing this commit. Historical
Swift audit/build checks are reported in the audit summary. The latest native
evaluation UI was not built or exercised during this stopped benchmark.
