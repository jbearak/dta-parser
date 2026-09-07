# Owned strings, logicals and factors, 2026-09-07

Stage 4 qualification is still in progress. The initial benchmark matrix passes
its value, metadata, mutation-isolation, selector-allocation and retained-memory
checks, but 43 read cases exceed both the 10% and 1 ms regression thresholds.
Later targeted testing also found an Arrow-output callback bug: changing a
previously prepared owned string column could change the values written because
the descriptor retained its handle instead of the exact allocation. This
candidate has not passed acceptance. Its measurements remain here while the
read paths and callback handling are corrected and reviewed.

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
