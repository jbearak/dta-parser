# Native numeric operation benchmarks

This comparison measures public operations on compact Stata columns and
ordinary doubles. It covers tagged-missing inspection, `anyNA()`, totals,
row totals, mean, range, `summ()`, matching, membership, multiplication,
division and column addition. Reader calls are outside the measured interval.
Arithmetic also includes `dta_double` controls, which apply the same missing
and result-validation rules while retaining ordinary double storage.
Compact results can additionally require narrower storage and promotion;
the typed-double control does not impose an identical destination format.

The four file-backed inputs are million-row byte, int, long and float columns
from the deterministic DTA/Arrow fixtures in
[`r-file-readers/prepare.R`](../r-file-readers/prepare.R). They contain periodic
system missing values. A separate constructed/retained control places the
only missing value in the final row to measure cached `anyNA()` counts.

## Reproduce

Commit the candidate package first. The existing source builder requires its
file set to match the chosen Git commit, including newly added native modules.
Use new private directories for each clean build:

```sh
python3 benchmarks/r-file-readers/build-snapshot.py \
  --variant baseline --base-commit BASELINE_COMMIT \
  --work /private/tmp/native-ops-baseline
python3 benchmarks/r-file-readers/build-snapshot.py \
  --variant candidate --base-commit CANDIDATE_COMMIT \
  --source r-package/dtatools --work /private/tmp/native-ops-candidate
```

Generate the fixtures using the baseline library and the instructions in
[the reader comparison](../r-file-readers/README.md#generate-and-qualify-inputs).
The compact fixture must contain one million rows. With other builds and tests
stopped on the measurement host, run:

```sh
python3 benchmarks/native-operations/run.py \
  --baseline /private/tmp/native-ops-baseline \
  --candidate /private/tmp/native-ops-candidate \
  --fixtures /private/tmp/reader-inputs \
  --output /private/tmp/native-ops-results --rounds 6
```

Each build directory must have a valid clean-build receipt. The controller
checks its full Git source identity, source inventory, compiler inputs and
log, installed package inventory, and built/installed DLL equality before
and after timing. It also records fixture and controller hashes and the exact
source delta. An unchanged DLL beside edited sources is insufficient.

## Measurement and checks

Each round uses a fresh R process per build and checks 248 unique observations.
The round count must be a positive multiple of six, so build and arithmetic
orders are balanced. The protocol identifies the baseline by its receipt's
Git commit.
Build order alternates between rounds; case order is fixed. Two-representation
order alternates. Arithmetic rotates and reverses its three representations
across the six rounds. Untimed qualification
warms dispatch. Untimed calibration runs for at least 20 ms and selects a fixed
repetition count targeting 150 ms for the retained interval. Counts are
recorded separately for each observation. Times include public dispatch,
result allocation and automatic garbage collection. Fixture reads, explicit
garbage collection, calibration, qualification and result hashing are excluded.

The worker checks result bytes and output storage against ordinary controls,
using independent base references where their semantics agree. It also checks
full summary objects across builds, source values and compact state, and
actual native entry counts for candidate arithmetic. `summ()` uses the same
public operation on ordinary doubles as its numeric reference; its separate
unit tests compare with the previous calculation and Stata's oracle.

The controller reports median CPU and wall time per call. Inspect retained
interval lengths before interpreting ratios; 150 ms is a calibration target,
not an enforced timing threshold. Performance thresholds are not CI tests.

These are warm-operation measurements on one host. They do not measure
read-plus-consume latency or establish universal parity. File fixtures have
system missing values, matching uses self-lookup, and summaries are unweighted
and use default options. Tag-rich data, nonmatching lookups, detailed
summaries, row maxima and other untimed operations need separate throughput
measurements.
