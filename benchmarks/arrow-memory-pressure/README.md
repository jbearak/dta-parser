# Arrow memory pressure

This benchmark measures an eight-row Arrow read while an unrelated retained
numeric table remains live. Controls retain zero, 63 MiB or 65 MiB of native
backing. Both ordinary double and compact float tiny results contain system
and extended missing values. The input files are uncompressed and checksummed.

The baseline reader requests full R collection whenever charged native memory
exceeds 64 MiB. The candidate additionally requires more than 32 MiB of new
native allocation since the last successful forced collection. This prevents
unchanged live data from repeatedly triggering collection. The pressure test
continues to run before each read, and the package's repeated-large-read memory
bound remains a separate regression test.

Build each package from a committed source revision into a new private directory:

```sh
python3 benchmarks/r-file-readers/build-snapshot.py \
  --variant baseline --base-commit BASELINE_COMMIT --work /private/tmp/pressure-baseline
python3 benchmarks/r-file-readers/build-snapshot.py \
  --variant candidate --base-commit CANDIDATE_COMMIT \
  --source r-package/dtatools --work /private/tmp/pressure-candidate
mkdir /private/tmp/pressure-inputs
Rscript --vanilla benchmarks/arrow-memory-pressure/prepare.R \
  /private/tmp/pressure-baseline/library /private/tmp/pressure-inputs
python3 benchmarks/arrow-memory-pressure/run.py \
  --baseline /private/tmp/pressure-baseline --candidate /private/tmp/pressure-candidate \
  --fixtures /private/tmp/pressure-inputs --output /private/tmp/pressure-results
```

Stop other local builds, tests and benchmarks before timing. Six rounds balance
all condition orders, alternate build order, and alternate tiny storage order.
Every observation starts a fresh R process. Each measured interval contains
2,000 public reads, except the slow baseline 65 MiB condition uses 200. The
runner records same-interval process CPU, elapsed time and GC CPU. Public
dispatch, file I/O, verification, allocation and automatic or forced collection
are inside the interval. Setup, warmup, explicit collection, full value checks
and data signatures are outside it. Median per-call costs compare matching
conditions; inspect interval lengths before interpreting small differences.

The worker verifies every numeric value and the storage of the tiny result,
every retained source value, and complete data signatures. Compact sources
remain retained. The candidate must make zero forced collection attempts in
each timed interval. Live-byte checks distinguish ordinary results from the
bounded additional storage of compact results. Private attempt counters count
admitted requests, including ones that could be interrupted before collection;
these runs do not inject interruptions.

Before and after measurements, the controller verifies clean-build receipts,
the complete package sources, compiler inputs, installed code, native library,
fixtures and benchmark scripts. Its completion check rejects missing or
duplicate cases, mismatched signatures, invalid intervals and candidate forced
collections, including under Python's optimized mode. Run that check's tests
with `python3 benchmarks/arrow-memory-pressure/test-run.py`.

These are warm-cache measurements on one host. They do not establish read
throughput for large files, cold-storage behavior, or memory bounds for every
workload. The benchmark contains no CI timing threshold.
