# Reproducible benchmarks

These report-only microbenchmarks use checked fixtures and fixed iteration
counts. They intentionally have no timing assertions. Run correctness gates
before collecting results:

```sh
scripts/conformance.sh
cargo test --workspace --locked
DTA_BENCH_ITERATIONS=100 cargo run --release -p dta-parser --example bench
DTA_BENCH_ITERATIONS=100 bun benchmarks/typescript.ts
Rscript benchmarks/r-benchmark.R 100
```

`DTA_BENCH_ITERATIONS` uses the same grammar in the Rust and TypeScript
benchmarks: `0` or a non-zero ASCII digit followed by ASCII digits. Leading
zeros, signs, whitespace, decimal points, exponents, non-decimal prefixes, and
integers above JavaScript's safe-integer limit are invalid and use the default
of 25; valid values are clamped to 1 through 10,000.

The Rust report separates filesystem I/O, metadata parsing, full slice decode,
projected slice decode, and a projected 1 KiB-bounded file read. It includes
modern all-types, wide, `strL`, and legacy files. The TypeScript report separates
I/O, metadata, buffer decoding, and Node wrapper-backed projection. The R report
captures native allocation/population plus wrapper overhead as one public-call
measurement, and compares the same first-two-column row window with haven when
installed; the C ABI
does not expose stable internal timers, so a finer native R split would require
instrumenting production code and is deliberately not claimed here.

The [`large-scale/`](large-scale/) harness separately compares the public
dta-parser reader, the retained internal Rust-vector collector, and haven on
deterministic 100 MB and 1 GB files. It runs full and projected-eight-column
workloads for 101 iterations by default and writes all generated artifacts below
ignored `target/large-scale/`. See its README for the checkout-local package
library guard, correctness checks, orchestration command, and output matrix.

The manual [`r-corpus-performance/`](r-corpus-performance/) suite loads every
common-readable DHS, MICS, and NSFG DTA file beneath `/opt/aww_cache` through
dta-parser, haven, and Stata in fresh processes. It aggregates elapsed time and
maximum per-file peak RSS by corpus and stored DTA release while keeping paths
and raw results private.
Its [2026-08-24 report](r-corpus-performance/results-2026-08-24.md) records the
aggregate results used in the R package README.

The report-only [`r-helper-performance/`](r-helper-performance/) benchmark
compares label factorization and one-way tabulation with Haven on a generated
compact integer column. It checks result equivalence and reports whether each
workflow materializes the source.

Record the exact command, toolchain, host, fixture sizes, iteration count, and
correctness status in `baseline.md`. Results are evidence for investigation,
not a release gate.

The manual [`fertility-surveys/`](fertility-surveys/) framework separately
checks the private fertility-survey corpus with explicit opt-in and CI refusal
safeguards.

The independent [`aww-cache-differential/`](aww-cache-differential/) workflow
recursively compares every regular DTA file beneath `/opt/aww_cache` through the
public dtaparser and haven readers. It uses bounded resumable tiles and invokes
Stata only to adjudicate actual disagreements:

```sh
benchmarks/aww-cache-differential/benchmark.sh
```
