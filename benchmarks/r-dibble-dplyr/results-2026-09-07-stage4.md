# Owned strings, logicals and factors, 2026-09-07

The latest storage candidate passes the local correctness, allocation, native
mutation and memory gates. Fifteen read timings still cross the investigation
threshold against both baseline runs. Three are delegated filtering costs that
the required Stage 6 migration must address. Twelve are per-element base-R read
costs, recorded below without a claim of general read-performance parity.
Overall epic performance acceptance remains open. PR review, CI and merge are
still required for Stage 4.

The initial benchmark matrix passed
its value, metadata, mutation-isolation, selector-allocation and retained-memory
checks, but 43 read cases exceed both the 10% and 1 ms regression thresholds.
Later targeted testing also found an Arrow-output callback bug: changing a
previously prepared owned string column could change the values written because
the descriptor retained its handle instead of the exact allocation. A separate
constructor regression let a foreign character vector with a removable class
remain aliased through an R metadata wrapper. Both findings were reproduced on
the exact initial package. That initial candidate did not pass acceptance.
Its measurements remain here as the history of the fixes and qualification.

## Initial candidate and source identities

The fresh baseline is merged Stage 3
`ec10a6ac34602f3bd691e8043019c1b479babda4`. The initial candidate is
`7d56080f3e97bc4d73a848e363d729767b9629c0`, with package tree
`82b95507e3ea9fe8b8658d7c2098b1f95f5c3756`. Both libraries were installed
from exact git archives with the committed installation helper. Installed
package provenance, installed-file hashes and the loaded DLL are checked before
and after measurement.

The atomic matrix uses committed runner revision
`b259ad5a521dbb867a0b8563e3a0c2262e298671` in both libraries. Its driver
checks all five R dependencies and its own Python bytes against that revision
before and after execution. Runtime R identities also record all five files.
The unchanged prior-double matrix uses runner revision
`ec10a6ac34602f3bd691e8043019c1b479babda4` in both libraries. A later native
factor-fixture correction is separate from this package source and these runners.

The [initial evidence index](results-2026-09-07-stage4/initial-evidence-index.json)
records the original path, SHA-256 and size of every copied artifact. All 157
files were copied byte-for-byte. Their historical paths and identities were not
rewritten. The [atomic comparison](results-2026-09-07-stage4/comparison-atomic-7d56080/operation-comparison.csv)
and [double comparison](results-2026-09-07-stage4/comparison-double-7d56080/operation-comparison.csv)
were derived only after verifying the recorded input hashes and matching runner
identities. Each comparison directory records its derivation script and input
manifest digests.

The first baseline memory attempt reached a passing R case, but macOS
`/usr/bin/time -l` could not read `sysctl kern.clockrate` in the sandbox and
exited without RSS. The successful operation artifacts and original manifest
were copied unchanged into a new directory. All 30 memory cases then passed
with read-only system-statistics permission. The [copy proof](results-2026-09-07-stage4/baseline-b259ad5-memory-retry-copy.json),
original attempt and qualified retry are all preserved. No operation timing was
rerun or relabeled for this retry.

## Measurement scope

Measurements ran sequentially on Apple M4 Max, macOS 26.6.2, R 4.6.1,
dplyr 1.2.1 and vctrs 0.7.3, with competing builds, tests and probes paused.
Each operation has seven timed iterations. Fixtures and independent value and
metadata oracles are prepared outside timing. The DTA writer wrapper collects
and checks the expected factor-conversion warning inside the measured call in
both revisions. No other warnings are hidden.

The atomic matrix covers ordinary `dta_string`, unclassed declared-width
character, logical, factor and ordered-factor columns at 100,000 and 1,000,000
rows. Selectors use 16 columns; reads use eight. Public dibble ingress still
promotes bare integers to the established compact `dta_long` double form.
Factors exercise owned integer backing through the public table interface.
The separate native supplement covers bare integer writes. Public factor writes
retain their established unsupported-type error.

The matrix has 206 operation/read rows, 126 selectors after reads and 18 public
write profiles. Oracles check full values, column attributes, table attributes,
attribute-name order and raw row-name bookkeeping. Read results stay alive while
source backing is checked before and after profiling, timing and a later
selector. Profiled and final timed DTA/Arrow files are read back independently.
Format-specific logical and factor conversions are checked explicitly.

The Python driver tests passed 87 synthetic success and rejection cases across
ordinary Python, `-O` and `PYTHONOPTIMIZE=1`. The R provenance checks passed 36
exact-diagnostic rejection/no-output cases and nine usage counterchecks, including
both the prior four-file and new five-file dependency identities. Five positive
and ten negative attribute-order probes passed. These checks test the runners;
they do not replace package behavior tests.

