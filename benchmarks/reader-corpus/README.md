# Full-corpus DTA and Arrow reads

See the [September 16 results](results-2026-09-16/README.md).

This benchmark measures the default-enabled readers on the original 1,823-file
DHS, MICS and NSFG inventory. Each readable DTA file is converted to the current
Arrow profile before timing, with matching full data-and-metadata signatures.
Malformed DTA inputs remain recorded as failures and cannot produce Arrow files.
All 1,812 historically comparable inputs must qualify for both formats.

Install the package from a clean checkout with
[the installation driver](../reader-refresh/install.py), then run:

~~~sh
python3 benchmarks/reader-corpus/run.py \
  --library "$LIBRARY" --build-record "$BUILD_RECORD" \
  --source-root "$SOURCE_ROOT" --data-root "$DATA_ROOT" \
  --output "$NEW_PRIVATE_OUTPUT"
~~~

The data root is the original repository's target directory, containing the
archived August 24 inventory and comparator rows. The output directory must not
exist. Use `--cache` to override `/opt/aww_cache`. Use `--smoke` to check one
readable input per corpus, the wide India input, and the original malformed
inputs; smoke results are not a full-corpus benchmark.

Preparation finishes before any timed reads. Each file is read once per format
in a fresh R process, with automatic thread selection and Arrow verification
enabled. Files and formats run sequentially. Reader order alternates across files.
The timed worker accepts command-line arguments and prints results using base R.
It checks that `jsonlite` is absent before and after reading. Python validates
the results and writes the JSON records. The separate preparation process uses
`jsonlite`, and exits before timing begins.

Hashing both input files before
each pair warms their filesystem cache; there is no in-process warmup or added
pre-read garbage collection. The read-call clock excludes package loading but
includes first-reader initialization. Results remain live until process exit.

Whole-process CPU time and peak RSS include startup, package loading and
shutdown. Read-call CPU is recorded separately. Conversion, signature checks
and input hashing are outside all reported read and process measurements.
The package, worker scripts, retained evidence and input hashes are checked
again before the run receives its COMPLETE marker.

Run the observation-parser checks with
`python3 -m unittest discover -s benchmarks/reader-corpus -p test_run.py`.

The comparable-file summaries sum read times over the frozen 1,812-file set.
They are batch totals from one observation per file, not repeated-read medians.
Haven and Stata rows are retained unchanged from August 24, 2026; neither tool
is rerun. Comparisons against them span measurement dates. Both new formats use
the same input set, and Arrow conversion cost is excluded.

Keep the output directory private: it contains survey copies, paths, signatures
and child logs. Publish aggregate tables and sanitized provenance only.
