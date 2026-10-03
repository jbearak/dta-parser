# Reproducible benchmarks

Most microbenchmarks in this directory report timings without asserting them.
They use checked fixtures and fixed iteration counts. Run correctness gates
before collecting results:

```sh
scripts/conformance.sh
cargo test --workspace --locked
DTA_BENCH_ITERATIONS=100 cargo run --release -p dta-tools --example bench
DTA_BENCH_ITERATIONS=100 bun benchmarks/typescript.ts
Rscript benchmarks/r-benchmark.R 100
```

[`r-reference-mutation/`](r-reference-mutation/) is an assertion-based
regression gate for the R package's reference mutation paths. Its exact
allocation, traversal, aliasing, and timing limits fail the run when a compact
path regresses.

The [October 1 correctness-review comparison](r-numeric-performance/review-2026-10-01/README.md)
measures retained generation and mutation optimizations. The separate
[I/O and merge comparison](io-merge-review/results-2026-10-01/README.md)
compares the reviewed build with v0.10.0, including namespace startup and
fresh versus repeated reads. The [reader CPU scaling study](reader-cpu-scaling/results-2026-10-01/README.md)
compares same-interval CPU and wall time across Stata processor settings and
R thread counts. These reports retain raw observations and describe their
different timing boundaries; none imposes a performance gate.

The [R reader comparison](r-file-readers/results-2026-10-01.md) measures
reader construction changes with tibble and dibble outputs, alongside base R
and major package readers. It reports read-call and first-consumption costs,
paired uncertainty intervals, CPU time and peak RSS. The
[reader survey](../docs/research/r-file-reader-performance-2026-10-01.md)
describes the formats and metadata contracts behind those comparisons.

The [October 2 reader follow-up](r-file-readers/results-2026-10-02.md)
compares further dibble construction and retained Arrow scalar-access changes
against release 0.11.0. It includes fresh cross-format measurements, large
controls, and separate native Stata `use` and `save` timings. The
[representation analysis](../docs/research/r-reader-performance-limits.md)
explains which costs come from R's result representation and which can be
removed from the readers.

The [scalar-access follow-up](reader-cpu-scaling/results-2026-10-02-scalar.md)
measures direct native forwarding, repeated wrapper checks, and whole-chunk
caching. It reports incremental scalar and read-plus-consume gains against
the subsequent gather4-v2 candidate, with separate source bindings.

The [compact-kernel follow-up](reader-cpu-scaling/results-2026-10-02-compact-kernels.md)
compares public missing predicates and reductions with ordinary doubles.
Typed compact masks and ordered sums meet the measured parity target across
42 DTA/Arrow cases, while preserving compact storage and existing results.

The [native-operation follow-up](native-operations/results-2026-10-02.md)
compares tagged predicates, cached missing checks, totals, summaries, matching
and arithmetic across four compact widths and both file formats. Six rounds
include ordinary-double controls and separate typed-double arithmetic controls,
with result, storage and source checks. Arithmetic improves substantially but
still trails the double controls.

The [compact arithmetic follow-up](native-operations/results-2026-10-02-arithmetic-parity.md)
removes native allocation and loop overhead left by that change. Six balanced
rounds put the measured multiply, divide and self-add operations at 0.58–1.13×
typed-double CPU, with full result and storage checks. Bare-double ratios and
the remaining float overhead are reported separately.

The [direct float comparison follow-up](float-comparison/results-2026-10-02.md)
compares scalar and pair comparisons across missing layouts and thread settings.
The 432-observation constructed-column matrix reaches double-control throughput
with exact missing-code and scalar-precision semantics. Retained-column
throughput remains a separate question.

The [Arrow collection-pressure follow-up](arrow-memory-pressure/results-2026-10-02.md)
removes repeated full collections caused by unchanged live native buffers.
Eight-row reads with 65 MiB retained improve by 69.2–69.5× CPU; controls below
the pressure threshold remain essentially unchanged. This is a steady-state
small-read result, with the repeated-large-read memory bound checked separately.

