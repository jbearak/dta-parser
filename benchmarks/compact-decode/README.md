# Compact decode experiment

This screen isolates the cost of decoding compact bytes into ordinary doubles.
It uses the unchanged external `DATAPTR_RO` probe from
[`compact-materialization`](../compact-materialization/). Compile that probe
once and pass the same binary to both builds.

Each input has one million rows. The 24 cases cover byte, int, long, and float
storage; constructed or immutable retained backing with 8,191-row chunks; and
zero, 62 scattered, or 843,750 dense missing values. Sparse and dense cases use
all 27 Stata missing ranks. Ordinary numeric values are the only temporal mode
in this screen. Separate correctness tests cover dates and datetimes.

Every timed request gets a fresh metadata handle sharing one rooted compact
source. Materializing a handle allocates and fills its own double result. A
batch contains 32 such handles, for 256 MB of output and at most 4 MB of shared
input. This keeps source construction outside timing without repeatedly
encoding a million rows. The source remains compact and bitwise unchanged.
The ordinary expected-value vector contributes another 8 MB; these payload
counts exclude descriptor/list overhead and other process memory.
This is an aliased-input experiment; it does not measure private inputs or
compare materialization with an ordinary-double no-op.

`worker.R` checks the entire source before each batch, each target's initial
state, and every result afterward. Warm-up mutation verifies alias independence.
Exact compact-copy and compatibility-copy counters must remain zero in both
builds. Separate untimed observations record R allocation bytes and vector-heap
high-water/live deltas. Those memory measures overlap and are not process RSS.

Run `run.py --baseline BASELINE_BUILD --candidate CANDIDATE_BUILD --probe
SHARED_PROBE --output NEW_DIRECTORY --qualify-only` for complete no-clock
qualification. Omit `--qualify-only` for the six-round paired screen. Both build
directories must have clean source-bound receipts. The controller uses and
hashes the same absolute Rscript launcher, verifies its runtime against both
builds and the shared probe, and rechecks all source/library/controller bindings
afterward. It records the package source delta.

Each build/round gets a fresh process. Build and backing order alternate; six
rounds cover all six missing-density permutations. Every batch contains new
unmaterialized targets. CPU and elapsed intervals accumulate to at least
150 ms per case, including automatic GC. Input/handle setup, checks, explicit
GC, memory profiling, and destruction are outside timing. All individual
intervals, including zeros, remain in the evidence, because the aggregate
threshold does not improve timer resolution.
Summaries include ratios of medians and median/minimum/maximum paired-round
ratios. These are descriptive observations from one host, not uncertainty intervals.

Run `python3 benchmarks/compact-decode/test-run.py` and the same command with
`python3 -O` before qualification. The controller rejects incomplete matrices,
wrong missing densities, pre-materialized targets, input copies, changed values,
nonfinite times, inconsistent interval sums, and unbalanced ordering.

The [October 3 paired result](results-2026-10-03.md) records the completed
288-observation screen and its independent audit.