## Initial results

Both revisions completed every atomic case. All candidate selector allocation,
backing-sharing and unchanged-string scan guards passed. At one million rows
and 16 columns, rename measured:

| Storage | Baseline ms | Candidate ms | Baseline R bytes | Candidate R bytes |
| --- | ---: | ---: | ---: | ---: |
| `dta_string` | 136.639 | 0.595 | 128,084,824 | 84,056 |
| Declared character | 139.507 | 0.597 | 128,084,824 | 84,056 |
| Logical | 1.828 | 0.484 | 64,084,824 | 84,056 |
| Factor | 3.045 | 0.483 | 64,084,824 | 84,056 |
| Ordered factor | 1.840 | 0.482 | 64,084,824 | 84,056 |

Across all 40 direct selector/pipeline cases, cumulative R allocation is at most
449,360 bytes. The one-million-row five-verb pipelines use 422,240 bytes.
The equally safe delegated pipeline remains faster, and its separate rows are
retained in the full comparison. These are cumulative allocations, not retained
memory. Native copy counters overlap R allocation and each other and must not
be summed with them.

At one million rows, a first shared string write copies only its 8 MB pointer
payload; a logical write copies only its 4 MB payload. Subsequent private writes
copy no target payload and record 416 R bytes. Full replacement creates new
values without copying or journaling the old values. Source and result remain
isolated in both directions. The [write CSV](results-2026-09-07-stage4/candidate-7d56080-b259ad5/owned-atomic-writes.csv)
keeps staged values, validation scans and overlapping native byte counters
separate.

All 30 candidate memory processes pass with flat handle depth. Retained vector
heap with the source alive is 81,368 to 92,576 bytes across rename, five verbs
and fifty verbs. Final heap residuals after dropping the result are negative,
from normal baseline variation, and all are below the 1 MB release bound.
Whole-process RSS is 0.191 to 1.133 GB and includes startup, fixtures, retained
oracles and validation. It is not the operation's peak memory. The [paired
memory table](results-2026-09-07-stage4/comparison-atomic-7d56080/memory-comparison.csv)
reports RSS and retained heap separately.

The [43 flagged read cases](results-2026-09-07-stage4/comparison-atomic-7d56080/investigate.json)
include one-million-row logical row gathering at 24.03 ms versus 4.36 ms,
ordered-factor range at 23.06 ms versus 2.75 ms, and string Arrow output at
334.09 ms versus 185.17 ms. The initial comparison triggers investigation;
it does not establish that every difference is repeatable. These costs prevent
acceptance of this initial candidate while the affected paths are investigated.

The prior-double regression matrix passes all 46 operation/read cases, 30
selectors after reads, six write profiles, four captured-expression profiles and
six memory processes. No paired double operation exceeds both regression
thresholds. Nested string RHS capture records 16,000,312 R bytes versus the
baseline's 24,000,360 bytes. Arithmetic predicate capture remains 1,000,048 bytes.
These are measured capture costs, not general claims of zero-copy evaluation.

The [independent R regression bundle](results-2026-09-07-stage4/root-acceptance-7d56080/root-manifest.json)
passes all 219 historical behavior comparisons on the exact candidate. The four
R scripts and their baseline oracles were reused unchanged. This count excludes
the historical 18-case native names observer, whose original C source was not
recovered; its old binary was not used for this run. The original native mutation
runner remains a separate required gate.

Exact package checks and the corrected native supplement are recorded by the
implementation qualification. Final read-performance evidence, both nested
reviews, latest-head CI, substantive CodeRabbit review and normal merge are
still required. Stages 5 through 9 and final integrated/downstream validation
remain part of the epic.

## Intermediate native qualification

Read and callback fixes were reviewed and committed as
`976cc403f21b9adbb454d39c9c3447717b67c29f`, with package tree
`5918bf611151f8a2b78dbf3e704e67f70b1fb9a5`. Its fresh source archive
had MD5 `d027ec292ab4f0e7ba52559b0c2c2d6d`; the installed DLL had MD5
`f1b1a0fbdce2d388733638cb19d99709`. The 1,060-file repository export,
archive contents and installed package were verified independently.

This intermediate candidate passed full R package/conformance checks with the
baseline three warnings and two notes, plus Haven interoperability,
documentation, archive and binary checks. All 219 retained R behavior cases
passed again. The fertility R backend produced the same complete test log as
the retained baseline: 499 tests, four existing failed or errored blocks and two
skips. Its 454 tracked/nonignored files, Git state, and integration output's size
and modification time were unchanged. This was an isolated-library comparison;
the final merged-main check in the actual fertility renv remains required.

