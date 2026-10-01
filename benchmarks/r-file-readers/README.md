# R file-reader comparisons

This runner compares base R and installed high-performance package readers
with explicit `dtatools::read_dta()` and `read_arrow()` tibble and dibble
outputs. Every external reader returns a tibble. Results inheriting from
`tbl_df` retain their native tibble subclass without conversion. Other results
pass through `as_tibble()` inside the reader timer. The worker checks the
resulting container outside that timer. The benchmark compares file formats
and their public R readers together; different formats do different work.

| Method | Input | Public call before any needed tibble conversion |
| --- | --- | --- |
| `base_csv` | CSV | `utils::read.csv()` |
| `base_rds` | uncompressed RDS v3 | `readRDS()` |
| `fread` | CSV | `data.table::fread()` |
| `readr` | CSV | `readr::read_csv(lazy = FALSE)` |
| `vroom_eager` | CSV | `vroom::vroom(altrep = FALSE)` |
| `vroom_lazy` | CSV | `vroom::vroom(altrep = TRUE)` |
| `haven` | DTA | `haven::read_dta()` |
| `arrow` | uncompressed generic Feather v2 | `arrow::read_feather(as_data_frame = TRUE)` |
| `fst` | fst default compression | `fst::read_fst()` |
| `qs2` | qs2 level 3 with byte shuffle | `qs2::qs_read(validate_checksum = TRUE)` |
| `dtatools_dta_tibble`, `dtatools_dta_dibble` | DTA | explicit `output`, default numeric ALTREP |
| `dtatools_arrow_tibble`, `dtatools_arrow_dibble` | profiled uncompressed Arrow IPC | explicit `output`, `verify = TRUE` |

Missing packages or input formats appear in `unavailable.json`. No reader is
substituted. The runner preserves additional dependency libraries in `R_LIBS`
after prepending each selected dtatools library. Base CSV performs its normal type inference. CSV readers retain
their package defaults for schema inference, with progress and type reports
disabled. Arrow's generic Feather input has no dtatools profile or checksums.
The dtatools Arrow input preserves the DTA's schema and checksums, so the
Arrow package and dtatools cases include different metadata work.

## Build and bind acceptance libraries

Set `READER_BASE_COMMIT` to the full Git commit used as the baseline. Build
both variants through `build-snapshot.py`, using new private directories:

```sh
python3 benchmarks/r-file-readers/build-snapshot.py \
  --variant baseline --base-commit "$READER_BASE_COMMIT" \
  --work /private/tmp/reader-build-baseline
python3 benchmarks/r-file-readers/build-snapshot.py \
  --variant candidate --base-commit "$READER_BASE_COMMIT" \
  --source r-package/dtatools --work /private/tmp/reader-build-candidate
```

The baseline uses the exact Git package contents. The candidate captures the
working package, whose file set and modes must match that baseline. The
wrapper preserves a source snapshot, installs from a separate build copy,
and records source hashes before and after installation. Each successful
work directory contains `library/`, `build-receipt.json`, `input-record.json`,
`source.patch`, and private build logs and command/environment records.

Save this configuration as `/private/tmp/reader-builds.json`. Its values name
the work directories, not their `library/` children:

```json
{
  "baseline": "/private/tmp/reader-build-baseline",
  "candidate": "/private/tmp/reader-build-candidate"
}
```

Then verify the receipts and write the publication records:

```sh
python3 benchmarks/r-file-readers/record-builds.py \
  /private/tmp/reader-builds.json /private/tmp/reader-build-records
```

The recorder checks the preserved sources, installed package inventories,
source-build/installed DLL equality, tool identities and build receipts. It
replays both source patches against the Git base before emitting
`build-bindings.json`, `baseline.patch`, and `candidate.patch`. Keep the
builder, recorder and shared I/O recorder helper unchanged between these
steps; their hashes are part of each receipt. Historical installations do
not supply acceptance build receipts.

## Generate and qualify inputs

Use separate installed baseline and candidate libraries. Keep generated
files, configurations and worker logs in a private directory outside Git.
Run preparation with the baseline library. This example makes two 200,000-row
fixtures and one 1,000,000-row compact-numeric fixture, each 32 columns wide:

```sh
DTATOOLS_BENCH_LIB=/path/to/baseline-library \
  Rscript --vanilla benchmarks/r-file-readers/prepare.R \
  /private/tmp/reader-inputs 200000 1000000
python3 benchmarks/r-file-readers/run.py \
  --baseline /path/to/baseline-library \
  --candidate /path/to/candidate-library \
  --fixtures /private/tmp/reader-inputs/fixtures.json \
  --work /private/tmp/reader-qualification --qualify-only
```

To add a wide fixture while retaining the original three entries and their
paths, write a separate combined manifest:

```sh
DTATOOLS_BENCH_LIB=/path/to/baseline-library \
  Rscript --vanilla benchmarks/r-file-readers/prepare-wide.R \
  /private/tmp/reader-inputs/fixtures.json /private/tmp/reader-wide-inputs
```

