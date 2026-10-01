# R I/O and merge release comparison

This harness compares the five public operations represented in the R package
README: `read_dta()`, `save_dta()`, `read_arrow()`, `save_arrow()`, and
`dta_merge()`. The exported write functions are named `save_*`, not `write_*`.

The [2026-10-01 report](results-2026-10-01/README.md) compares the v0.10.0
release with a later candidate on fixed, fingerprinted inputs. It does not
refresh the README's historical Stata/Haven comparisons or full-corpus totals.

## Reproduction

Use two independently installed package libraries with the same R and
dependencies. Record each source revision, production-file hashes, installed
file hashes, DLL hash and installation log. A package version string alone
cannot distinguish these builds because both report version 0.10.0.

Copy the harness into a private run directory and provide `configuration.json`
with the fields shown in `configuration.example.json`. Keep local survey paths
and the populated configuration out of published reports. Both `R_LIBS` and
`DTATOOLS_BENCH_LIB` are set for every R child; the child verifies the loaded
package path.

Generate the primary 100 MB and 1 GB fixtures with
`benchmarks/large-scale/generate-stata-fixtures.R`, using its canonical absolute
size-file and manifest paths. This requires Stata. The fixed row counts and
schema come from `stata-write-sizes.tsv` and `stata-generate-fixture.do`.
Enter the resulting immutable generation paths in the configuration. Supply
the separately licensed India 2021 input locally. Then run, in order:

```sh
python3 prepare.py
python3 qualify.py configuration.json inputs
python3 run.py configuration.json reads
python3 run.py configuration.json writes
python3 run.py configuration.json merges
python3 run.py configuration.json loads
python3 qualify.py configuration.json outputs
```

`prepare.py` creates current-profile Arrow files through the baseline package
and the exact seed-7 README merge fixture. Create `merge_directory` first.
Fresh output directories are required; the driver refuses to append another
timing run to existing phase logs. Capture provenance before and after the
measurement window with `provenance.py`. Its additional configuration fields
name the archived baseline source and both installation logs.

Run workers sequentially while builds and other benchmarks are stopped. The
driver alternates baseline-first and candidate-first order by pair, rotates
case order, and checks each case's order balance. Reads and merges use ten
pairs; writes use eight. Each worker performs one measured call. Merge inputs
are loaded before timing, followed by one untimed merge and full GC. Writers
prepare input before timing and run full GC. Fresh reads have neither an
in-process warmup nor pre-read GC. Namespace loading has its own timer.

The separate `warm/` driver takes an India-only configuration and measures one
read after an untimed read, removal of that result, and full GC. Keep its
output directory separate. It is a different protocol, not an additional
sample of the fresh-read comparison.

## Measurements and checks

Call wall time and call CPU use the same `proc.time()` interval. The parent
records whole-process wall time, CPU and peak RSS with `wait4`; on the measured
macOS host RSS is in bytes. Process costs include startup and untimed setup,
and merge process costs also include the warmup. They are not substitutes for
call timing. Filesystem cache is warm. Default threading, Arrow verification
and Arrow checksums remain enabled.

Full `datasig()` comparisons cover values, order and the package's canonical
metadata model. Merge qualification also checks shape, key multiplicities,
match counts, representative coalesced values and unchanged input signatures.
Writer samples record dimensions, file sizes and warning sequences. The first
and final output per case/build are read back through the baseline reader;
intermediate private output files are removed after recording their sizes.
Separate qualification calls check that writes leave input signatures intact.
The expected Arrow timezone-attribute warnings must agree between builds.

Summaries retain both medians and the median paired candidate/baseline ratio.
The 95% intervals use 10,000 paired bootstrap resamples with fixed seed
20261001. These describe this run's sampling uncertainty; they do not cover
other hardware, cold caches, other surveys or future runtime versions.
