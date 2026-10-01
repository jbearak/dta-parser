# R I/O optimization measurements

This directory contains comparisons of individual I/O optimization candidates
against the production code reviewed in PR #275. It is separate from the
[release comparison](../io-merge-review/README.md), which compares against
v0.10.0. Candidate screens guide implementation choices. They do not replace
the final comparison of the combined changes.

See the [2026-10-01 results](results-2026-10-01.md) for measurements,
rejected experiments, build bindings and correctness checks.

## Reader screen

`read-screen.py` measures one public `read_dta()` or `read_arrow()` call in each
fresh R process. It uses the existing
[reader worker](../reader-cpu-scaling/worker.R). The package is loaded before
the call timer starts. Arrow checksum verification stays enabled.

The input configuration uses the `reads` entries from the I/O release
comparison. Each entry supplies an opaque `id`, a DTA path, an Arrow path,
`rows`, and `columns`. Keep this configuration and worker logs private when
the input paths are sensitive.

```sh
python3 benchmarks/io-optimization/read-screen.py \
  --baseline /path/to/baseline-library \
  --candidate /path/to/candidate-library \
  --fixtures /path/to/private-configuration.json \
  --work /path/to/new-results-directory \
  --methods dta arrow --threads 1 0 --pairs 10
```

Use independently installed, frozen libraries and a new results directory.
Do not run builds, tests, profilers, or other benchmarks during a timing
window. Record the source revision, any source patch, build command,
toolchain, and build log for each library separately. The script binds the
installed package files, input bytes, R executable, runtime information,
and measurement scripts before and after the run.

Every format, fixture, thread limit, and library combination first runs in a
separate qualification process. Qualification checks the complete dataset
signature and shape. Signatures must agree across libraries, formats, and
thread limits for each fixture. Input hashing and qualification warm the
filesystem cache before timing. This is not a cold-storage benchmark.

Timing order alternates baseline-first and candidate-first within each case.
Cases rotate between pairs. The script requires an even number of pairs and
retains every observation in `raw.jsonl`. It records public-call wall and CPU
time, plus whole-process wall time, CPU time, and peak resident memory. Peak
memory therefore includes package loading and read setup. Linux and macOS
resource-usage units are normalized to bytes.

`summary.csv` reports medians and the median paired candidate/baseline ratio.
Its 95% intervals use 10,000 paired bootstrap resamples with a fixed seed.
If any clock pair has zero resolution, that metric retains its raw medians
but does not report a ratio or interval. All metrics need interpretation
together: a wall-time improvement alone does not establish lower CPU or
memory cost.

`qualification.json` and the two provenance records omit input paths.
Worker logs stay in the private results directory. Before publishing any
records, inspect them for sensitive paths or data and preserve the exact
measurement script version that produced them.

## Writer screen

The public R writers are `save_dta()` and `save_arrow()`. Writer comparisons
reuse the [paired runner](../io-merge-review/run.py) and its worker without
changing the timed boundary. Each fresh R process constructs or reads its
input, collects garbage, and times one public save call. Whole-process peak
memory includes input preparation. The ordinary fixtures contain numeric,
logical, temporal and character columns; the primary fixtures exercise
package-owned inputs.

Use the release comparison's private writer configuration with independently
installed libraries and a new `directory`. On macOS, run:

```sh
python3 benchmarks/io-optimization/write-provenance.py PRIVATE_CONFIG before
python3 benchmarks/io-merge-review/run.py PRIVATE_CONFIG writes --pairs 8
python3 benchmarks/io-optimization/write-provenance.py PRIVATE_CONFIG after
python3 benchmarks/io-merge-review/qualify.py PRIVATE_CONFIG outputs
```

The reused writer runner records macOS resource-usage units. Do not treat its
RSS values as bytes on other operating systems. It alternates library order,
rotates fixture order and retains every timing observation. Warning sequences
must match across libraries and repetitions. Output sizes must stay stable
within each library. Separate workers compare complete first and final output
signatures across libraries, then check that each writer preserves its input.
No signature computation or warm-up write precedes a timed save call.

## Source and build records

`record-builds.py PRIVATE_CONFIG NEW_OUTPUT_DIRECTORY` binds retained libraries
to frozen source snapshots and emits repository-relative source patches.
Its private configuration names the baseline revision and earlier provenance
record, plus each candidate's source directory, installed library and build
log. Compiled candidates must contain every base-tracked package file and
have identical source-build and installed DLLs. An R-only candidate explicitly
records its omitted native source files and verifies baseline DLL reuse.

Toolchain versions in these records are recording-time observations. Build
logs have separate hashes. The patches apply to the recorded base revision;
they reconstruct individual experiments, not separate release branches.
Run the recorder's tests with:

```sh
python3 benchmarks/io-optimization/test-record-builds.py -v
```