The added fixture has 128 rows and 4,096 columns. It cycles through the five
numeric Stata storage types, three numeric display formats and 16 shared
value-label groups. Plain external formats preserve only the independent
values. This fixture measures per-column setup where column count dominates
row count. Its new manifest preserves the existing input manifest and records
its hash. Optional final arguments override column count and row count for a
smoke check.

All fixtures are deterministic. The numeric fixture has 32 double columns.
The mixed fixture has 16 double columns, eight repeated UTF-8 category strings
and eight varied ASCII strings. These categories are character columns rather
than factors, so CSV, DTA and generic Feather represent the same values.
The compact fixture has eight byte, eight int, eight long, six float and two
double columns with explicit Stata storage. Numeric values use exact binary
fractions and periodic missing values. Strings are nonmissing and nonempty;
this suite does not measure DTA's empty-string/missing distinction.

The compact and wide DTAs use `dtatools::save_dta(version = 19)`; other inputs use
`haven::write_dta(version = 15)`. Every profiled Arrow input is saved from its
DTA import and has the same complete `datasig()` signature. Generic Feather,
CSV and RDS are written directly from independently generated plain R values.
Preparation checks the DTA values against that reference before saving Arrow.

Every available reader/library/thread combination runs once in a separate
qualification process before timing. For synthetic value fixtures, qualification first compares the complete
consumption result against the independent reference. It then compares every
column name and value to the plain RDS reference after removing container
metadata and numeric integer/double differences, using exact
`identical()` equality; it also checks parser problems for readr/vroom.
This checks cross-package values; CSV and generic Feather do not retain Stata
metadata. Unexpected qualification warnings abort the run. Qualification also
checks dtatools' requested container class and compares complete dtatools signatures across
formats, containers and libraries. Failure aborts the run before timing.

Existing private configurations from `io-optimization/read-screen.py` also
work. Their `reads` entries need only opaque `id`, `dta`, `arrow`, `rows`, and
`columns` fields. Entries without `qualification = "values"` use full
`datasig()` comparisons across dtatools formats, containers, libraries and
threads. With `--modes read` alone, these signature-only fixtures do not run the
separate R full-consumption traversal during qualification. Their records say
`consumption = "omitted_read_only"` with a null `consumption_sha256`; the full
dataset signature is still required. This avoids an additional R traversal of
large controls whose timed workload only reads. Any run containing `consume`
requires complete consumption before computing signatures and compares its
hash across every variant, format, container and thread setting. Value fixtures
always require complete consumption, including with `--modes read` alone.
Missing consumption hashes are never treated as computed results. The chosen
policy appears in both fixture provenance and each qualification record.
Other readers are recorded as unavailable for signature-only fixtures because
historical Stata metadata and encoding behavior can differ across packages.

## Measure

After stopping competing builds, tests, profilers and benchmarks:

```sh
python3 benchmarks/r-file-readers/run.py \
  --baseline /path/to/baseline-library \
  --candidate /path/to/candidate-library \
  --fixtures /private/tmp/reader-inputs/fixtures.json \
  --work /private/tmp/reader-results \
  --build-records /private/path/build-bindings.json \
  --threads 1 0 --pairs 6
```

`--cases`, `--methods`, and `--modes` restrict the matrix. Thread request zero
uses each reader's own default, except qs2 where this runner chooses one
thread explicitly. The runtime inventory records resolved package default
thread settings. Positive requests are passed to parallel readers. Base R
and haven have no thread argument and run only the first requested setting.
Do not interpret zero as equal core allocation across packages.

## Acceptance matrix

Run these three commands sequentially after the machine becomes quiet. The
combined synthetic manifest has `numeric`, `compact`, `mixed`, and `wide`
entries. The control manifest contains the existing private `primary-100mb`,
`primary-1gb`, and `india` entries. Adapt paths to the prepared inputs and
successful build work directories. If comparator packages live in a separate
library, include that directory in `R_LIBS` for every command.

First compare all 14 methods at their default thread settings. Both process
modes run for all four synthetic shapes, using six pairs:

```sh
python3 benchmarks/r-file-readers/run.py \
  --baseline /private/tmp/reader-build-baseline/library \
  --candidate /private/tmp/reader-build-candidate/library \
  --build-records /private/tmp/reader-build-records/build-bindings.json \
  --fixtures /private/tmp/reader-wide-inputs/fixtures.json \
  --work /private/tmp/reader-accept-defaults \
  --threads 0 --modes read consume --pairs 6
```

Then measure explicit one-thread dtatools, fread and Arrow reads. In the
recorded runtime, readr, vroom and fst already default to one thread, and this
runner explicitly gives qs2 one thread at request zero. Check the default
thread inventory and extend this supplement if a package's default changes.
Base R and haven expose no thread control.

```sh
python3 benchmarks/r-file-readers/run.py \
  --baseline /private/tmp/reader-build-baseline/library \
  --candidate /private/tmp/reader-build-candidate/library \
  --build-records /private/tmp/reader-build-records/build-bindings.json \
  --fixtures /private/tmp/reader-wide-inputs/fixtures.json \
  --work /private/tmp/reader-accept-serial \
  --methods dtatools_dta_tibble dtatools_dta_dibble \
    dtatools_arrow_tibble dtatools_arrow_dibble fread arrow \
  --threads 1 --modes read consume --pairs 6
```

