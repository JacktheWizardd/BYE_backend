# Organization and export validation — October 12, 2026

- Model-preparation fixture suite: **10 tests passed**.
- Model-evaluation/review/analysis/public-export fixture suite: **30 tests passed**.
- Targeted mocked Swift suites: **37 tests passed**, covering collection gates,
  RMP transport/client behavior and AppModel summary/cache/cancellation behavior.
  They made no live PCC/RMP requests. Other Swift tests were not run.
- Public-export tests verify real text/free-form errors are omitted from numeric
  records, real-case labels are replaced, original evidence remains unchanged,
  and existing export directories are protected.
- Exported **4,401 completed pipelines, 5,848 stages, 108 load/resource sessions**.
  Counts reconcile with 3,312 baseline and 1,089 larger-budget pipeline records.
- Shell syntax checks passed for `scripts/swift.sh` and `scripts/benchmark-bye-mac.sh`.
- Tracked diff whitespace check passed.
- Optimized native builds passed in three separate scratch directories: ordinary
  release, `BYE_AUDIT`, and `BYE_MODEL_EVAL`. The evaluation build emitted an unused
  optional-result warning; the Swift wrapper emitted a native-build-system
  deprecation warning. Neither prevented compilation/linking.
- The targeted Swift test build also reported an existing MainActor callback
  conversion warning in `CourseQueueTests.swift` (not part of this change); it
  did not fail the current language-mode build. This check does not certify a
  future Swift 6 language-mode migration.

These checks do not run inference or contact PCC/RMP. Historical Swift audit/build
checks are documented in the audit summary. The latest native evaluation UI now
compiles, but its workflows were not exercised during organization. No full Swift suite, final native
integration, energy comparison or release certification is claimed here.
