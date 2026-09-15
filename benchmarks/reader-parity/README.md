# Reader parity experiments

This controller reruns Stata and both installed R readers on the same host.
It records reader elapsed time, R reader CPU time, process CPU time and peak
resident memory. Application startup is outside the reader clock; first reader
initialization remains inside fresh measurements. Warm measurements perform one
untimed read, then the manifest's number of repeated reads. Small warm cases use
100 calls to exceed timer resolution. A zero Stata median cannot pass the gate.

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
must be at most its matched Stata median in each cohort. All signatures qualify
before any timings. Build records bind installed files to source commits; worker,
input and Stata hashes are recorded. Inputs and installed files are checked again
after the run. No heavy builds or other benchmarks should run concurrently.

`--screen` permits a smaller diagnostic run. Such runs always report an unmet
release gate. `--case ID` and `--mode fresh` are screening controls. Candidate-only
`--experiment NAME=VALUE` accepts private `DTATOOLS_EXPERIMENT_` controls. The
baseline always runs without experimental environment variables.

The timing gate is only one release requirement. Correctness, downstream use,
native lifetime, peak memory relative to baseline variability, corpus behavior
and package/cross-language checks must pass before enabling an experiment by
default. Full and projected reads must pass independently. Cold filesystem
cache diagnostics must be reported separately.

Local job manifests and logs contain input paths and column names. Publish only
sanitized observations, summaries and binding records. The controller does not
publish anything or change the private survey files.