The unchanged native runner then failed its full dictionary-string replacement
timing assertion. A separately labelled diagnostic run measured 48 ms against
a 12 ms character-fill control. Allocation was 48,017,232 bytes, compared with
44,017,136 bytes in the initial candidate's native run. Paired profiling traced
the extra 4,000,096 bytes to two copies of the 250,000-entry character cache:
the new attribute helper's conservative fallback added R references before
attribute replacement. This is a production regression, not a reason to change
the native budget. The intermediate candidate was rejected. Full atomic/double
timing matrices were not run on it. The next candidate restores conservative
attribute assignment to its original caller frame and passes the unchanged gate.

A separately committed heap supplement,
`7003a46899ed508c4068e077e3aa1af7fff541f3`, passed both independent
reviews and all 36 fresh baseline processes. It adds R header-cell usage to the
unchanged memory workloads' vector-heap checkpoints. The final candidate also
passes all 36 processes. This measurement does not change the scope or bytes of the
earlier vector-heap and whole-process RSS evidence.

## Latest exact candidate

The measured source is `e343b3b56a8529e9ee0ac40f8bd88beebcd2be15`,
package tree `f12a2a1dd430636a33b7f6e953023d90d1ff2589`. Its installed
DLL has SHA-256
`9af2605a3c73b06f970578b11fd7ee39db652fd4a56c544ca7be060deda75efb`.
The [new evidence index](results-2026-09-07-stage4/benchmark-e343b3b/index.json)
preserves 447 artifacts byte-for-byte, with original paths, hashes and sizes.
It includes the recent baseline control, both full candidate matrices, all heap
processes, comparisons, independent regressions and downstream attempts. The
[qualification archive](results-2026-09-07-stage4/qualification/README.md)
records package and native checks; the
[diagnosis archive](results-2026-09-07-stage4/diagnosis/README.md) preserves
failed attempts, development probes and source evidence behind the fixes.

The unchanged atomic runner passes 206 operations and reads, 126 selectors
after reads, 18 public write profiles and 30 isolated memory processes. The
prior-double runner passes 46 operations and reads, 30 selectors after reads,
six writes, four captured-expression profiles and six memory processes.
No double operation exceeds both timing thresholds. The independent regression
bundle passes all 219 retained R cases again, with unchanged input scripts and
oracles. The historical native names observer remains excluded from that count.

The exact package passes the full R suite and required conformance, including
the Haven comparisons. `R CMD check` reports the existing three warnings and
two notes, with no errors. Documentation, archive, source-hash, installed NOTICE
and binary-isolation checks pass. The original 159 native assertions and 15
readiness checks pass, as do all 18 corrected integer/factor/ordered allocation
cases and the saved rename gate. Dictionary replacement returns to 32 ms and
44,017,136 R bytes. The original native timing and allocation budgets are unchanged.
Rust bridge checks ran on the exact exported source. The unchanged core
workspace checks are reused under explicit Git-object equality proof, rather
than described as a fresh run.

At one million rows and 16 columns, direct rename measures:

| Storage | Stage 3 ms | Latest ms | Stage 3 R bytes | Latest R bytes |
| --- | ---: | ---: | ---: | ---: |
| `dta_string` | 136.639 | 0.608 | 128,084,824 | 84,056 |
| Declared character | 139.507 | 0.590 | 128,084,824 | 84,056 |
| Logical | 1.828 | 0.480 | 64,084,824 | 84,056 |
| Factor | 3.045 | 0.479 | 64,084,824 | 84,056 |
| Ordered factor | 1.840 | 0.487 | 64,084,824 | 84,056 |

Direct selector/pipeline allocation remains at most 449,360 bytes across both
row counts. Five-verb pipelines allocate 422,240 bytes and take 2.67 to 3.35 ms.
The equally safe delegated five-verb reference takes 1.40 to 1.55 ms and allocates
98,248 bytes. Ownership benefits both paths; these measurements do not establish
a universal speed advantage for direct verbs. Shared first writes copy only
the changed 8 MB string or 4 MB logical payload. Later private writes copy no
target payload and allocate 416 R bytes. Full replacement avoids copying or
journaling old values. All source/result isolation and depth checks pass.

