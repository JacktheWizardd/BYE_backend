# Suggested commit scope

This guide covers the current app improvements and repository organization. The
original experiment tooling is already in the repository. Review the staged diff
before committing, and keep the view split together with its model and reader changes.

## Suggested commit

Title: `Add class-day filtering and improve review browsing`

Description:

> Add class-day filtering, chronological and difficulty review sorting, and
> retrieval across equivalent course labels. Split native views into separate
> files and bring class sections to the top of professor reports.
>
> Add a stable local test-app build workflow and document the reusable benchmark
> dataset. Keep generated apps and private review data out of Git.

## Explicit staging paths

From the repository root, after reviewing the changes:

```sh
git add -A -- .gitignore AGENTS.md README.md \
  Sources/Classwise/AppModel.swift \
  Sources/Classwise/ProfileLookup.swift \
  Sources/Classwise/RMPAPIReader.swift \
  Sources/Classwise/RMPBrowser.swift \
  'Sources/Classwise/Views*' \
  Sources/ClasswiseCore/Models.swift \
  Tests/ClasswiseAppTests/APIReaderTests.swift \
  Tests/ClasswiseAppTests/CourseQueueTests.swift \
  Tests/ClasswiseAppTests/ScheduleFilterTests.swift \
  Tests/ClasswiseCoreTests/CoreTests.swift \
  Tests/ClasswiseCoreTests/CourseShorthandTests.swift \
  Tests/ClasswiseCoreTests/ScheduleAvailabilityTests.swift \
  scripts/build-test-app.sh test/README.md \
  benchmarks/datasets/bye-summary-2026-10-11/README.md \
  docs/experiments/2026-10-11-local-summarization/COMMIT_GUIDE.md
git diff --cached --stat
git diff --cached --check
```

The quoted `Views*` Git pathspec includes both the removed monolithic file and its
replacement directory. The adds honor `.gitignore`, including generated test apps
and local real-review expected facts.
Do not force-add ignored experiment outputs, `.local-docs/`, `.build/`, models,
user caches, or release archives. This commit does not resume the stopped experiment
or publish a release.

The fresh-clone fixture suites need no model downloads or live collection:

```sh
python3 -m unittest discover -s benchmarks/model-prep -v
python3 -m unittest discover -s benchmarks/model-eval -v
```

The current native app passed all 170 tests with `./scripts/swift.sh test` during
the October 12 pre-commit review. WebKit fixture tests required running outside the
review sandbox. This does not establish live-service or visual UI validation.

See `VALIDATION.md` for historical experiment checks. Those records describe the
stopped benchmark and do not claim that held-out inference or final native model
integration was completed.
