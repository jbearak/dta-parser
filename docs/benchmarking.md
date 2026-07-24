# Benchmarking against haven

The repository includes an opt-in, reproducible comparison with
[`haven::read_dta()`](https://haven.tidyverse.org/reference/read_dta.html).
It has two deliberately separate parts:

1. a correctness suite over every checked-in Stata fixture; and
2. a performance benchmark over deterministic, generated datasets, including
   stage-level attribution.

The suite is opt-in because the regular TypeScript tests should not require an
R installation. It does not download data or packages and does not retain the
generated `.dta` files.

## Requirements

- the repository's normal JavaScript dependencies (`npm install`);
- R available as `Rscript`; and
- the R packages `haven` and `jsonlite`.

Install the R dependencies once if needed:

```r
install.packages(c("haven", "jsonlite"))
```

## Correctness suite

Run:

```sh
npm run test:reproducibility
```

The suite asks both readers to decode all checked-in `.dta` files and compares
canonical representations. The corpus currently exercises formats 114, 115,
117, 118, and 119; numeric storage types; fixed and long strings; empty and
wide datasets; dataset and variable labels; display formats; value labels;
and ordinary plus extended missing values (`.`, `.a` through `.z`).

For every file, the comparison includes:

- row and column counts and variable order;
- dataset labels, variable labels, and Stata display formats;
- each variable's value-to-label mapping; and
- every decoded cell, with tagged missing values kept distinct.

Numbers use a relative tolerance of `1e-7` so values stored as Stata `float`
are not rejected due to insignificant language-level formatting differences.
All other values and metadata are exact. Stata storage type names are not part
of the cross-reader assertion because haven exposes the decoded R vector type,
not the original byte/int/long/float distinction. The parser's storage-type
handling remains covered by the TypeScript unit suite.

The command exits nonzero on the first run containing a difference and prints
up to 20 paths to mismatched values. A successful run resembles:

```text
Correctness: PASS — 29 files match haven (tolerance 1e-7).
```

## Performance benchmark

Run the correctness suite and performance benchmark together:

```sh
npm run benchmark
```

Or run only the timings:

```sh
bun run benchmarks/dta-vs-haven/run.ts --benchmark-only
```

The default workload uses 100,000 rows, two untimed warmups, and five measured
iterations. Options make a run easy to scale or repeat:

```sh
bun run benchmarks/dta-vs-haven/run.ts \
  --rows 250000 \
  --warmup 3 \
  --iterations 10 \
  --json benchmark-results/dta-vs-haven.json
```

The JSON artifact contains environment and package versions, file sizes, all
raw timing samples, medians, and relative throughput. `benchmark-results/` is
gitignored so machine-specific measurements are not accidentally presented as
universal package claims.

### Workloads and timing

The generator uses a fixed random seed and haven's Stata 14 writer to create
v118 files in a fresh temporary directory:

| Dataset | Shape | Purpose |
| --- | --- | --- |
| `numeric-v118.dta` | 20 numeric columns | Dense numeric decoding |
| `mixed-v118.dta` | 7 numeric/labelled/string columns | Labels, strings, and tagged missing values |

Each file is measured in two modes: a full read and a three-column projection.
Each sample includes opening the `.dta` file, parsing its metadata, decoding
the requested data, and closing it. R and Bun process startup, fixture
generation, warmups, and result serialization are outside the timed region.
Both readers eagerly materialize the requested data before a sample completes;
the harness only inspects result dimensions, so downstream traversal is not
part of the measurement.

### Stage attribution

After the headline timings, the harness prints an attribution table for each
dataset. These measurements answer a narrower question than the headline:
where does each implementation spend its end-to-end time on a warm file?

For dta-parser, the boundaries are directly exposed by its implementation:

| Stage | Measurement |
| --- | --- |
| Open + metadata + labels | `DtaFile.open()` followed by `close()` |
| Observation read | One positional read of the exact observation byte range into a newly allocated buffer |
| Decode + JS result | `read_rows_from_data_buffer()` over an already loaded observation buffer |
| Composition/noise residual | End-to-end median minus the three independently measured medians above |

The metadata parser and value-label parser are also timed against preloaded
bytes as diagnostics. An empty row-container allocation supplies a lower bound
on JS result allocation; it does not populate cells, so it must not be
subtracted as though it were the complete result-construction cost.
The diagnostic output also normalizes each combined decode/result stage to
nanoseconds per requested cell, making differently shaped datasets easier to
compare.

Haven has a coarser observable boundary. `read_dta()` calls ReadStat's C parser,
and haven's C++ value callback writes each decoded cell into its R vector during
that same native call. Without rebuilding haven with internal timers, binary
decoding and R result population cannot be measured independently. The harness
therefore reports them honestly as a combined stage:

| Stage | Measurement |
| --- | --- |
| Native metadata/setup | Haven's native file entrypoint with `n_max = 0` (internally it may parse one row before returning zero) |
| Native data + decode + R result | Full native-file median minus native metadata/setup |
| R wrapper/datasource residual | `read_dta()` median minus the preconfigured native-file median |

Two further diagnostics constrain the interpretation. A base-R raw file read
shows the warm file-I/O scale, while haven's native parser over a preloaded raw
vector shows whether its file input path explains material time. A synthetic
typed tibble with the correct dimensions and attributes gives a lower bound on
R result allocation, but not the cost of populating cells, allocating actual
strings, or crossing ReadStat's per-value callback.

The percentages are calculated from medians of separate sample sets. They are
useful attribution estimates, not an accounting identity. A negative or large
`composition/noise residual` indicates timer noise, garbage collection, JIT
state, or interactions between stages; increase `--rows`, warmups, and
iterations before drawing conclusions. All raw samples are retained in the
optional JSON result.

Because generated files are written and repeatedly warmed immediately before
measurement, the default suite characterizes warm-cache parsing. It does not
claim to measure cold physical-disk latency. Re-run with larger `--rows` values
to test how allocation and garbage collection change with scale.

The displayed value `dta-parser throughput` is:

```text
haven median elapsed time / dta-parser median elapsed time
```

Thus `2.00x` means dta-parser completed that workload in half haven's median
time; `0.50x` means it took twice as long. Lower millisecond values are always
better. Compare results only on the same machine and workload: filesystem
cache, CPU, R/Bun versions, data shape, and iteration count can materially
change timings.

This harness measures elapsed read performance, not peak memory. It also does
not claim feature parity between the libraries: haven returns a tibble with R
classes, while dta-parser returns JavaScript rows or selected columns and
preserves Stata missing tags as explicit objects.

## Implementation files

- `benchmarks/dta-vs-haven/run.ts` orchestrates comparison, timing, and output.
- `benchmarks/dta-vs-haven/haven.R` provides haven snapshots and timed reads.
- `benchmarks/dta-vs-haven/generate.R` creates deterministic performance data.

## Recorded runs

- [Apple M4 Max, 2026-07-24](benchmark-results/2026-07-24-apple-m4-max.md)
