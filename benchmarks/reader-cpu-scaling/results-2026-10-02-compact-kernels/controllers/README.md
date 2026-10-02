# Reproducing the compact-kernel comparison

The published worker and controller preserve the measured logic. Private absolute paths are replaced with placeholders, with original and published hashes in `../publication-source-map.json`. The transformed copies were not rerun as a clean-machine experiment.

Use `benchmarks/r-file-readers/build-snapshot.py` to build a source-bound candidate from base commit `93cc80890032da4c6ef93e8beb4f5b6eb0175a29` and the accepted package source. Every build directory must include its frozen `source/`, installed `library/`, `build-receipt.json`, `input-record.json` and `source.patch`. The controller verifies the actual candidate receipt; role names do not change the receipt's variant.

Generate the million-row compact fixture with `benchmarks/r-file-readers/prepare.R` as described in that harness's README. The required files are `compact.dta`, `compact.arrow` and `compact.rds`. The reference holds ordinary doubles. The worker selects columns 1, 9, 17 and 25, corresponding to byte, int, long and float. The input hashes and runtime versions used here are retained in each stage's provenance.

Use the scalar probe source and preparation instructions from `results-2026-10-02-scalar/controllers/`. Build `scalar_access_probe.so` and regenerate `scalar-probe-build.json` and `scalar-probe-check.json` with your local paths and hashes. The probe verifies full same-order checksums/missing counts plus selected exact values, outside the operation timer. Historical probe receipts cannot simply be copied to a different build.

Copy `throughput.py` and `throughput-worker.R` into a private working directory. Set these environment variables to actual paths:

- `DTATOOLS_BENCH_REPO`: this repository, containing the recorded reader helper, recorder and runtime files.
- `DTATOOLS_KERNEL_BUILD`: the accepted source-bound build directory, not its library child.
- `DTATOOLS_PROBE_DIR`: the scalar probe directory with source, compiled library and regenerated receipts.
- `DTATOOLS_CURRENT_BUILD`: the earlier combined scalar build, required only when running a comparison with `--variants current,kernel`.

After stopping builds, tests, profiling and competing benchmarks, run from that private working directory:

```sh
python3 throughput.py --variants kernel --cases all \
  --rounds 6 --reps 256 --mode confirmation --parity-gate 1.25 \
  --fixtures "$COMPACT_FIXTURES" --work "$COMPACT_RESULTS"
```

The output directory must be new. This runs 252 fresh processes and writes 504 operation observations. Each process compares compact and ordinary doubles for one operation, source format and storage type. Explicit GC, loading and qualification are outside timing; automatic GC, dispatch, allocations and public result construction are inside. Every reduction uses `na.rm = TRUE`. The worker checks the native reduction against ordinary doubles before separately checking public Stata result-storage behavior, including existing float-result rounding.

The initial `screen/` uses its separately preserved worker/controller: two bundled diagnostic rounds, 32 repetitions, current and first-mask builds. Its reductions use stripped native views. It is not a public-reduction before/after comparison with acceptance. `sum-gate/` retains the intermediate sum candidate that missed float parity; `float-gate/` retains the successful preliminary gate. All use the same generated inputs but retain their own protocols and source bindings.

The focused regression scripts and final full-suite runner are under `validation/`. Compiler inspection used the accepted build's original flags plus diagnostic/output-only flags; see `compiler/receipt.json`. No benchmark used the diagnostic compiler output. Installed binaries and input binaries are intentionally excluded from this publication.
