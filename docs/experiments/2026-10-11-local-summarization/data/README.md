# Public experiment data

These files are derived from the stopped revised benchmark, run ID
`20261012T040851Z` (October 11 Pacific time). Original evidence remains local.

| File | Contents |
| --- | --- |
| `trials.csv` | 4,401 completed pipeline records, numeric timing and failure indicators |
| `stages.csv` | 5,848 extraction/direct/reduction stages belonging to completed pipelines; token counts, processing/generation speeds and timing |
| `matched-case-timings.csv` | Per-case/configuration repeat counts, median and range; incomplete repeat groups retained |
| `load-and-resources.csv` | 108 fresh-process sessions, readiness, Metal observation, helper/supervisor CPU and separate memory peaks |
| `quality-checkpoint.json` | Saved aggregate semantic-review checkpoint, including denominators and unfinished review |
| `prototype-bundle-sizes.csv` | Initial prototype weight, installed logical, allocated and ZIP sizes; not final UI integration sizing |
| `candidates.csv` | Pinned model identities, filenames, hashes, sizes and recorded license obligations |
| `original-candidates.csv` | Three earlier rejected candidates, pinned identities and cleanup status; separate from this run's counts |
| `settings.json` | Baseline effective comparison settings |
| `synthetic-examples.json` | Six illustrative fictional input/actual-output/display examples with review notes |
| `provenance.json` | Completion counts and SHA-256 identities of source JSON records read by the exporter |

Real cases have opaque labels in result CSVs. Provenance retains original relative
record names and hashes, but no raw review content. No real profile names, review
text, source IDs, prompts, free-form runtime errors or machine-absolute paths are
copied to the numeric tables. Synthetic examples deliberately retain fictional
text so readers can inspect concrete failures. The original source-to-case mapping
and real-review quality judgments remain local.

Seconds are monotonic-clock durations; bytes are exact process-accounting or file
figures. CSV booleans are `True`/`False`; empty cells mean unavailable, not zero.
`first_decoded_content_s` can refer to JSON syntax, not visible answer text.
`structural_error_count` is not a factual-error count. Raw/display quality is a
separate assessment. A recorded stage may have no completed generated output.

`pipeline_s` includes both stages for extraction/reduction and validation work.
Matched timing excludes execution errors and reconstructed-checkpoint timing, but
includes structurally invalid results: these durations do not establish usable
summaries. Warm and first-inference records remain distinguished in `trials.csv`.
Three repeats do not support reliable tail-percentile claims.

Resource peaks are sampled at 100 ms and can miss transients. Lifetime footprint
columns are separate. Supervisor and helper mappings can overlap; do not sum them
or add Metal allocations. CPU seconds are an activity proxy, not battery energy.
Filesystem cache state is uncontrolled. Power/thermal/background conditions vary.

The quality file is a saved review checkpoint, not a complete post-stop reassessment.
Some identical outputs share judgments, and final review counts need not equal
completed pipeline counts. No held-out inference or dedicated energy workload ran.

Re-exporting is read-only with respect to original evidence and refuses an existing
output directory. This performs no inference, downloads or live collection:

```sh
python3 benchmarks/model-eval/export_record.py \
  --run .local-docs/model-eval-2026-10-11/20261012T040851Z \
  --output /tmp/bye-public-record-new
```

See [recorded results](../RESULTS.md) for a readable interpretation. Original logs
are required to audit unsupported claims against real evidence; the public numeric
export alone cannot independently establish factual accuracy.
