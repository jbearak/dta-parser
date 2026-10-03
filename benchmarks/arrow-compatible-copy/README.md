# Compatible Arrow numeric transfer

This screen compares public Arrow reads before and after replacing no-null
Float64-to-double and Int32-to-integer scalar transfers with chunk copies.
Destination R vectors still own independent allocations. Nullable inputs,
Float32 widening and retained compact Int16 are unchanged controls.

`prepare.R` creates seven fixed route cases with two million rows and eight
columns. It inspects the actual Arrow schema and every record batch, verifies
null presence in each nullable-control batch, and writes complete source
oracles. Fixture generation is outside timing. The profiled and generic
Float64 cases share a physical file but use different profile settings, so
compare builds within a route rather than treating their difference as an
isolated checksum or classifier measurement.

Use clean source-bound builds from `../r-file-readers/build-snapshot.py` for
the commits pinned in `run.py`. For example:

```sh
Rscript --vanilla benchmarks/arrow-compatible-copy/prepare.R BASELINE_LIBRARY NEW_FIXTURES
python3 benchmarks/arrow-compatible-copy/test-run.py
python3 -O benchmarks/arrow-compatible-copy/test-run.py
python3 benchmarks/arrow-compatible-copy/run.py \
  --repository REPOSITORY --baseline BASELINE_BUILD --candidate CANDIDATE_BUILD \
  --fixtures NEW_FIXTURES --output NEW_QUALIFICATION --qualify-only
python3 benchmarks/arrow-compatible-copy/run.py \
  --repository REPOSITORY --baseline BASELINE_BUILD --candidate CANDIDATE_BUILD \
  --fixtures NEW_FIXTURES --qualification NEW_QUALIFICATION --output NEW_RESULTS
```

Qualification executes all 56 build/case combinations without reading clocks.
Measurement requires that completed qualification with identical build,
fixture, runtime and controller bindings. Six rounds use every target-route
permutation and alternate build, thread, workflow and control order. The 336
workers are separate R processes. Each measures one read-return or one read
followed by full consumption, at one or 16 requested threads.

The full consumer calculates a sum and a complete missing mask for every
column. Values, all missing positions, types, metadata, consumption and native
retained ownership are checked outside timing. Construction, package loading,
explicit preceding GC and final validation are excluded; automatic GC is
included. Every CPU, elapsed and GC interval remains in the evidence.

The controller records actual schema and batch facts, exact source/library
receipts, the absolute Rscript launcher and its R runtime, fixture hashes and
all worker CSVs. It rejects changed values or state, incomplete or unbalanced
matrices, inconsistent totals, nonfinite timings and changed dependencies.
Route eligibility comes from source dispatch and recorded physical inputs,
supported by direct Rust branch tests. Neither measured build has new phase
timers or counters.

The [October 3 result](results-2026-10-03.md) reports the completed screen,
including unchanged controls, paired ratios and short-interval limits.
