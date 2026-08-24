# R corpus performance benchmark

This local, report-only suite compares `dtaparser::read_dta()`,
`haven::read_dta()`, and Stata's `use` across every regular `.dta` file beneath
the DHS, MICS, and NSFG directories in `/opt/aww_cache`. It does not follow
symlinks and refuses to run in CI. Each reader loads each file in a fresh
process; successful R data frames remain live until exit. The runner records
the reader operation's elapsed time and the process's peak RSS, rotating reader
order between files. Stata elapsed time is measured around `use` inside Stata,
so its application startup is excluded from timing but included in peak RSS.

The published aggregate uses only files that all three readers load with identical
dimensions. Empty, corrupt, unsupported, and one-reader-only inputs remain in
the private raw results but are excluded symmetrically. The summary reports the
common-readable file count and exclusion count for each corpus, total elapsed
time over that common file set, dta-parser's speedup against each comparator,
and the maximum per-file peak RSS observed for each reader. It never publishes
private paths or data values.

See the [2026-08-24 aggregate report](results-2026-08-24.md) for the complete
1,823-file run used in the R package README.

On macOS, run the complete suite from the checkout root:

```sh
benchmarks/r-corpus-performance/benchmark.sh
```

`AWW_CACHE_ROOT` may name another absolute cache root with `DHS`, `MICS`, and
`NSFG` children; `STATA_BIN` may name the Stata executable. The Stata worker
sets `maxvar` to 32,767 so wide but valid survey files are not rejected by the
default 5,000-variable limit. For a bounded
harness check, pass a maximum file count per corpus; the default has no limit:

```sh
benchmarks/r-corpus-performance/benchmark.sh 2
```

Results are private and ignored beneath `target/r-corpus-performance/`. Each
run retains its exact inventory, per-reader raw measurements, summary, built
source package, and installed package library. The macOS runner relies on
`/usr/bin/time -l`; Linux uses GNU `time -v`.
