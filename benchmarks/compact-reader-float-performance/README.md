# Compact reader FLOAT performance

The final reader implementation keeps allocation facts only for complete, strict, modern non-temporal Arrow FLOAT columns. The existing missing-count scan also computes FLOAT bounds and observed-zero counts. DTA and integer columns remain unknown. DTA bulk FLOAT uses an exact Boolean missing-count kernel, with the format-version gate outside the row loop.

The table gives medians of six alternating baseline/candidate process pairs. Reader cost is candidate/baseline, where smaller is faster. Workflow speedup is baseline/candidate, where larger is faster. Each workflow includes the read and zero, one or five independent `1.01 / source` operations.

| Fixture and format | Reader CPU cost | CPU delta, ms | One-operation speedup | Five-operation speedup |
| --- | ---: | ---: | ---: | ---: |
| dense_float/dta | 0.941 | -0.078 | 1.073 | 1.058 |
| dense_float/arrow | 0.528 | -2.916 | 1.883 | 2.056 |
| sparse_int/dta | 0.974 | -0.017 | 0.968 | 0.973 |
| sparse_int/arrow | 1.008 | +0.009 | 1.002 | 1.006 |

Arrow FLOAT reader CPU cost ranged from 0.505 to 0.547 across the six pairs. DTA FLOAT was noisier, ranging from 0.743 to 1.396; its roughly 6% median reader gain was not consistent across pairs.

Integer readers are controls: their reductions are unchanged. The DTA integer workflows measured about 3% slower; Arrow integer workflows were near neutral. These results do not establish an integer-reader optimization.

The raw observations and evidence include CPU and wall clocks, calibration repetitions, all twelve workflow coordinates, and source/installed-package/fixture bindings. The 24 untimed qualification controls are separate. Warm OS file cache, one reader thread and these two million-row fixtures limit the performance claim. Allocation and automatic GC are timed; allocation volume is not measured.

The rejected broad-facts experiment is preserved in `rejected-all-facts/`. Its 144 observations bind a different source and DLL. It raised DTA reader CPU cost by 64% for dense FLOAT and 45% for sparse INT, and slowed both one-operation DTA workflows. Those results motivated the smaller final implementation. Its gains are historical, not final measurements.

One fresh R qualification passed 139 blocks and 70,260 assertions with no failure, error, warning or skip. The exact native test manifest is included. Four release Rust filters passed 23 test executions; the filters overlap, so this is not a count of distinct tests.

The exact Python controllers used for that qualification are retained in `recorded-qualification-scripts/`, bound to their original private receipt script digests. The root `focused-test-run.py` and `reader-rust-tests.py` are maintained helpers hardened after qualification. They were not used to produce the recorded R or Cargo runs. The focused helper now requires zero observed and zero allowed warnings; the Rust helper handles CRLF, timing suffixes and should-panic labels, and checks parsed status counts against the Cargo summary. Six fake-row/log tests pass with normal Python and `-O`. Untimed replay of the four included original Cargo logs preserves the same 23 executions. No R, Cargo, build or timing was rerun.

The final local build took 23.57 seconds: zero C compilations, 62 Rust compilations and one dtatools installation. It installed no R dependencies. Existing C objects were reused; external Rust dependency cache hits are not claimed.

The final source/DLL-bound assembly witness is in `assembly/`. Its active FLOAT loops remain scalar. Arrow removes the per-element generic tag-classifier call; DTA moves the version gate outside the loop. The exact canonical tag predicate preserves all 27 positive tags and both-sign IEEE NaNs without treating infinities or noncanonical high finite words as missing.

Before clocks, oracles check source facts, values, metadata and compact state. After clocks, alias mutation checks verify missing-cache invalidation. The reader-only Arrow alias follows its existing retained-to-raw detachment and clears facts. Operation workflows preserve the immutable source. These ownership transitions are explicit in every recorded control.

Validate the published records without running R, Cargo or timing:

```sh
python3 publish-reader-evidence.py --check .
python3 -O publish-reader-evidence.py --check .
```

The final `reader-run.py`, `reader-worker.R` and `reader-fixtures.R` are the exact executed sources. The Python controller's CLI help lists its inputs. New timings require independently installed baseline/candidate libraries, their full matching local build receipts, and the matching build-source copies. The published build summaries deliberately omit full target/vendor inventories. The standalone `--check` commands above replay recorded evidence without those installations, local build receipts or generated fixture files.

From this directory, generate fixtures outside all clocks:

```sh
Rscript --vanilla reader-fixtures.R BASELINE_LIBRARY FRESH_FIXTURES
```

Run the controller first with `--qualify-only` and a separate fresh output directory. Then run the six-pair timed panel with the following argument outline:

```sh
python3 reader-run.py \
  --baseline-library BASELINE_LIBRARY \
  --candidate-library CANDIDATE_LIBRARY \
  --baseline-receipt BASELINE_FULL_BUILD_RECEIPT.json \
  --candidate-receipt CANDIDATE_FULL_BUILD_RECEIPT.json \
  --fixtures FRESH_FIXTURES \
  --public-workers-root REPO/benchmarks/remaining-compact-kernels \
  --target-cpu 0.3 --output FRESH_TIMED_PANEL
```

Failed private diagnostics are excluded from passing evidence.
