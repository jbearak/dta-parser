# Reader parity experiments

The prepared DTA reader, wide numeric batches, four-slot observation ring,
and owned Arrow buffers are now enabled by default. The historical experiment
controls below apply only to older source revisions. The controller retains
them for reproducing those runs; its Stata parity threshold is a research
target, not a requirement for enabling these optimizations.

This controller reruns Stata and both installed R readers on the same host.
It records reader elapsed time, R reader CPU time, process CPU time and peak
resident memory. Application startup is outside the reader clock; first reader
initialization remains inside fresh measurements. Warm measurements perform one
untimed read, then the manifest's number of repeated reads. Small warm cases use
100 calls to exceed timer resolution. A timed interval shorter than ten
milliseconds is indeterminate and cannot pass, for either reader. Tiny fresh
cases may therefore remain unqualified even when the rounded medians match.

`prepare.R BASELINE_LIBRARY INPUTS_JSON ARROW_DIRECTORY CASES_JSON` creates
current-profile Arrow files once and checks full value/metadata signatures.
Inputs are objects with `id` and `path`. It freezes full reads and clustered and
scattered selections of 10, 30 and 60 columns where available. Each projection
has known-name, union-safe and metadata-discovery cases. Retained older Arrow
files belong in compatibility tests rather than these timing comparisons.

Install each clean source with `benchmarks/reader-refresh/install.py`. Then run:

```sh
python3 benchmarks/reader-parity/run.py \
  --cases /absolute/local/cases.json --output /absolute/local/results \
  --baseline-library /absolute/baseline-library --baseline-build /absolute/baseline-build.json \
  --candidate-library /absolute/candidate-library --candidate-build /absolute/candidate-build.json
```

Defaults are two independent cohorts, 20 observations per method/case/cohort,
and both fresh and warm modes. Forward and reversed rotations balance method
positions and pair order. Cases reverse between cohorts. Every candidate median
must be at most its matched Stata median in each cohort. Baseline/candidate R
value and metadata signatures qualify before timing. Stata loads the same DTA
and checks dimensions; Stata value/metadata conformance is a separate gate.
Build records bind installed files to source commits; worker,
input and Stata hashes are recorded. Inputs and installed files are checked again
after the run. No heavy builds or other benchmarks should run concurrently.

`qualify-corpus.py` compares full signatures, dimensions, warnings and failure
messages across the two installations. Its input list contains `id`, `path` and
`reader` fields, with reader set to `read_dta` or `read_arrow`. Use this separately
for a larger DTA corpus and retained older Arrow files. Per-file paths and error
messages stay in local records; the summary uses opaque input IDs.

`--qualify-only` checks signatures and dimensions without attempting timings.
`--screen` permits a smaller diagnostic run. Such runs always report an unmet
release gate. `--case ID` and `--mode fresh` are screening controls. Candidate-only
`--experiment NAME=VALUE` accepts private `DTATOOLS_EXPERIMENT_` controls. The
baseline always runs without experimental environment variables.

`downstream.py` compares sums over up to 30 numeric columns, full signatures,
first writes with a captured copy, and conversion to ordinary R numeric storage.
It records both consumer time and each observation's complete load-and-use time.
The first-write setup is outside the consumer clock but inside the complete
workflow clock. Results and captured-copy isolation are checked after mutation.
Process peak memory includes loading and consumption. Warm reader peaks include
the warmup and repeated calls, including overlapping old/new R result lifetimes;
they are not estimates of one retained result's size.

The controller's timing gate assesses the original Stata parity target.
Reader changes also need checks of correctness, downstream use,
native lifetime, memory use, corpus behavior and package/cross-language behavior,
with full and projected reads considered independently. Cold filesystem cache
diagnostics must be reported separately.

Local job manifests and logs contain input paths and column names. Publish only
sanitized observations, summaries and binding records. The controller does not
publish anything or change the private survey files.

## Four-reader India comparison

`india.py` runs ten fresh processes each for `read_dta()`, verified
`read_arrow()`, `haven::read_dta()`, and Stata `use`. It selects a full-read
case from the same case manifest and binds the dtatools installation to its
build record. Each rotated method order is followed by its reverse, balancing
which tool runs before another. Input hashing warms the filesystem cache before
the sequential runs. The controller does not flush or rewarm that cache between
observations, add an in-process warmup, or request extra garbage collection.

This example uses the current reader defaults:

```sh
python3 benchmarks/reader-parity/india.py \
  --cases /absolute/local/cases.json --case india-all \
  --library /absolute/candidate-library --build /absolute/candidate-build.json \
  --output /absolute/local/india-results
```

For older source revisions, supply each experimental control explicitly; the
result binding records them.
The controller removes experimental environment variables from haven and Stata.
`--smoke` runs one round on a small case to check the worker protocol. Its
timings are marked as smoke results and should not be published as benchmarks.

Read wall time excludes process startup and includes first-call reader work.
Process CPU time is user plus system time from `wait4` for every tool. Process
CPU and peak resident memory cover the whole fresh process, including startup,
package loading and shutdown. R read-call CPU is also recorded separately.
These distinct time intervals should not be used to calculate CPU utilization.

The controller checks dimensions after every read and verifies input,
installation, runtime and worker bindings at completion. Run full semantic
qualification separately so signature traversal does not inflate resource
measurements. Observations are saved after each successful read; `COMPLETE`
appears only after every read and the final binding check succeed. This focused
comparison does not satisfy the broader reader-parity release gate.
