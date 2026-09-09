# Direct summaries and nesting: measurements and tradeoffs

Source `3db15d44f2b557f5282fb7a30fd59c7980a4484c`, package tree
`fd8642daf27875e5cece5822e1ac9cd5615ff3c6`, has no joint timing flags in the original 54-shape grid. It reduces the
observed superlinear nesting allocation increase and repeated-call memo retention. Four
many-small-group latency regressions against the predecessor public route
persist across three paired repeats. For those many-small-group cases, the fixed
safe reference is slower.
These are measured tradeoffs, not an overall zero-regression claim.

The comparison uses the fresh installed predecessor
`4d07d656dc95cd2cf5fae12c1dc08d6fae4f8d2c` and a fixed safe reference built on
that installation. The predecessor public nesting route has the reproduced
foreign-write defect and is a weaker control. The fixed reference captures
nested frame leaves independently of the candidate finalizer; its safety checks
cover the declared workload shapes. Both remain separate from candidate public
calls. All measurements use host R 4.6.1 in coordinated windows without other
agent R/build/audit workloads, not an exclusive-machine guarantee.

## Whole operations

The six workloads cover 100,000 and 1,000,000 rows, eight and sixteen mixed-type
payload columns, and sixteen and 128 groups. Six one-group controls at one million
rows and eight payload columns bring the total to 54 shapes. Each source also
contains its grouping key. Fixtures and correctness checks precede measurement.
Seven elapsed samples per series include garbage collection.

None of 108 candidate/predecessor pairs in this matrix exceeded both 10% and
1 ms. Twelve timing comparisons still increased. The largest absolute increase
was 13.816 ms, or 1.96%, for width summary at 100,000 rows, sixteen payload columns
and 128 groups against predecessor public. The largest relative increase was
4.19%, or 0.940 ms, for group_nest at 100,000 rows, eight payload columns and 128
groups against public. These are observed single-grid comparisons; the larger
group-count follow-up below has repeated timing flags.
The [complete comparison table](stage7-summary-nesting-comparison.csv) retains
all 108 pairs, positive deltas, first/warm allocations and native counters.

At one million rows, eight payload columns and 128 groups:

| Workload | Predecessor public ms | Fixed safe ms | Candidate ms | Fixed safe R MB | Candidate R MB |
| --- | ---: | ---: | ---: | ---: | ---: |
| One-column summary | 62.08 | 62.16 | 58.19 | 136.27 | 36.17 |
| Width summary | 431.05 | 430.79 | 417.34 | 328.85 | 84.62 |
| Reframe selected rows | 78.26 | 79.84 | 75.65 | 162.28 | 62.18 |
| Identity group callback | 479.65 | 479.70 | 428.01 | 417.57 | 348.84 |
| Group nest | 65.82 | 89.39 | 58.76 | 62.53 | 80.25 |
| Nest by | 66.45 | 89.33 | 57.13 | 62.56 | 80.27 |

Times are median milliseconds; R MB are warmed Rprofmem totals for one call,
using decimal megabytes. Nesting retains a cumulative-allocation tradeoff:
about 80.3 MB versus 62.5 MB for the safe reference here, despite lower medians.
Across the full matrix, 32 comparisons have higher warmed R allocation. The
predecessor public nesting route records about 48.1 MB here. Native capture counters
also rise for the identity callback, from 44 MB to 52 MB at this shape, despite its
lower R allocation. They overlap Rprofmem and must not be added to it. Profile stacks
identify observed allocations, not an exclusive CPU cause or proof that every cost is unavoidable.

## Many small groups

The follow-up uses 1,024 and 4,096 groups, two rows per group, an integer grouping
key and one integer payload column. The initial installed run is followed by
three fresh serial pairs in candidate/predecessor, predecessor/candidate, then
candidate/predecessor order. Each series has seven GC-inclusive samples. Values
and complete recorded schemas agree across sources. These integer fixtures are
read-only: the separately reproduced logical/single-row write defect does not
establish that these specific outputs were unsafe.

