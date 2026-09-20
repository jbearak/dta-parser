# Shared mutation overhead, 2026-09-20

The direct-call runner measures a single-row `set_dta_values()` assignment at
1.8 µs, down from 14.0 µs on the same host. A whole-column scalar fill falls
from 22.1 to 10.0 µs. The two 1,000-write loop medians are 2.0 and 2.1 ms,
versus 17.0 and 16.7 ms for baseline. These are measurements of the recorded
fixtures, not latency guarantees.

The native patch was already cheap. The improvement comes from bypassing R
setup for eligible scalars and using stack staging in the shared transaction.
`repl()` and `:=` benefit through their own scalar adapters; selected-row
creation also improves. Whole-column generation changes less.

## Source and method

- Baseline: `75771518e1312794ae02b617253fde48028ec16f`, package tree
  `6a5841e97ef7151aed6c9e6504819fb3f3025320`.
- Candidate: `8ef15b826f6bb88eed8c5a401b5ba6601ecb2fbc`, package tree
  `13976093639e2dc3815e4853aadea2a2f076fda8`.
- Full-matrix runner: `d72354a313e3f3db4a13113fe3d53b5b94a5396f`.
- GC-controlled runner: `d06c2d95c9ef4ffc0194c9c5c0759402d5f2a582`.
- R 4.6.1, `aarch64-apple-darwin25.4.0`; Darwin 25.6.0 arm64.
- dtatools 0.10.0; data.table 1.18.6.1; bench 1.1.4.
- Both packages came from the exact-source installer. Each runner verified
  the library's provenance sidecar against the requested revision and installed files.

Each pair was run in baseline, candidate, candidate, baseline order, with
100,000 rows and no other benchmark or reviewer probes running. Tables below
use the mean of the two run medians, not a pooled median. Individual medians,
quartiles, allocation observations and provenance are in
[the raw results](results-2026-09-20-shared-mutation/).

`run.R` uses the original two-column fixture, 200 iterations per direct call
and three per 1,000-write loop, with `bench::mark(filter_gc = FALSE)`.
`expanded.R` uses 50 fresh fixtures per condition, one or 100 columns, and
private or externally shared target backing. It times `eval(call, env)` with
`bench::system_time`; setup and correctness assertions are outside timing.
These matrix times include the extra `eval()` and should be compared with each
other, not subtracted from the direct-call times.

Private targets are prepared with the same native patch on both revisions.
Shared fixtures then retain a separate tibble, so each replacement measures
the first write after sharing. Generation adds one column with spare capacity.
Data.table's retained-column rows do not promise dtatools' result isolation.
Every case checks landed values, storage where applicable, and the retained
result outside timing.

## Original direct-call benchmark

| Operation | Baseline | Candidate | data.table, candidate run | Baseline / candidate | Candidate / data.table |
| --- | ---: | ---: | ---: | ---: | ---: |
| `set_dta_values()`, one row | 14.0 µs | 1.8 µs | 1.8 µs | 7.78× | 1.00× |
| `set_dta_values()`, whole column | 22.1 µs | 10.0 µs | 7.5 µs | 2.21× | 1.33× |
| `set_dta_values()`, 1,000 rows | 16.9 ms | 2.05 ms | 2.0 ms | 8.22× | 1.03× |
| `repl()`, one row | 109.6 µs | 29.0 µs | 1.8 µs | 3.79× | 16.08× |
| `repl()`, whole column | 122.6 µs | 41.2 µs | 7.5 µs | 2.97× | 5.49× |
| `repl()`, 1,000 rows | 116.5 ms | 28.9 ms | 2.0 ms | 4.04× | 14.43× |

Both candidate runs report the same rounded 1.8 µs single-row median and
10.0 µs whole-column median. Data.table also reports 1.8 µs per row in both
runs. This is parity at the report's rounding precision on this fixture,
not a claim of identical costs for other shapes or policies.

## All entry points

The following rows are private one-column fixtures. Names map directly to
[the expressions in the runner](expanded.R). `set_reject` rejects a value that
needs wider storage; `repl_promote` and `bracket_promote` widen byte to int.
`repl_fused` uses the existing comparison-and-patch path. Expression rows use
`x + 2`, except `set_expression`, which evaluates `abs(-3)` outside a data mask.