The [numeric grouping follow-up](prepared-grouping/results-2026-10-02.md)
prepares numeric order keys once instead of decoding and validating them during
sorting. Across 20 constructed-input cases, compact grouping is 11.94–23.69×
faster and matches typed/ordinary-double throughput within the measured spread.
It reports the additional eight-byte-per-row-per-key cache cost explicitly.

The [full-cache reader rerun](reader-corpus/results-2026-10-01-full-cache/README.md)
reports `read_dta()` for every regular DTA input in the DHS, MICS, NSFG,
ENADID and WFS survey datasets, with both tibble and dibble outputs. Its 3,762
survey attempts include the two known malformed inputs for both containers;
aggregate times cover 1,879 readable files.

The [full-cache Stata oracle](r-corpus-roundtrip/results-2026-10-01.md)
qualifies DTA and Arrow round trips across all 1,879 readable files in the
five survey datasets, with two hash-bound malformed-input exclusions. It reruns
live Stata comparisons without invoking Haven.

The [I/O optimization screens](io-optimization/README.md) compare individual
reader and writer candidates against the reviewed build. They use separate
correctness qualification and fresh-process timing, with wall time, CPU time,
and peak memory recorded together.

`DTA_BENCH_ITERATIONS` uses the same grammar in the Rust and TypeScript
benchmarks: `0` or a non-zero ASCII digit followed by ASCII digits. Leading
zeros, signs, whitespace, decimal points, exponents, non-decimal prefixes, and
integers above JavaScript's safe-integer limit are invalid and use the default
of 25; valid values are clamped to 1 through 10,000.

The Rust report separates filesystem I/O, metadata parsing, full slice decode,
projected slice decode, and a projected 1 KiB-bounded file read. It includes
modern all-types, wide, `strL`, and legacy files. The TypeScript report retains
the corresponding checked-fixture cases and adds product-shaped workloads:

- Sight: a natural 200-row viewport, a 200-row viewport in sorted display order
  whose original source-row indices are sparse, restoring
  three full sort/filter columns, and the first `strL` column touch.
- Table Viewer: a 100-row page across 120 columns, sparse indexed reads of three
  columns, a 128-row-chunked selected-column scan, a large value-label section,
  and first-touch indexing of a large `strL` section.

The product cases generate deterministic valid DTA files in the system temporary
directory before timing begins and remove them when the run ends. They scale the
checked fixtures to 100,000 Sight rows, 1,000 wide Table Viewer rows, 6,144 value
label tables, and 4,096 256-byte `strL` entries. Fixture construction is covered
by correctness tests and is excluded from reported timings. The R report
captures native allocation/population plus wrapper overhead as one public-call
measurement, and compares the same first-two-column row window with haven when
installed; the C ABI
does not expose stable internal timers, so a finer native R split would require
instrumenting production code and is deliberately not claimed here.

The [`large-scale/`](large-scale/) harness separately compares the public
dta-tools reader, the internal Rust-vector collector, and haven on
deterministic 100 MB and 1 GB files. It runs full and projected-eight-column
workloads for 101 iterations by default and writes all generated artifacts below
ignored `target/large-scale/`. See its README for the checkout-local package
library guard, correctness checks, orchestration command, and output matrix.

The manual [`r-corpus-performance/`](r-corpus-performance/) suite loads every
common-readable DHS, MICS, and NSFG DTA file beneath `/opt/aww_cache` through
dta-tools, haven, and Stata in fresh processes. It aggregates elapsed time and
maximum per-file peak RSS by corpus and stored DTA release while keeping paths
and raw results private.
Its [2026-08-24 report](r-corpus-performance/results-2026-08-24.md) records the
original comparator results. The [September 12 adaptive-default reader refresh](reader-refresh/results-2026-09-12-defaults/README.md)
updates the dtatools corpus, DTA/Arrow, India, projection and fixture measurements,
including read-call CPU time and fresh-process peak RSS. The subsequent
[September 13 local-reader startup investigation](reader-startup/results-2026-09-13/README.md)
supplies corpus and fresh-process India comparisons for the defaults at that time, plus alternating
old/new dtatools measurements on small files. It removes unnecessary dependency
loading and reports read-call CPU time, whole-process CPU, and peak RSS.
The [September 16 full-corpus run](reader-corpus/results-2026-09-16-base-r/README.md)
updates both `read_dta()` and verified `read_arrow()` with default settings.
Its timed workers use base R for setup and reporting. It qualifies Arrow
copies for all 1,821 readable inputs, attempts all 1,823 original DTA inputs,
and retains the same 1,812-file comparison set. Haven and Stata corpus timings remain from August 24.