The 36 fresh
[paired heap cases](results-2026-09-07-stage4/benchmark-e343b3b/comparison-heap-e343b3b/heap-comparison.csv)
include doubles and all five atomic families. They count R header cells and
vector heap separately, infer the header size from five raw GC checkpoints,
then add the two components. Retained tracked heap is 86,032 to 227,104 bytes;
after dropping the final result, residuals are 57,936 to 209,592 bytes. Every case
is below 1 MB. At one million rows, string rename falls from 128,087,056 to
87,824 retained bytes; a fifty-verb string pipeline falls from 120,104,056 to
225,040 bytes. The header-inclusive residual shows why vector heap alone is
insufficient. These numbers exclude external native allocation, unused heap
capacity and process overhead. Whole-process RSS remains separate in the
original memory tables, including fixtures and validation.

## Remaining read costs and staged disposition

A recent baseline control repeats all 206 operations, 126 post-read selectors
and 18 writes on the exact Stage 3 library. All 206 R allocation measurements
match the original baseline. It supplements the original baseline and does not
replace its history or claim a second baseline memory run.

The candidate has the same 15 flagged cases against both baseline runs, all at
one million rows. The following times use the recent control. Full values,
metadata, source preservation and post-read allocation guards pass throughout.

| Storage and read | Recent baseline ms | Candidate ms |
| --- | ---: | ---: |
| Declared character `anyNA` | 0.285 | 2.625 |
| Declared character nonmissing count | 1.016 | 3.403 |
| Logical nonmissing count | 1.015 | 3.280 |
| Logical `as.character` | 3.017 | 4.999 |
| Logical `as.integer` | 0.270 | 2.434 |
| Logical mean | 1.832 | 3.824 |
| Factor `anyNA` | 0.250 | 2.444 |
| Factor nonmissing count | 1.016 | 3.212 |
| Factor `as.character` | 2.453 | 4.595 |
| Ordered factor `anyNA` | 0.250 | 2.441 |
| Ordered factor nonmissing count | 1.017 | 3.189 |
| Ordered factor `as.character` | 2.455 | 4.627 |
| Logical filter half | 5.267 | 9.189 |
| Factor filter half | 5.063 | 7.980 |
| Ordered factor filter half | 4.967 | 8.656 |

The first twelve add 1.98 to 2.39 ms per million elements, with unchanged R
allocation. R source inspection and separate getter prototypes identify
element-at-a-time access in these paths. R does not offer a logical/integer
ALTREP mean hook, and its string `anyNA` path does not use the available
`No_NA` fact hook. The production getter was reduced to a rooted backing record
with a cached read pointer. Prototype getter timings support that diagnosis;
they are not a proof of a universal lower bound or an aggregate benchmark.
The relative changes can be large for these short reads. They remain an
explicit limitation of the owned representation, not a claim of read parity.

The three filtering cases have a different cause. Their predicate reads only
row numbers. The current compatibility method still delegates whole-table
filtering on a tibble view, bypassing the package's shared batch gatherer.
Separate boundary measurements find owned snapshot slicing at 4.68 to 4.78 ms,
ordinary slicing at 1.37 to 1.41 ms and validated batch gathering at 1.60 to 1.64 ms.
Each slicing path allocates 16,000,384 R bytes. Predicate/mask overhead is
comparable. Final logical capture adds about 1.07 ms and 16 MB, while factor
and ordered-factor finalization take about 0.19 ms without payload capture.
Sampling places the owned slicing cost in vctrs's per-column base subset path.

This evidence permits the storage stage to advance under its passed safety,
allocation, native and memory gates. It does not declare general read-performance
acceptance. Stage 6 must replace the existing filter delegation with shared
evaluation and gathering, then rerun these exact cases against the retained
baseline. The remaining element-read costs must stay in the integrated
performance report. Stage 5's helper-context proof still precedes that migration;
no temporary dispatch class or early filter implementation was introduced here.

## Downstream comparison

The latest isolated-library fertility run and its unchanged retry both retain
499 tests, four known failed or errored blocks and two skips. Both strict
full-byte drivers fail because testthat adds one 18-byte line, `I believe in you!`,
after its completion marker. The installed testthat reporter source confirms
that it can emit this encouragement after failed tests.

The original logs, driver failures and guards remain unchanged. A separate
[read-only audit](results-2026-09-07-stage4/benchmark-e343b3b/fertility-e343b3b-praise-diagnosis/semantic-parity-addendum.md),
independently reviewed, verifies the unique footer location and proves that
removing only those 18 bytes in memory makes every other backend byte identical
to the retained baseline. It also verifies outcome counts, all 454 user-file
and Git-state records, the large output's size and modification time, the
absence of column-reallocation warnings, and exact package/DLL guards.
This establishes behavioral parity with a disclosed framework footer
difference. It does not turn either strict driver into a pass or clear the
four existing backend failures. The final merged package must still be tested
inside the actual fertility renv, with the original lockfile restored afterward.