| Operation | Baseline µs | Candidate µs | Baseline / candidate |
| --- | ---: | ---: | ---: |
| `set_row` | 18.1 | 3.4 | 5.35× |
| `set_whole` | 25.2 | 12.0 | 2.09× |
| `set_expression` | 17.4 | 17.8 | 0.97× |
| `set_create` | 63.2 | 52.7 | 1.20× |
| `set_reject` | 21.4 | 7.4 | 2.89× |
| `repl_row` | 116.5 | 32.7 | 3.56× |
| `repl_whole` | 122.1 | 38.7 | 3.15× |
| `repl_expression` | 2172.3 | 2337.0 | 0.93× |
| `repl_promote` | 8725.8 | 8923.2 | 0.98× |
| `repl_fused` | 600.0 | 584.2 | 1.03× |
| `gen_whole` | 121.8 | 113.7 | 1.07× |
| `gen_row` | 174.0 | 110.6 | 1.57× |
| `gen_expression` | 2513.6 | 2647.7 | 0.95× |
| `bracket_row` | 207.6 | 85.0 | 2.44× |
| `bracket_whole` | 220.4 | 88.4 | 2.49× |
| `bracket_expression` | 2373.4 | 2277.1 | 1.04× |
| `bracket_promote` | 9071.8 | 8788.4 | 1.03× |
| `bracket_create` | 257.2 | 150.5 | 1.71× |
| `bracket_create_expression` | 2747.9 | 2708.6 | 1.01× |
| `append_prebuilt` | 19.4 | 19.0 | 1.03× |
| `data_table_row` | 3.5 | 3.6 | 0.97× |
| `data_table_whole` | 9.1 | 9.1 | 1.00× |

## Width and shared backing

Times are baseline → candidate in µs. The complete 88-condition matrix is in
[summary.csv](results-2026-09-20-shared-mutation/summary.csv).

| Operation | 1 column, private | 1 column, shared | 100 columns, private | 100 columns, shared |
| --- | ---: | ---: | ---: | ---: |
| `set_row` | 18.1 → 3.4 | 41.1 → 26.6 | 54.5 → 24.1 | 71.4 → 43.9 |
| `set_whole` | 25.2 → 12.0 | 27.0 → 12.9 | 56.3 → 30.5 | 58.0 → 30.2 |
| `repl_row` | 116.5 → 32.7 | 139.8 → 56.9 | 212.0 → 84.8 | 249.6 → 96.6 |
| `bracket_row` | 207.6 → 85.0 | 241.5 → 109.9 | 385.3 → 190.8 | 409.1 → 206.0 |
| `gen_whole` | 121.8 → 113.7 | 127.3 → 117.4 | 192.9 → 201.3 | 193.2 → 184.2 |
| `gen_row` | 174.0 → 110.6 | 175.7 → 116.1 | 285.7 → 191.3 | 286.5 → 184.6 |
| `bracket_create` | 257.2 → 150.5 | 257.9 → 143.6 | 433.3 → 250.1 | 422.8 → 245.5 |

Wide-table validation still scans all columns. Shared sparse writes must copy
the target payload to preserve the other result. Neither cost disappears.
Whole-column generation is close to baseline, including 193 → 201 µs for the
wide private fixture; its selected-row counterpart falls from 286 to 191 µs.

## R allocation, native scratch and payload copying

Bytes below are separate observations or counters, not estimates from `gc()`.
R bytes come from an untimed `profmem` observation after warming the profiler.
Native counters reset after fixture setup. Heap staging and journals count as
native scratch; stack staging does not. Target-copy bytes count old payload
copied during detachment, not every allocation needed for the new payload.

| Operation and backing, 1 column | R bytes, baseline → candidate | Native scratch bytes, baseline → candidate | Candidate target-copy bytes |
| --- | ---: | ---: | ---: |
| `set_row`, private | 0 → 0 | 16 → 0 | 0 |
| `set_whole`, private | 0 → 0 | 8 → 0 | 0 |
| `repl_row`, private | 280 → 0 | 16 → 0 | 0 |
| `bracket_row`, private | 280 → 280 | 16 → 0 | 0 |
| `gen_row`, private | 408,856 → 400,328 | 0 → 0 | 0 |
| `repl_fused`, private | 280 → 280 | 100,000 → 100,000 | 0 |
| `set_row`, shared | 800,048 → 800,048 | 16 → 0 | 800,000 |
| `set_whole`, shared | 800,048 → 800,048 | 8 → 0 | 0 |

The old 0 B R profile hid 16 bytes of native heap staging for a double scalar
row write and eight for a whole-column fill. Those now use the transaction's
stack buffers. A shared row write still copies 800,000 payload bytes. A shared
whole-column fill allocates replacement storage but need not copy the old values.
The fused path keeps its existing journal allocation.

The direct runner's `bench::mark` allocation observation and its warmed timing
iterations need not have the same sharing state. Its full allocation output is
retained in each `run.R.log`; the fresh-fixture matrix above establishes the
private/shared distinction explicitly.

## Component measurements

These isolated medians are not additive parts of an exact end-to-end model.
They identify setup that an eligible native call avoids and show that the
shared patch itself was already a small part of the old call.

| Component, one-column fixture | Baseline µs | Candidate µs |
| --- | ---: | ---: |
| Shape preflight | 1.19 | 1.15 |
| Target resolution | 0.78 | 0.72 |
| Row normalization | 2.60 | 2.58 |
| Value-size rule | 0.82 | 0.80 |
| Replacement cast helper | 2.44 | 2.36 |
| Shared-column scan | 0.12 | 0.14 |
| Capacity preparation | 1.27 | 1.27 |
| Scalar binding lookup | 1.54 | 1.54 |
| Scalar column generation | 22.21 | 12.75 |
| Native patch | 0.53 | 0.47 |
| Private view create/release | 0.55 | 0.53 |

