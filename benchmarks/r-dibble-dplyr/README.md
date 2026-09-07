# Dibble dplyr overhead

This benchmark compares the same Stata column objects in a tibble and a dibble.
It separates container restoration from Stata vector semantics. Fixture creation
and correctness checks are outside the timed expressions. Timings include GC;
memory is cumulative R allocation, not peak RSS or total native allocation.

The [2026-09-05 report](results-2026-09-05.md) records the baseline and a narrow
validation prototype. The [implementation plan](../../docs/plans/dibble-result-performance.md)
describes the staged architecture. Later dated reports record production changes
and keep their exact source revisions separate from the initial prototype.


## Stage 4 implementation review fixes

The [review-fix report](results-2026-09-07-stage4-review-fix.md) and
[indexed evidence](results-2026-09-07-stage4-review-fix/README.md) qualify
`c8ca0a4a74c7ef6aa811d78b3422979e9007b1fe`. Fresh constructors avoid the
unnecessary first-private-write payload copy, width scans release temporary
encoding buffers, and the native runner rejects every nonempty destination.
The complete local gates and fresh paired baseline/candidate matrix pass their
behavioral, allocation and memory checks. The same fifteen read flags remain:
twelve base-R operations and three delegated filters. Stage 6 must resolve the
filter regressions; integrated performance acceptance remains open.

The new archive preserves failed attempts, exact source/installation identities,
all fresh five-gate Cargo input snapshots and raw paired results. Run its
`verify.py` to check archived bytes and executable bits without running workloads.
The previous dated report and merged review supplement retain their original
bytes and qualification scope. PR #195 still requires final substantive review,
CI and normal merge on its eventual reviewed head.

