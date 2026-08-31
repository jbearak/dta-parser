# R corpus write qualification and benchmark

This manual workflow qualifies `dtatools::save_dta()` against every DTA file
in the DHS, MICS, and NSFG directories beneath `/opt/aww_cache`, then compares
its write performance with Stata. It refuses CI and requires Stata/MP 18 or
later, haven, and processx. The complete workflow requires Stata/MP because its
32,768-variable release-119 case exceeds Stata/SE's 32,767-variable limit; an
early capability probe fails before corpus work when `maxvar 120000` is not
available.

Qualification uses a fresh R process for each input. It reads with dtatools,
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

After installing the checkout-local R package, run the public Stata comparator
tests with:

```sh
Rscript --vanilla benchmarks/r-corpus-roundtrip/test-stata-comparator.R
```

This checks releases 115, 117, and 118, deliberate one-property mismatches,
and a 20 MB, 1,000-variable performance fixture. The default performance limit
is 2.5 seconds; `DTATOOLS_COMPARATOR_MAX_SECONDS` may set a host-specific limit.

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
`DTATOOLS_ROUNDTRIP_RUN_DIR` to an existing run directory to resume its exact
installed package, source tarball, and hash-bound inventory. The retained
public-style reports contain no input paths, labels, or values.

The aggregate-only [2026-08-28 report](results-2026-08-28.md) records the
latest complete qualification against dtatools 0.6.0 under the documented
Stata/MP 18 executable scope. The [2026-08-27 report](results-2026-08-27.md)
remains the historical first complete qualification and write comparison.

## Exact Stata verification

`verify.sh` runs the stricter correctness loop. For each source it
writes a direct DTA copy, an Arrow copy, and a DTA copy read back from Arrow.
Stata compares the original with both DTA outputs. The comparison covers
dimensions, variable order and names, storage types, display formats, dataset
and variable labels, value-label assignments and definitions, notes, and every
stored value. Notes means the dataset notes represented by the package; Stata
variable notes are arbitrary variable characteristics and are outside the
package's documented read model.

Start with the smallest files:

```sh
benchmarks/r-corpus-roundtrip/verify.sh smallest 10
```

Run one previously failing file until it passes completely:

```sh
benchmarks/r-corpus-roundtrip/verify.sh id DHS-0123456789abcdef01234567
```

Only then restart the full size-ordered loop:

```sh
benchmarks/r-corpus-roundtrip/verify.sh full
```

Full verification uses up to 16 independent dataset processes and completes
every selected dataset before reporting failures. Work is admitted in
smallest-first, size-aware waves: the default estimated-memory ceiling is 96
GiB, and each dataset reserves the larger of 512 MiB or 16 times its source
size. This leaves headroom on a 128 GiB host and narrows concurrency for the
largest inputs. Override the limits with `DTATOOLS_VERIFY_JOBS` and
`DTATOOLS_VERIFY_MEMORY_GIB`. Each Stata comparison uses one processor.

After every wave, the runner atomically writes `verification.partial.tsv` so
an interrupted run has a durable ordered checkpoint. To investigate the
unverified tail after an interruption, restart at its one-based ordered corpus
position:

```sh
benchmarks/r-corpus-roundtrip/verify.sh from \
  target/r-corpus-roundtrip-verification/PREVIOUS_RUN 1617
```

This recovery mode does not replace the final uninterrupted full-run gate.

Passing work directories are deleted. Every failure is retained beneath
`target/r-corpus-roundtrip-verification/`, and the ordered `verification.tsv`
contains only corpus IDs and compact comparison locations, never source paths,
labels, or values. Single-ID and smallest-file runs remain serial. Each
invocation builds and installs the current checkout afresh, so a single-ID
recheck cannot accidentally use the package that produced the prior failure.
