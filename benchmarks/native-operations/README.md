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

Add `--arithmetic-only` to measure just `x * 2`, `x / 2` and `x + x` across
the same four widths, two file formats and three representations. This mode
checks 72 observations per build per round and omits the late-missing control.

## Measurement and checks

Each round uses a fresh R process per build and checks 248 unique observations
in the full comparison, or 72 in arithmetic-only mode.
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

## General arithmetic

The general arithmetic worker uses constructed million-row columns and preserves
the diagnostic `x * 1.01` and compact-plus-typed-double cases for int and float,
with and without missing values. It adds scalar addition and subtraction,
reverse subtraction and division, mixed int/float addition and multiplication,
and long/float addition. `x * 2` remains a control for the previous kernel.
Each build has 102 observations per round across compact, typed-double and bare
double inputs. Six balanced rounds produce 1,224 observations.

The general controller and source builder currently require the Unix R runtime
layout used on macOS and Linux; the general controller rejects Windows before
launching workers. This benchmark limitation does not change the package's
supported platforms.

Use the same clean-build steps above, then run with other CPU workloads stopped:

```sh
python3 benchmarks/native-operations/general-run.py \
  --baseline /private/tmp/native-ops-baseline \
  --candidate /private/tmp/native-ops-candidate \
  --output /private/tmp/general-arithmetic-results --rounds 6
```

This matrix needs no file fixtures. Its independent oracle applies Stata's
invalid-result normalization, storage promotion and final float rounding to
ordinary binary64 arithmetic. Every measured result is checked in full, together
with its missing mask, missing cache, storage and unchanged sources. Retained
chunks, noncanonical imports, all missing tags and extreme floating values are
covered by the package correctness tests, not by this throughput matrix.

To qualify the worker without recording timings:

```sh
Rscript --vanilla benchmarks/native-operations/general-worker.R \
  /private/tmp/native-ops-candidate/library 1 \
  /private/tmp/general-arithmetic-qualification.csv candidate qualify
```

Run `python3 benchmarks/native-operations/test-general-run.py` to check rejection
of incomplete matrices, invalid timings, changed results/source states/build
receipts, missing native dispatch and unbalanced observation orders. These tests
also pass under `python3 -O`; acceptance checks do not depend on Python assertions.

The [final general arithmetic acceptance](results-2026-10-02-general-arithmetic-v2.md)
reports all 34 cases, including the remaining gaps. The maintained general
controller resolves the exact Rscript used for workers, hashes that launcher
and its R runtime before and after the run, and requires the runtime to match
both clean-build receipts.
