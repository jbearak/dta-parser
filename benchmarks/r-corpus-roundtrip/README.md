# R corpus write qualification and benchmark

This manual workflow qualifies `dtaparser::write_dta()` against every DTA file
in the DHS, MICS, and NSFG directories beneath `/opt/aww_cache`, then compares
its write performance with Stata. It refuses CI and requires Stata/MP 18 or
later, haven, and processx. The complete workflow requires Stata/MP because its
32,768-variable release-119 case exceeds Stata/SE's 32,767-variable limit; an
early capability probe fails before corpus work when `maxvar 120000` is not
available.

Qualification uses a fresh R process for each input. It reads with dtaparser,
writes a Stata 18/19 standalone file, reads that output again, and checks the
values, storage declarations, tagged missing codes, formats, labels, and notes.
Haven must report the same dimensions, and Stata 18 must open each output with
the same dimensions. The two known unreadable source files are exclusions only
when their stable corpus identity, byte length, and SHA-256 digest all match the
recorded facts.
The complete gate is exactly 1,821 passes and two exclusions.

Only after that gate succeeds does the same package build write all 1,821
datasets again in fresh processes alongside Stata. Writer order rotates by
input. The report aggregates operation time, maximum per-file peak RSS, and
output bytes by corpus and source release. A generated 32,768-variable dataset
is qualified and benchmarked separately to exercise release 119.

Run the public, corpus-free harness test with:

```sh
Rscript --vanilla benchmarks/r-corpus-roundtrip/test-framework.R
```

Run the complete qualification and benchmark from the checkout root:

```sh
benchmarks/r-corpus-roundtrip/benchmark.sh
```

`AWW_CACHE_ROOT` may name another root containing `DHS`, `MICS`, and `NSFG`.
`STATA_BIN` may name the Stata executable. For a quick smoke test, pass the
maximum number of files per corpus; each corpus selects its largest inputs:

```sh
benchmarks/r-corpus-roundtrip/benchmark.sh 2
```

Results remain private beneath `target/r-corpus-roundtrip/`. Set
`DTAPARSER_ROUNDTRIP_RUN_DIR` to an existing run directory to resume its exact
installed package, source tarball, and hash-bound inventory. The retained
public-style reports contain no input paths, labels, or values.

The aggregate-only [2026-08-28 report](results-2026-08-28.md) records the
latest complete qualification against dtaparser 0.6.0. The
[2026-08-27 report](results-2026-08-27.md) remains the historical first
complete qualification and write comparison.