Finally check both dtatools formats and containers on the larger private
inputs. These controls measure read-only wall time, core time and peak RSS,
at one thread and automatic threads, using eight pairs:

```sh
python3 benchmarks/r-file-readers/run.py \
  --baseline /private/tmp/reader-build-baseline/library \
  --candidate /private/tmp/reader-build-candidate/library \
  --build-records /private/tmp/reader-build-records/build-bindings.json \
  --fixtures /private/path/private-control-fixtures.json \
  --work /private/tmp/reader-accept-controls \
  --cases primary-100mb primary-1gb india \
  --methods dtatools_dta_tibble dtatools_dta_dibble \
    dtatools_arrow_tibble dtatools_arrow_dibble \
  --threads 1 0 --modes read --pairs 8
```

With every comparator available, these stages produce 864, 480, and 384 timed
observations, plus 72, 40, and 48 qualification processes. Qualification runs
once per reader/library/thread combination and serves both process modes.
`--qualify-only` can check the final libraries while waiting for a quiet
machine, but the measurement command repeats qualification; it has no resume
or skip-qualification mode. Do not treat qualification resource use as a
timing result.

## Measurement boundaries and records

Every observation uses a fresh R process. Package loading, reader setup,
bytecode compilation of the small wrapper, and a full garbage collection
precede the timer. No read warmup occurs in that process. Input hashing and
qualification warm the filesystem cache; this does not measure cold storage.

Two process modes keep memory measurements separate:

- `read` times one public call, keeps the result live, checks its shape, and
  exits without scanning its values. Its peak RSS measures startup and read.
- `consume` times the same read, then separately traverses every numeric value as an ordinary double
  and string byte length. It reports read, consumption and combined intervals.
  Its peak RSS includes full consumption. This is a complete traversal rather than
  a promise that every ALTREP backend creates an ordinary R-vector copy.
  The numeric cast can allocate a double column from compact storage, so this
  RSS describes the selected traversal workflow; compact-aware aggregates can
  have different memory use.

Each interval records `proc.time()` elapsed, user and system time around the
same operations. CPU time is user plus system across threads, so lower wall
time can be weighed against additional core time. `wait4()` records total
process CPU time and peak resident memory, normalized to bytes on macOS and
Linux. Worker startup and packages are included in process metrics. The
read-only and consumption measurements come from different children; their
RSS values must not be subtracted to estimate an allocation size.

Baseline/candidate order alternates for every pair. Cases rotate and reverse
between pairs. External readers run once per pair with baseline-library
dependencies. The pair count must be positive and even. `raw.jsonl` retains
every observation without outlier removal. `summary.csv` reports per-reader
medians. `paired-summary.csv` reports dtatools median candidate/baseline
ratios and 95% paired bootstrap intervals using 10,000 resamples and a fixed
seed. Any unresolved clock pair suppresses that metric's ratio and interval
while preserving raw values and medians.

Before/after records bind all input bytes, installed dtatools package files,
R/Rscript executable hashes, R/package versions, package DESCRIPTION hashes, resolved vroom ALTREP flags,
thread settings, and measurement source hashes. Source revisions, patches,
compiler/toolchain and build logs come from the snapshot/receipt workflow
above. Published acceptance runs must pass
`--build-records /private/path/build-bindings.json`. The runner checks its
`libraries.baseline` and `libraries.candidate` inventories against the supplied
installed packages and binds the full record hash before and after execution.
Each inventory maps installed dtatools relative file names to SHA-256 hashes.
Omit the option only for an exploratory or smoke run. Fixture IDs, dimensions and hashes appear
in publishable records; file and library paths stay out of them. Logs and
configuration files remain private. Review every artifact for sensitive
paths or values before publishing it.

Comparator package versions and DESCRIPTION files are recorded, but their
complete native libraries and transitive dependencies are not fingerprinted.
Preserve the dependency libraries during a run. Report input sizes alongside
cross-format results: these deterministic numeric fixtures compress well,
and compressed-reader rankings do not predict arbitrary datasets.

Run the lightweight measurement-parser, qualification-policy and build-record checks with:

```sh
python3 benchmarks/r-file-readers/test-run.py -v
python3 benchmarks/r-file-readers/test-builds.py -v
```

Exercise the qualification policies with real readers using two existing
independent installations and a new private work directory:

```sh
python3 benchmarks/r-file-readers/smoke-qualification.py \
  --baseline /path/to/baseline-library \
  --candidate /path/to/candidate-library \
  --work /private/tmp/reader-qualification-smoke
```

This smoke creates a four-row fixture and runs all four dtatools methods with
both libraries and thread settings 1/0. It checks signature-only read
qualification, signature qualification with consumption, and value
qualification in read-only mode. Complete signatures must match across all
48 fresh processes; consumption hashes must match wherever required and be
absent only for signature-only read qualification. It collects no timings.