The diagnosis and local qualification records merged through
[PR #198](https://github.com/jbearak/dta-parser/pull/198), followed by the paired
benchmark evidence in [PR #199](https://github.com/jbearak/dta-parser/pull/199).
Their additive [output-content record](results-2026-09-07-stage4-output-integrity/README.md)
provides full-byte SHA-256 equality at both checkpoints of one fresh isolated
c8 fertility run. The separate [comparison-identity audit](results-2026-09-07-stage4-comparison-integrity/README.md)
binds the unchanged paired results to all six manifests and three comparators,
with 87 small guard cases. Neither supplement rewrites historical records,
claims absence of transient restored writes, or supplies new benchmark timings.
The final actual fertility renv install/test/restore remains open.

These evidence changes preserve the separately qualified c8 package and runner
identities. The later two preflight helper docstrings leave its executable AST
unchanged; archived c8 executions retain their original input hash.

## Stage 4 review supplement

The [review supplement](results-2026-09-07-stage4-review-supplement/README.md),
submitted as [PR #197](https://github.com/jbearak/dta-parser/pull/197) at
`0bb559e80af119264f87c4fcd06a65287230db0d`, adds missing review inputs,
executable command fixtures and guarded diagnostic replay. The original
[Stage 4 report](results-2026-09-07-stage4.md) and historical artifacts retain
their bytes and measured-source labels.

The earlier three-Git-object comparison did not prove which working files the
reused Rust workspace commands read. The supplement's
[fresh five-gate manifest](results-2026-09-07-stage4-review-supplement/workspace-gates/manifest.json)
supersedes that insufficient binding. Formatting, Clippy, 278 tests,
documentation and verified packaging passed on a clean checkout of
`e343b3b56a8529e9ee0ac40f8bd88beebcd2be15`, with complete 1,060-file
byte/mode inventories and clean status checked before and after every command.
Packaging used no `--allow-dirty`; its eleven existing warnings concern excluded
test targets. The [crate record](results-2026-09-07-stage4-review-supplement/workspace-gates/package-artifact.json)
binds the actual verified artifact and all 27 members. The separate R check
retains three established warnings and two notes.

These additions do not resolve the fifteen disclosed read flags. The three
filter regressions remain required Stage 6 work; twelve per-element costs remain
visible, with integrated performance acceptance still open. Stages 5–9, a fresh
merged-main installation and tests in the actual fertility renv, and restoration
from its original lockfile remain required. Issue #172 stays open. Substantive
external review, CI and normal merges are separate gates.

## Reproduce

Run from the repository root. Install `bench`, `dplyr`, and the package's test
dependencies first. Build the package source being measured into an isolated
library; do not use an older globally installed dtatools.

```sh
benchmark_source=$(git rev-parse HEAD)
git diff --exit-code "$benchmark_source" -- r-package/dtatools
benchmark_root=$(mktemp -d /tmp/dibble-dplyr-benchmark.XXXXXX)
Rscript --vanilla benchmarks/r-dibble-dplyr/install.R \
  "$benchmark_root/library" "$benchmark_source"
R_LIBS="$benchmark_root/library" Rscript --vanilla -e \
  'library(dtatools); testthat::test_local(commandArgs(TRUE)[1], filter="dibble|reference-copy|dta-string|dta-numeric|mutate-data|slice-dta-rows", load_package="installed", stop_on_failure=TRUE)' \
  "r-package/dtatools"
Rscript --vanilla benchmarks/r-dibble-dplyr/run.R \
  "$benchmark_root/library" "$benchmark_root/results" "$benchmark_source" 7
Rscript --vanilla benchmarks/r-dibble-dplyr/prototype.R \
  "$benchmark_root/library" "$benchmark_root/prototype"
```

The installer exports only tracked package files from the resolved revision,
builds its source archive and installs into a library without an existing
dtatools package. After successful installation it records the full source SHA,
package-tree ID, archive hash and installed-file hashes in a sidecar. Runners
that accept SOURCE_SHA validate that sidecar before creating result directories
or writing measurements, and retain the loaded-library path assertion. Missing
provenance, a mismatched SHA or a changed installation fails before output.
For an implementation comparison, install each recorded commit this way. `DTATOOLS_BENCH_KINDS` can restrict
the comma-separated storage kinds for a targeted rerun.

`run.R` checks equivalent result values and column attributes, input preservation,
and compact source backing before every paired timing. It measures rename,
selection, symbol replacement, row filtering, five successive mutations, and
numeric arithmetic across tall, wide, compact, ordinary, and mixed tables.
`stages.csv` measures constituent routines separately; those medians are not an
additive profile of the complete operation.

`prototype.R` changes no installed namespace or package source. It clones the
existing constructor into a private environment, bypasses validation after
proving that rename returned the source vectors, and retains all current column
isolation. It verifies output metadata and both directions of later mutation.
It is an experiment for column-only operations, not a general implementation.

`check-rename-allocation.R LIBRARY` intentionally fails on the baseline. It
bounds both the largest and summed recorded allocations below one retained
double payload. This small check records allocations above 10,000 bytes;
`owned-double.R` separately checks unthresholded cumulative allocation.
Stage 3 requires this check to pass; it remains separate from the CI workflow.

The dated result directory contains raw CSV files and package versions. The
package build/check result and exact baseline revision are recorded in the report.

## Direct column stage

`columns.R LIBRARY OUTPUT_DIRECTORY SOURCE_SHA` compares direct column methods
with whole-verb delegation through the same installed safe finalizer. It checks
values and metadata before timing, records nominal retained R object sizes
separately, and enforces the stage 1 limit of 130 MB for a 1M by 16 ordinary
string rename. It does not replace the future owned-backing allocation gate.
Run from the repository root with an isolated build of the recorded revision.
The historical reports and their revision labels remain unchanged.


## Direct row stage

`run-rows.R LIBRARY OUTPUT_DIRECTORY SOURCE_SHA [ITERATIONS]` measures ordinary
row brackets, the explicit helper, the dplyr row hook and the shared gatherer.
Tall and wide fixtures cover ordinary doubles/strings, compact integers and
dictionary strings, mixed columns, logicals and converted factors. Grouped
fixtures separately measure reconstruction, validation and delegated filter/
mutate consumers at 10,000, 100,000 and 1,000,000 rows. The default is nine
iterations with GC included. All fixtures and public equivalence checks are
outside timing; the runner rejects an unintended library, asserts dibble and
compact fixture preconditions, and records its own file hash.

The source oracle is serialized before operations and compared afterward.
Full-row result comparisons use a separate deserialized oracle so they cannot
materialize source ALTREP columns through a shared comparison target. Source
values, attributes and compact state are checked before and after timing.
`gather_only` isolates the common gather path but is not an additive timing
component of the public operation.

`row-memory.R LIBRARY KIND SOURCE_SHA` records the retained R vector-heap
increase after GC for a one-million-row, sixteen-column half-row subset.
Wrap that separate process with the platform's peak-RSS tool, such as
`/usr/bin/time -l` on macOS. Its peak includes startup, fixtures and validation;
it is not peak memory attributable only to the row operation. These retained
and process-peak measurements are distinct from `bench` cumulative allocation.

The [Stage 2 report](results-2026-09-06-stage2.md) records the exact final pair,
the small grouped-reconstruction regression, retained heap and process peaks.
`repeat-group-reconstruct.R LIBRARY OUTPUT_CSV SOURCE_SHA` repeats that
10,000-row, 1,000-group case with three independent fixtures and fifteen
iterations, retaining source and output guards outside timing.

Run `test-provenance.R LIBRARY SOURCE_SHA` against a fresh `install.R` library
for the bounded guard checks. It exercises every SOURCE_SHA runner with missing,
mismatched, malformed and changed installation metadata, asserts no result
output on rejection, and checks locale-independent fingerprints and matching
result output. It also checks all owned-runner dependency identities and detects
a change confined to the shared `helpers.R`. Older dated artifacts keep their
recorded runner versions and manual exact-install verification; do not add
provenance to an old library.

## Owned ordinary-double stage

The [Stage 3 report](results-2026-09-06-stage3.md) records the exact final pair,
the rejected first candidate and its read regressions, native mutation gates,
retained heap and process peaks. Run the following from a clean checkout with
the runner files from the candidate revision. Each library is created by the
provenance installer described above; the reported comparison uses Stage 2
`fd069a36832ed7c1bdedeed52a4281ecabb36e25` and candidate
`08b086ccd338d394420112cf9f550d355e94cb24`. The final runner identities include
`helpers.R`, both entry points and `owned-double-helpers.R`. Earlier owned-run
records listed in the report omitted `helpers.R`; the separate `historical-*`
manifests already include it. The report preserves those records and distinguishes
them from the final qualification.

```sh
owned_bench_root=$(mktemp -d /tmp/dibble-owned-benchmark.XXXXXX)
owned_baseline=fd069a36832ed7c1bdedeed52a4281ecabb36e25
owned_candidate=08b086ccd338d394420112cf9f550d355e94cb24
Rscript --vanilla benchmarks/r-dibble-dplyr/install.R \
  "$owned_bench_root/baseline-library" "$owned_baseline"
Rscript --vanilla benchmarks/r-dibble-dplyr/install.R \
  "$owned_bench_root/candidate-library" "$owned_candidate"
Rscript --vanilla benchmarks/r-dibble-dplyr/owned-double.R \
  "$owned_bench_root/baseline-library" "$owned_bench_root/baseline" \
  "$owned_baseline" baseline 7
Rscript --vanilla benchmarks/r-dibble-dplyr/owned-double.R \
  "$owned_bench_root/candidate-library" "$owned_bench_root/candidate" \
  "$owned_candidate" candidate 7
Rscript --vanilla benchmarks/r-dibble-dplyr/check-rename-allocation.R \
  "$owned_bench_root/candidate-library"
```

`owned-double.R` checks tenfold row scaling for selectors, direct and safe
delegated five-verb pipelines, aggregates, arithmetic, filtering, coercion and
DTA/Arrow reads and writes. Every read/export is followed by a selector that
checks backing and allocation. First shared capture, subsequent private sparse
writes and full replacement are measured separately. Nested string RHS and
arithmetic row expressions retain their separate snapshot cost and alias checks.
Fixtures and independent source/result checks stay outside measurements.

`owned-double-memory.R LIBRARY SOURCE_SHA baseline|candidate OPERATION ROWS`
measures retained heap and release after rename, `pipeline_five` or `pipeline_50`.
Run each operation at 100,000 and 1,000,000 rows in its own process, for both
libraries. On macOS, one case is:

```sh
/usr/bin/time -l Rscript --vanilla benchmarks/r-dibble-dplyr/owned-double-memory.R \
  "$owned_bench_root/candidate-library" "$owned_candidate" candidate \
  pipeline_50 1000000
```

Run timed processes serially, without concurrent builds or tests. Retained heap,
nominal object sizes and whole-process peak RSS answer different questions.
Native copy counters overlap R allocation and one another; do not add them into
a total. The [reference-mutation runner](../r-reference-mutation/README.md)
also qualifies assigned capacity preparation and separately measured borrowed
capture before strict private writes. It preserves all 159 original assertions
and their original numerical limits. Zero Rprofmem bytes above a threshold does
not mean zero total allocation.

The [current qualification driver](run-owned-qualification.py) records complete
runner identities and output manifests for the same workloads. It checks
committed runner bytes, process results and runtime identities with explicit
exceptions that remain active under Python optimization. It refuses existing
operation output and opens each memory log exclusively. Failed attempts retain
their diagnostic files; use a new output directory when retrying. For the
candidate, after installing the library above and arranging a quiet window:

```sh
python3 benchmarks/r-dibble-dplyr/run-owned-qualification.py operations . \
  "$owned_bench_root/qualified-candidate" "$owned_bench_root/candidate-library" \
  "$owned_candidate" "$owned_candidate" candidate
python3 benchmarks/r-dibble-dplyr/run-owned-qualification.py memory . \
  "$owned_bench_root/qualified-candidate" "$owned_bench_root/candidate-library" \
  "$owned_candidate" "$owned_candidate" candidate
```

Use the baseline library and source with a separate output directory for the
paired baseline, keeping the candidate runner revision. The memory command uses
macOS `/usr/bin/time -l`. Run the driver's CLI regression checks with
`python3 benchmarks/r-dibble-dplyr/test-owned-qualification.py`. They exercise
normal Python, `-O` and `PYTHONOPTIMIZE=1` using disposable Git fixtures and
synthetic subprocess output; they do not run R workloads.

## Owned strings, logicals and integer backing

`owned-atomic.R` qualifies ordinary `dta_string`, declared character, logical,
factor and ordered-factor columns. The public dibble constructor continues to
promote bare integer columns to Stata numeric storage, so factors exercise the
table's ordinary integer backing. The native mutation qualification separately
covers captured bare integer values. Public `replace_values()` continues to
reject factor targets; the public write matrix covers both string forms and
logicals.

The operation matrix contains 206 rows: direct and equally safe delegated
selectors and five-verb pipelines, plus applicable reads, aggregates, coercions,
exports, filtering, row subsets and DTA/Arrow I/O. All five types use 100,000 and
1,000,000 rows. Selectors use 16 columns; reads use eight. There are also 126
post-read selector checks and 18 separate first shared, subsequent private and
full-replacement write profiles. Private-write preparation and measurement
change different rows. A later source write checks the reverse direction of
result isolation.

Deterministic ordinary vectors supply independent value, type and column
attribute oracles. Table metadata checks include compact row-name bookkeeping.
File-format expectations explicitly include DTA's logical-to-byte and
factor-to-labelled-long conversions and Arrow's preservation of logicals and
factor levels. The runner checks the expected factor conversion warning; other
warnings remain visible. The DTA writer wrapper collects and checks that warning
inside each measured call in both revisions. Fixture creation and all value and
metadata oracle checks occur outside timing and allocation profiles. The
profiled result and `bench`'s retained
preflight result are checked as well as the initial result. Writers' final timed
files are reopened and compared with the independent oracle.

The source backing is checked before and after each read, profile and timed
phase. Returned aliases remain alive through the subsequent selector. Candidate
selectors must allocate under 1 MB and copy no payloads. Private string scan
counters also require zero unchanged-column validation scans, because low R
allocation alone cannot establish that values were not scanned. Scan counts,
cumulative R allocations and overlapping native byte counters remain separate.

Use `run-atomic-qualification.py` with fresh `install.R` libraries and committed
runner files. It guards its own source and all five R dependencies, including
the shared `helpers.R`, and records runtime identities and SHA-256 manifests.
Both installations must use the same runner revision. For an exact candidate
commit in `atomic_candidate` and a quiet measurement window:

```sh
atomic_bench_root=$(mktemp -d /tmp/dibble-atomic-benchmark.XXXXXX)
atomic_baseline=ec10a6ac34602f3bd691e8043019c1b479babda4
Rscript --vanilla benchmarks/r-dibble-dplyr/install.R \
  "$atomic_bench_root/baseline-library" "$atomic_baseline"
Rscript --vanilla benchmarks/r-dibble-dplyr/install.R \
  "$atomic_bench_root/candidate-library" "$atomic_candidate"
python3 benchmarks/r-dibble-dplyr/run-atomic-qualification.py operations . \
  "$atomic_bench_root/baseline" "$atomic_bench_root/baseline-library" \
  "$atomic_baseline" "$atomic_candidate" baseline
python3 benchmarks/r-dibble-dplyr/run-atomic-qualification.py operations . \
  "$atomic_bench_root/candidate" "$atomic_bench_root/candidate-library" \
  "$atomic_candidate" "$atomic_candidate" candidate
python3 benchmarks/r-dibble-dplyr/run-atomic-qualification.py memory . \
  "$atomic_bench_root/baseline" "$atomic_bench_root/baseline-library" \
  "$atomic_baseline" "$atomic_candidate" baseline
python3 benchmarks/r-dibble-dplyr/run-atomic-qualification.py memory . \
  "$atomic_bench_root/candidate" "$atomic_bench_root/candidate-library" \
  "$atomic_candidate" "$atomic_candidate" candidate
```

Each memory command launches 30 isolated macOS processes: rename, five verbs
and 50 verbs, at both row counts, for all five types. It checks flat handle depth,
backing identity, retained heap with source and result alive, and release after
the last result is dropped. Whole-process peak RSS includes startup, fixtures
and validation, so it is not an operation-only allocation peak.

The driver rejects existing operation directories and memory logs, verifies
complete case matrices and existing evidence hashes, and preserves failed-run
diagnostics. Use a new output directory for a retry. Its explicit integrity
exceptions remain enabled under Python optimization. Run
`python3 benchmarks/r-dibble-dplyr/test-atomic-qualification.py` for the 87
synthetic CLI guard cases across default Python, `-O` and `PYTHONOPTIMIZE=1`.
These guard tests perform no R timing. The Stage 3 runners and historical raw
evidence keep their original bytes and identities.
## Retained header and vector heap supplement

`owned-heap.R` sources the existing atomic or double memory runner unchanged
in a local evaluation environment, then reads its five `gc()` checkpoints.
This is a separate measurement. It includes R header cells, which the earlier
vector-heap measurements omit, and is useful when an owned backing record uses
an external pointer. No namespace is patched. The local argument adapter only
supplies the original runner's expected command-line arguments.

The wrapper reports raw header-cell counts and vector bytes. It infers the
unique integer header size consistent with all five cell counts and R's reported
MB totals, which are rounded upward to 0.1 MiB. It fails if the size is ambiguous.
The Python driver independently checks that inference and every reported heap
delta. Header bytes plus vector bytes measure used R heap; they exclude external
native allocations, unused heap capacity, and process overhead. The existing
peak-RSS runs retain their separate whole-process interpretation. Small residual
heap after dropping the result can include fixed bookkeeping and caches.

After committing the wrapper and driver, run each side in a quiet window:

```sh
python3 benchmarks/r-dibble-dplyr/run-heap-qualification.py REPO NEW_OUTPUT LIBRARY SOURCE_SHA RUNNER_SHA baseline
python3 benchmarks/r-dibble-dplyr/run-heap-qualification.py REPO NEW_OUTPUT LIBRARY SOURCE_SHA RUNNER_SHA candidate
```

Use full commit identities and a fresh output directory for each command. The
driver binds its own bytes and all eight R dependencies to `RUNNER_SHA`; the R
wrapper records and rechecks their runtime identities. Every process validates
the exact installed package before and after its workload. The matrix has 36
fresh processes per side: doubles and the five atomic kinds, 100k/1M rows, and
rename/five-verb/fifty-verb operations. Existing value, metadata, backing, depth
and vector-heap checks remain active. Candidates must also retain less than
1 MB of combined tracked R heap with source and result alive and leave less than
1 MB above the reference-free checkpoint after both are dropped. The supplement
reports no operation timing and does not replace the original qualification.