All four public-route comparisons exceed both 10% and 1 ms in every repeated
pair. The ranges below are minima and maxima of three series medians, not
individual-sample ranges or confidence intervals.

| Groups | Operation | Predecessor public ms | Candidate ms | Fixed safe ms |
| ---: | --- | ---: | ---: | ---: |
| 1,024 | Group nest | 35.34–35.77 | 68.04–69.91 | 182.69–186.68 |
| 1,024 | Nest by | 40.40–40.72 | 71.70–72.50 | 189.40–190.99 |
| 4,096 | Group nest | 151.50–153.24 | 288.27–291.56 | 712.50–719.72 |
| 4,096 | Nest by | 165.17–167.87 | 325.31–331.03 | 737.77–741.61 |

The paired public increases are 31.3–165.9 ms, about 77–100%; candidate medians
are about 55–63% lower than the fixed safe reference. This is a remaining latency
limitation for many small groups. The complete gap is not attributed to required
safety work, and no claim is made that it is unavoidable.

| Groups | Operation | Predecessor public R MB | Candidate R MB | Fixed safe R MB |
| ---: | --- | ---: | ---: | ---: |
| 1,024 | Group nest | 0.091 | 0.680 | 82.501 |
| 1,024 | Nest by | 0.378 | 0.810 | 82.788 |
| 4,096 | Group nest | 0.115 | 2.468 | 329.514 |
| 4,096 | Nest by | 1.244 | 2.982 | 330.643 |

Allocation totals are identical across the repeats. Fourfold group growth now
uses 3.63 times the R allocation for group_nest and 3.68 times for nest_by,
versus approximately fifteenfold growth on a048. Group_nest changes from
15,795,248/239,134,496 bytes at 1,024/4,096 groups to 679,976/2,467,976 bytes.
The largest candidate R event at 4,096 groups is 131,120 bytes, versus 65,584
for a048: lower cumulative allocation does not mean every allocation shrinks.
C18 separately passes its installed public ratio budget; copied controls and
the high-cardinality runs retain the exact measurements. This finite comparison
does not establish asymptotic complexity.

The [three-pair summary](stage7-evidence/3db15d44/assessments/highcard/root-repeat-summary-3db15d44-01.json)
records each pair assessment and run order. Its original local paths map to
repository copies through the [selected evidence index](stage7-evidence/3db15d44/index.json).

## Retained heap and peak memory

The memory matrix uses six fresh candidate children: three operations at both
row counts, eight payload columns and 128 groups. Each child makes 50 calls from
the same original source, retaining source and latest result. It neither retains
all intermediate outputs nor nests the preceding output. The twelve predecessor
public/safe children use the same lifetime. The known public write-isolation
defect is separate from this read-only memory measurement.

| Operation | Rows | Safe reference RSS MB | Candidate RSS MB | Candidate Ncells 5 to 50 | Candidate vector bytes 5 to 50 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Identity group callback | 100,000 | 261.31 | 274.09 | 85 | 2,504 |
| Identity group callback | 1,000,000 | 860.06 | 768.29 | 85 | 2,504 |
| Group nest | 100,000 | 231.83 | 260.11 | 85 | 2,504 |
| Group nest | 1,000,000 | 756.79 | 716.19 | 85 | 2,504 |
| Nest by | 100,000 | 232.42 | 245.97 | 85 | 2,504 |
| Nest by | 1,000,000 | 757.02 | 581.45 | 85 | 2,504 |

All three 100,000-row peaks are higher than the safe reference; the three
one-million-row peaks are lower. Whole-child
`time -l` RSS includes startup, fixtures, operations, validation, state collection,
GC and release. It is not a per-operation or per-checkpoint peak. Heap checkpoints
0/5/50 precede their state inspections; after-validation heap follows state
collection. Warmed prefixture measurement follows warm validation/state work and
release. Ncells and vector bytes are separate; vector residual is not total
retained memory. The recorder retains small rows and other bookkeeping.

