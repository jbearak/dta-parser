# Reproducible benchmarks

These report-only microbenchmarks use checked fixtures and fixed iteration
counts. They intentionally have no timing assertions. Run correctness gates
before collecting results:

```sh
bun run conformance
cargo test --workspace --locked
DTA_BENCH_ITERATIONS=100 cargo run --release -p dta-parser --example bench
DTA_BENCH_ITERATIONS=100 bun benchmarks/typescript.ts
Rscript benchmarks/r-benchmark.R 100
```

The Rust report separates filesystem I/O, metadata parsing, full slice decode,
projected slice decode, and a projected 1 KiB-bounded file read. It includes
modern all-types, wide, `strL`, and legacy files. The TypeScript report separates
I/O, metadata, buffer decoding, and Node wrapper-backed projection. The R report
captures native allocation/population plus wrapper overhead as one public-call
measurement, and prints a separate haven reference when installed; the C ABI
does not expose stable internal timers, so a finer native R split would require
instrumenting production code and is deliberately not claimed here.

Record the exact command, toolchain, host, fixture sizes, iteration count, and
correctness status in `baseline.md`. Results are evidence for investigation,
not a release gate.
