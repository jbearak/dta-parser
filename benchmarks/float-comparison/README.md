# Float comparison kernels

This benchmark compares public float `<` and `==` operations with matching
typed-double and bare-double inputs. It includes scalar `< 1.01`, automatic
and single-thread scheduling, and inputs with no missing values or sparse
instances of all 27 Stata missing codes. Each input has one million rows.

The timed interval includes public dispatch, logical result allocation and
automatic garbage collection. Input construction, explicit collection,
calibration, separate native entry qualification, complete value hashing and
metadata/state checks are outside the interval. Each interval targets 300 ms
of CPU after at least 50 ms calibration; reports must include the actual range.

Six fresh-process rounds alternate build order and rotate/reverse the three
representations. Full logical results must match across builds, and between
representations with the same contract. Bare R propagates missing values, so
its missing-bearing comparisons are context controls with a different
contract. Compact sources must remain unmaterialized and preserve all input
bytes and metadata.

Prepare two clean builds with `benchmarks/r-file-readers/build-snapshot.py`,
then qualify and measure with private output directories:

```sh
Rscript --vanilla benchmarks/float-comparison/worker.R \
  /path/to/candidate/library 1 /path/to/qualification.csv qualify
python3 benchmarks/float-comparison/run.py \
  --baseline /path/to/baseline --candidate /path/to/candidate \
  --output /path/to/results --rounds 6
```

Keep other local tests, builds and timings stopped during measurement. The
controller verifies the package build receipts, records the source delta and
checks source, library and controller hashes again at the end. It rejects
incomplete matrices, changed results, missing native qualification and
unbalanced representation positions. `completion.json` identifies a complete
432-observation run. Timing ratios are report-only and are not CI thresholds.

This matrix covers warm operations on constructed columns on one host. Public
regression tests separately cover retained chunks, legacy encoding, temporal
rounding, noncanonical imports, IEEE values and scalar precision boundaries;
the timings do not establish their throughput.