All six candidate cases retain 2,307–2,308 Ncells and 46,976–46,984 vector bytes
after source/result release relative to warmed prefixture. These residuals are
not zero and do not establish an asymptotic bound. The callback residual exceeds
its safe reference by 329 Ncells and 6,272 vector bytes at both row counts.
Recorded source values, metadata, native membership/depth/bytes and state checks pass; the compact
integer column remains distinguished from owned atomic columns.

The unchanged installed-source 500-call follow-up uses 256 rows and 128 groups.
Between calls 5 and 500, candidate growth is 131 Ncells and 3,120 vector bytes,
versus 36,386 and 196,480 for installed source 96. Between calls 50 and 500 it is 46
Ncells and 616 vector bytes. After release it remains 2,475 Ncells and 49,576 vector
bytes above warmed prefixture; ten extra GC-only records leave 2,597 and 51,744.
Recorder overhead is not subtracted. All final values/schema/source and 6,261
recorded native-state rows pass. This child supplies no timing or RSS claim.

The fresh-child C17 regression separately checks the public operation after
five warmups and 100 calls, plus source/output values and package selection.
Installed 96 fails the 1,000-Ncell budget at 36,169; candidate host and minimum-R
tests pass. The successful test does not save an exact green Ncell delta.
Twelve separate 50-call write cases preserve source/early/latest results and
logical constants while verifying each intended target change.

## Diagnosis, evidence and remaining work

The earlier 96 grid also had no joint flags but eight positive timing deltas,
with a different set of cases. Its memory growth remained through extra full
GCs. Copied original/fixed-entry controls supported changing address-named
environment bindings to character address values and fixed-field rooted entries.
The copied 5-to-500 deltas were 37,271/131 Ncells and 201,200/3,120 vector bytes.
Those copied routes are distinct from the final installed 500 result above.
An earlier plain-list entry control crashed on cyclic input despite passing
acyclic memory checks; the fixed-entry route separately passes cyclic rejection,
healthy recovery, shared siblings and both numeric foreign-write directions.
The precise C-stack mechanism is not claimed. The later high-cardinality control separates two sources of growing allocation:
per-sibling prefix matching and global linear memo matching. The combined repair
precomputes first sibling identities once and uses the public utils address-hash
API with actual object keys and fixed-field rooted entries. Host and minimum-R
controls check cycle rejection, sibling identity, typing, writes and forced-GC results.
The API is marked experimental; the supported R 4.6.0/4.6.1 behaviors were tested.
Earlier address-keyed result environments remain a final-epic audit obligation.

The [selected repository evidence](stage7-evidence/README.md) contains actual
source copies, commands, receipts, raw timing CSVs and heap/RSS rows, with an
index mapping original paths to exact copied bytes. It explicitly lists omitted
runtime images, full inventories, profiles and native-state tables that remain
local. Those local files are not available merely by following a manifest path.
The comparison CSV is copied without modification,
SHA256 `836462f65e16d32c4c325d7d000f8b9c93e0cb44365d479fc63c7ebdb481e1b6`.
Timing and memory assessment hashes are respectively
`9ee95bd9375c5296c4938fb7589f90a2bdbe17d7cc866841c9c9ae44f0e34623` and
`946208bdd624eed980693ad7188581019a4d5980168a5606afe8414fcf9f03d8`.
Historical failed candidates and recorder attempts keep their original pins
in the retained local qualification directory.

This stage does not close the twelve remaining base-R read regressions introduced
earlier. Stages 8–9 and validation in the actual fertility renv remain required;
issue #172 stays open. Functional/package/platform checks and actual implementation
CodeRabbit review remain separate gates, tracked in the
[progress record](../plans/dibble-result-performance-progress.md).
