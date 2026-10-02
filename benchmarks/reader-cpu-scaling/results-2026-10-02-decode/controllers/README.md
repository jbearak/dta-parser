# Rerun controller templates

These templates were not executed as published. The three local root
assignments changed, and the thread-sweep template now normalizes Linux peak
RSS from KiB to bytes. The original measurements ran on macOS, where the
value was already in bytes. The source map records both hashes and these
changes. A rerun records the modified controller's own hash.

Set these environment variables to absolute paths:

- `DTATOOLS_DECODE_WORK`: a private working directory for this follow-up.
- `DTATOOLS_PREVIOUS_READER_WORK`: the earlier reader-study working directory.
- `DTATOOLS_REPO`: the repository containing `benchmarks/r-file-readers`.

Copy the templates under their original filenames before invoking them:

```sh
mkdir -p "$DTATOOLS_DECODE_WORK"
cp controllers/thread-sweep.py "$DTATOOLS_DECODE_WORK/thread-sweep.py"
cp controllers/phase-benchmark.py "$DTATOOLS_DECODE_WORK/phase-benchmark.py"
python3 "$DTATOOLS_DECODE_WORK/thread-sweep.py"
python3 "$DTATOOLS_DECODE_WORK/phase-benchmark.py"
```

Run sequentially from this results directory in a quiet measurement window.
The controllers refuse existing output directories (`final-sweep` and
`final-arrow-phases`). They do not build packages or generate fixtures.

The previous-study directory must contain the independently verified
`candidate-final-v2` build, installed library and source snapshot,
`bindings-final-v2`, `controls.json`, and `final-large/provenance-before.json`.
The private controls manifest must identify the `india` case with actual
readable DTA/Arrow paths and dimensions. File hashes must match the bindings.
It is intentionally absent from this publication because it contains private
input paths. The phase run additionally requires `candidate-arrow-phases`
with its source, library, build receipt and diagnostic completion record,
plus `arrow-phase-caps.patch` and the preceding sweep qualification.
Preserve the original input bytes and required R dependencies, or generate
new consistent receipts/manifests for an explicitly different experiment.

Stock means the earlier final-v2 candidate, not the release baseline.
Diagnostic means the private Arrow phase-cap build; it does not include
the later gather change. Public threads remain 16 in the phase experiment;
decode/fill settings cap phases after normal admission. Raw observations,
qualification, pre/post bindings and result hashes are generated anew.

The published build records describe the original measurements. Environment
substitution does not make different source snapshots or inputs equivalent.
Neither transformed template has been rerun or otherwise execution-tested.
