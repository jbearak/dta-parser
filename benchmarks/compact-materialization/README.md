# Compact materialization

This benchmark measures the first ordinary `DATAPTR_RO` request on compact
numeric columns. The same separately compiled C probe is loaded with both
package builds, so changes to internal package test helpers cannot change the
measured contract. The probe's source, binary, build command, environment,
toolchain and build log are bound by a receipt and checked again after the run.

The matrix has 32 cases: 4,096 and 1,000,000 rows, byte/int/long/float storage,
constructor and retained chunk backing, and private versus metadata-aliased
handles. Every input contains exact finite values and all 27 Stata missing
ranks, repeating five observed values plus 27 missing ranks. This deliberately
high missing density is stated in the results. Retained columns come from the internal immutable-owner test adapter;
this experiment measures materialization, not Arrow ingestion.

Each timed batch contains fresh independently constructed handles. Construction,
full bitwise source/result checks, explicit collection and batch destruction
happen outside timing. The shared C probe requests each handle once. Batches
contain at most 1,024 handles and approximately 64 MiB of compact-plus-double
payload. Their timed CPU and wall intervals are accumulated until each exceeds
150 ms. Automatic GC and the required output allocation remain inside timing.
The controller alternates builds and balances private/aliased order across at
least six rounds, using a fresh process for each build and round.

Every batch's `proc.time()` CPU and wall interval is saved separately. The
controller recomputes each aggregate and reports interval minima, maxima and
zero-duration counts. The 150 ms aggregate threshold does not establish the
precision of individual short batches; any performance report must include
their observed duration range and address timer granularity.

Checks read every value through the public region API without requesting a
source pointer or creating a metadata alias. This matters for the private
control: an `as.double()` observation can itself change compact sharing.
Every timed target and retained alias must have exactly the expected bits and
state. Separate qualification mutates the decoded target and then materializes
the old alias to prove their independence.

Memory observations are separate, untimed single-call diagnostics:

- Native copy counters report exact copied compact payload bytes and retained
  compatibility-copy bytes.
- `Rprofmem()` reports logged allocation sizes, including allocation overhead.
- `gc()` reports the increase in maximum used Vcells over the pre-call live
  vector heap, plus the post-collection live Vcells change, in bytes.

These observations overlap and must not be added together. They do not include
all external allocator memory and are not process RSS or process-wide peak
memory. The required decoded double payload is reported separately as `8*n`.

Prepare clean baseline and candidate builds with
`benchmarks/r-file-readers/build-snapshot.py`. Both receipts must pass that
recorder's verification. Then run, with private output directories of your
choice:

```sh
python3 benchmarks/compact-materialization/build-probe.py --work /path/to/probe
Rscript --vanilla benchmarks/compact-materialization/worker.R \
  /path/to/candidate/library /path/to/probe 1 /path/to/qualification.csv candidate qualify
python3 benchmarks/compact-materialization/run.py \
  --baseline /path/to/baseline --candidate /path/to/candidate \
  --probe /path/to/probe --output /path/to/results --rounds 6
```

Use an exclusive timing window. The controller creates `completion.json` only
after the full matrix, exact copy expectations, value checks, order balance and
unchanged source/package/probe/controller bindings pass. Individual worker CSVs
without that marker are partial results. One host and deterministic fixtures do
not establish a universal speedup; private compact columns provide a relevant
decode/allocation control, while an already ordinary double would only measure
a no-op pointer request.