The numeric replacement path already bypassed general vctrs casting, and the
fused comparison path already existed. This change removes setup around those
paths where eligibility permits it. It does not establish an unavoidable
remaining gap to data.table.

## Expression variance and controlled repeats

The full matrix includes slower expression medians in some conditions,
including about 19% for wide private `repl_expression` and 17% for
`gen_expression`. Its unchanged data.table row control was also about 16%
slower in that condition. Candidate expression upper quartiles reached
17 ms while typical calls took 2 to 3 ms. Those observations remain in the raw data.

A separate repeat collected fixture garbage before each timed call, using
`DTATOOLS_BENCHMARK_GC=before`. It used the same ABBA order, 50 samples per
condition, both widths and backing states, and six selected operations.
None of its 4,800 timed calls observed GC time. These post-collection timings
have a different starting memory state and should be compared within this
repeat. They are not replacements for the full matrix.

| Operation | 100 columns, private, baseline → candidate µs | 100 columns, shared, baseline → candidate µs |
| --- | ---: | ---: |
| `set_expression` | 57.6 → 58.2 | 83.0 → 83.2 |
| `repl_expression` | 2252.9 → 2218.5 | 2246.4 → 2232.7 |
| `gen_expression` | 2674.5 → 2630.6 | 2662.9 → 2681.2 |
| `bracket_create_expression` | 2812.9 → 2677.9 | 2804.4 → 2712.3 |
| `repl_promote` | 8864.4 → 8818.7 | 8833.3 → 8940.2 |
| `data_table_row` | 11.7 → 11.1 | 11.6 → 11.1 |

The larger expression and promotion cases stay within 5% of baseline across
this repeat's shapes. The largest increase is the small one-column shared
`set_expression` case, 63.3 → 67.9 µs, about 7%. In the full matrix the same
case differs by 1.25%.

These results support the scalar improvements and do not establish a persistent
16 to 19% expression regression. They also do not show every fallback getting
faster. The native eligibility probe adds work to a declined call, and fresh
fixture allocation history affects the observed latency. The
[controlled raw results](results-2026-09-20-shared-mutation/controlled/) retain
all medians and GC observations.

The benchmark itself needed two corrections during this work. Ineligible
argument forms initially paid for a second shape scan; that implementation
cost was removed before the recorded candidate revision. Separately, fixture
setup initially called `set_dta_values()` to make the target private. That
prepared baseline through its general path and candidate through its fast
path, affecting subsequent general-call timings. The recorded full matrix
uses the same native preparation on both revisions. The preparation experiment
establishes a dependency on setup; it does not identify a specific low-level
cache mechanism.


## Eligibility and policy

The detailed eligibility and fallback contract is in
[ADR 0043](../../docs/adr/0043-set-dta-values-is-the-loop-friendly-assigner.md#shared-numeric-scalar-fast-path).
The fast replacement path requires ordinary scalar logical, integer or double
inputs, positional rows or all rows, a supported numeric target, and an ordinary
ungrouped dibble.
Unsupported expressions, callbacks, grouping and storage promotion use the
existing paths. Generation keeps its storage defaults and capacity rules.

`data.table::set()` also checks types and ranges and permits some lossy
conversions with warnings. For example, assigning 1.5 to a selected row of an
integer column warns and truncates. dtatools additionally enforces Stata ranges,
missing tags and declared storage; fixed assignment rejects a value that needs
wider storage, while `repl()` and `:=` retain promotion. The timing comparison
uses values that fit unless a row explicitly tests promotion or rejection.

## Reproduction

Use a clean checkout containing the recorded runner and exact-source installs
for the two revisions. With `DTATOOLS_BENCH_LIB` unset, each runner installs the
requested revision itself. Execute the following for each revision in baseline,
candidate, candidate, baseline order, using a different output directory each time:

```sh
DTATOOLS_BENCHMARK_REVISION=75771518 \
  Rscript --vanilla benchmarks/r-cell-assignment/run.R 100000 200 1000
DTATOOLS_BENCHMARK_REVISION=75771518 \
  Rscript --vanilla benchmarks/r-cell-assignment/expanded.R 100000 50 100 /tmp/mutation-baseline-1
```

Replace the revision with `8ef15b82` for candidate runs. The controlled repeats
add these environment variables to the expanded command:

```sh
export DTATOOLS_BENCHMARK_GC=before
export DTATOOLS_BENCHMARK_OPERATIONS=set_expression,repl_expression,gen_expression,bracket_create_expression,repl_promote,data_table_row
```

The full matrix used runner `d72354a3`; the controlled repeats used `d06c2d95`.
Package source revisions and trees stayed fixed between them.