The [September 16 India comparison](reader-parity/results-2026-09-16-india/README.md)
compares ten full reads each with dtatools, haven and Stata.
The India report gives read wall time, whole-process CPU and peak RSS for all four
readers. The [reader-parity controller](reader-parity/) also covers
projected reads and downstream operations.

The synthetic [`projection-introspection/`](projection-introspection/) suite
compares a union-safe `any_of()` projection with Stata's full-load-then-keep
workflow and Stata's direct, non-union-safe projected `use`. It varies dataset
width and row count while requiring every method to return the same ten
columns.

The manual [`r-corpus-roundtrip/`](r-corpus-roundtrip/) workflow qualifies the
R writer against the same 1,823-file cache, requires semantic re-read equality
plus Haven and Stata-open checks, and only then benchmarks writes against Stata.
Its [2026-08-27 report](r-corpus-roundtrip/results-2026-08-27.md) records the
complete qualification and aggregate write results. The controlled synthetic
[write report](large-scale/results-2026-08-27.md) adds repeated Haven, Stata,
and dtatools timing and peak-RSS comparisons.

The report-only [`r-cell-assignment/`](r-cell-assignment/) benchmark times one
`repl()` call and one `set_dta_values()` call against one `data.table::set()`
call, whole column, single row, and in a per-row loop. Its
[first 2026-09-19 report](r-cell-assignment/results-2026-09-19.md) is the
evidence behind ADR 0041, and its
[second](r-cell-assignment/results-2026-09-19-set-dta-values.md) measures the
assigner ADR 0043 added.

The report-only [`r-helper-performance/`](r-helper-performance/) benchmark
compares label factorization and one-way tabulation with Haven on a generated
compact integer column. It checks result equivalence and reports whether each
workflow materializes the source.

The report-only [`r-merge-performance/`](r-merge-performance/) benchmark
compares `dta_merge()`, dplyr, base R, and Stata on deterministic wide 1:m and
m:1 merges. It measures both DTA-read Stata classes and ordinary R columns and
reports cumulative R allocation so materialization costs remain visible.

The report-only [`arrow-interchange/`](arrow-interchange/) benchmark compares
`save_arrow()` and `read_arrow()` with the DTA reader/writer, haven, and
Stata medians on the deterministic 100 MB and 1 GB fixtures and the
India 2021 DHS women's file, including the additive impact of each write
optimization and the checksums flag. Its
[2026-08-29 report](arrow-interchange/results-2026-08-29.md) records the
original read and conversion results. For the newer India measurements, see
the [September 16 four-reader comparison](reader-parity/results-2026-09-16-india/README.md).
The [September 12 balanced warm report](reader-refresh/results-2026-09-12-balanced/README.md)
retains synthetic reader measurements from before the latest optimizations.

The report-only [`dta-merge/`](dta-merge/) benchmark times one `dta_merge()`
across every x/y input-source combination — preloaded frames and `.dta` and
`.arrow` file paths — so from-file merge cost can be attributed to the file
read plus the merge itself. Its
[2026-08-29 report](dta-merge/results-2026-08-29.md) includes preloaded
base R and dplyr context rows.

Record the exact command, toolchain, host, fixture sizes, iteration count, and
correctness status in `baseline.md`. Results are evidence for investigation,
not a release gate.

The manual [`fertility-surveys/`](fertility-surveys/) framework separately
checks the private fertility-survey corpus with explicit opt-in and CI refusal
safeguards.

The independent [`aww-cache-differential/`](aww-cache-differential/) workflow
recursively compares every regular DTA file beneath `/opt/aww_cache` through the
public dtatools and haven readers. It uses bounded resumable tiles and invokes
Stata only to adjudicate actual disagreements:

```sh
benchmarks/aww-cache-differential/benchmark.sh
```
