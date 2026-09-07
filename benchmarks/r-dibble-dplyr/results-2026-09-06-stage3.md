# Owned ordinary-double backing, 2026-09-06

Stage 3 reduces a one-million-row, sixteen-column double rename from 128 MB
of cumulative R allocation to 84 KB. Select and relocate also stay below 1 MB
at both 100,000 and 1,000,000 rows, with no payload capture or target copy.
Ordinary results share tracked backing and remain isolated from later explicit
writes. Unknown borrowed values still require conservative capture.

The baseline is merged Stage 2 `fd069a36832ed7c1bdedeed52a4281ecabb36e25`.
The final measured source is `45f2ba489a6e0a2f25d1728eef0a84a6b2fde7b7`.
Both were built from git archives into fresh isolated libraries. Every runner
checks the exact source sidecar, installed-file hashes and loaded library.
The three owned-double runners are unchanged from their reviewed `6dcb9af`
versions. Their hashes and the historical runner hashes are recorded in each
[source manifest](results-2026-09-06-stage3/candidate/root-manifest.json).

Measurements ran serially while implementation and review builds/tests were
paused, on Apple M4 Max, macOS 26.6.2, R 4.6.1, dplyr 1.2.1 and vctrs 0.7.3.
Each operation has seven timed iterations with GC included. Fixtures, warming
and correctness checks are outside timing. MB means 1,000,000 bytes. Rprofmem
and bench allocation are separate measurements; the tables use Rprofmem except
for the historical matrix, which uses bench. Neither is retained memory or RSS.

The complete owned matrix passes 46 operation/read cases, 30 selectors after
reads, six write cases and four captured-expression cases. Value and metadata
checks use independent serialized reference values, including raw row-name
bookkeeping. All source-value, result-class, flat-depth and post-read selector
backing guards pass. DTA/Arrow roundtrips check the actual output before any reference write
could overwrite it. Arrow output is uncompressed and single-threaded. Root's
[237 exact-source mutation/capture/name checks](results-2026-09-06-stage3/qualification/root-qualification.log)
also pass. [Standard source conformance](results-2026-09-06-stage3/qualification/conformance.log)
passes, including the fresh R package check with no errors and the recorded
three warnings and two notes, ten native cases plus the fixture oracle, and
22 TypeScript fixtures with 32,085 cell comparisons. This is not a warning-free
check. The extra [as-cran check](results-2026-09-06-stage3/qualification/as-cran/r-check-network.log)
has zero errors, five warnings and four notes; it is a separate mode, not the
standard warning baseline. [Artifact verification](results-2026-09-06-stage3/qualification/final-artifact-verification.json)
records unchanged source files, identical packaged notices and the existing
106 exports. The [provenance driver](results-2026-09-06-stage3/qualification/benchmark-provenance.log)
passes 28 negative installation cases and seven usage-error cases across all
seven SOURCE_SHA runners. Other local and external PR gates are recorded in the
[progress record](../../docs/plans/dibble-result-performance-progress.md).

| Rows | Operation | Baseline ms | Candidate ms | Baseline MB | Candidate MB |
| --- | ---: | ---: | ---: | ---: | ---: |
| 100000 | rename | 0.705 | 0.493 | 12.845 | 0.084 |
| 100000 | select | 0.663 | 0.471 | 12.845 | 0.084 |
| 100000 | relocate | 0.772 | 0.581 | 12.847 | 0.086 |
| 100000 | pipeline_five | 4.612 | 2.737 | 63.425 | 0.422 |
| 1000000 | rename | 2.204 | 0.488 | 128.045 | 0.084 |
| 1000000 | select | 2.169 | 0.461 | 128.045 | 0.084 |
| 1000000 | relocate | 2.338 | 0.581 | 128.047 | 0.086 |
| 1000000 | pipeline_five | 26.179 | 2.750 | 632.225 | 0.422 |

The mixed five-verb pipeline renames, selects, relocates, replaces one column
with another, and renames again. At 1M rows the candidate's equally safe delegated
pipeline takes 1.374 ms and 0.098 MB versus 2.750 ms and 0.422 MB for successive dibble
operations. The comparison performs the plain pipeline before one safe finalizer;
each direct call constructs its own result. These measurements do not establish
that direct dispatch is always faster. Both improve on their matching baseline.
See all [operation comparisons](results-2026-09-06-stage3/owned-comparison.csv).

Read workloads use eight double columns and 1M rows. Each read/export is followed
by another rename, which allocates 83,192 bytes and copies no source payload.
All thirty post-read cases preserve metadata and share backing between the
source after the read and its subsequent selector result. The timed runner does
not compare source backing addresses immediately before and after each read.
A separate [untimed exact-source check](results-2026-09-06-stage3/qualification/read-backing-exact-45f2ba4.csv)
compares those addresses for all 15 read/export operations at both row counts;
all 30 cases pass, with source values, metadata, exposure and depth preserved.
It also repeats the post-read selector checks. The
[script](results-2026-09-06-stage3/qualification/check-owned-read-backing.R)
accepts `LIBRARY SOURCE_SHA OUTPUT_CSV` and runs from the repository root.
Selector dispatch is warmed on a separate four-row fixture. An initial cold
selector attempt exceeded the supplemental allocation limit and is retained
under discarded evidence; it is not a source-backing failure or accepted result.
The measured benchmark scripts remain unchanged.

| Operation | Baseline ms | Candidate ms | Baseline MB | Candidate MB |
| --- | ---: | ---: | ---: | ---: |
| sum | 1.218 | 1.125 | 8.000 | 0.000 |
| mean | 1.224 | 1.153 | 8.000 | 0.000 |
| range | 6.469 | 7.126 | 16.000 | 16.000 |
| coercion_double | 0.111 | 0.011 | 8.000 | 0.000 |
| coercion_integer | 0.554 | 0.452 | 12.000 | 4.000 |
| export_data_frame | 0.131 | 0.134 | 0.000 | 0.000 |
| export_tibble | 0.948 | 0.124 | 64.000 | 0.000 |
| arithmetic | 17.798 | 18.563 | 164.002 | 156.002 |
| mutate_arithmetic | 20.263 | 19.726 | 252.045 | 156.085 |
| filter_half | 68.192 | 27.298 | 722.055 | 50.083 |
| row_subset | 5.254 | 5.274 | 46.050 | 46.090 |
| read_dta | 7.128 | 4.538 | 192.042 | 64.081 |
| write_dta | 12.867 | 13.174 | 0.003 | 0.003 |
| read_arrow | 15.003 | 13.844 | 128.041 | 64.081 |
| write_arrow | 48.936 | 50.799 | 0.002 | 0.002 |

The first reviewed candidate, `6dcb9af279237402eedd7ca4147bfb8ecdc76337`, failed
read-performance acceptance despite passing correctness and allocation checks.
Four sequential baseline/candidate/candidate/baseline runs confirmed seven
regressions above both 10% and 1 ms. At 1M rows, range increased from 7.07 to 21.02 ms,
integer coercion from 0.554 to 3.524 ms, arithmetic from 17.77 to 21.29 ms,
mutate arithmetic from 20.19 to 22.23 ms, and filtering from 67.77 to 127.07 ms.
Range and filtering also regressed at 100k rows. The complete
[pre-fix comparison](results-2026-09-06-stage3/owned-before-read-fix-abba.csv)
and original measured source remain preserved.

Profiles traced range to repeated writable-pointer requests during base R
argument flattening. The correction passes an independent ordinary snapshot
into the existing range implementation. It retains the measured 16 MB allocation
and never exposes the owned payload. Public integer/logical conversion uses
R's native coercion routine on a rooted read-only payload, with normal snapshot,
extra-argument and tracing behavior. Bare owned missing masks and double
constructor validity avoid repeated scalar dispatch and temporary R vectors.
Invalid, attributed, classed and foreign values retain their established
validation and methods. Independent reviews compare range, arithmetic, warnings,
custom conversion returns, retained pointers and callback/GC behavior.

A fresh sequential baseline/corrected-candidate repeat passes all guards and
confirms closure of all seven regressions. At 1M rows it measures 7.066/6.486 ms
for range, 0.553/0.451 ms for integer coercion, 20.540/19.423 ms for mutate arithmetic,
and 68.785/27.160 ms for filtering. Arithmetic remains modestly slower at
17.565/18.626 ms, a 6.0% increase of 1.061 ms. No owned operation in either final
pair exceeds both thresholds. The
[repeat comparison](results-2026-09-06-stage3/owned-repeat-comparison.csv)
retains every case, including smaller timing increases.

At 1M rows, the first shared sparse write copies exactly one 8 MB target payload;
untouched columns retain their backing. The next proven-private sparse write
profiles zero R bytes and copies zero payload bytes, with 8 bytes staged and
16 native scratch bytes. Full replacement allocates its new 8 MB values while
copying zero old values and retaining no old-value journal. Native capture and
target-copy counters overlap each other and R allocation; they must not be added
together. [Raw write measurements](results-2026-09-06-stage3/candidate/owned-double-writes.csv)
include both lengths.

Arbitrary escaped-expression safety has a separate cost. The captured nested
string RHS fixture allocates 24.000 MB versus 16.000 MB on baseline, including
an 8 MB target copy. Ordinary string backing remains Stage 4 work. The arithmetic
where-expression fixture remains at 1.000 MB. These cases are separate from the
literal/private sparse-write gate; the allocation increase is retained in the
[candidate](results-2026-09-06-stage3/candidate/snapshot-cost-1000000.csv) and
[baseline](results-2026-09-06-stage3/baseline/snapshot-cost-1000000.csv) evidence.

Retained vector heap is measured after GC with source and independent oracle
alive. Each operation below runs in a separate process at 1M rows by 16 columns.

| Operation | Baseline retained MB | Candidate retained MB | Baseline process RSS MB | Candidate process RSS MB |
| --- | ---: | ---: | ---: | ---: |
| rename | 128.044 | 0.084 | 1268.449 | 1244.348 |
| pipeline_five | 120.047 | 0.087 | 1186.824 | 1232.749 |
| pipeline_50 | 120.043 | 0.093 | 1374.044 | 1256.735 |

Candidate retained heap also stays below 1 MB at 100k rows. Rename and five/50-verb
pipelines retain depth 1, preserve their source and release the final result's
backing when it is dropped. After dropping source, oracle and final result, all
candidate cases return within 1 MB of the pre-fixture heap baseline. Small negative
residuals reflect that process baseline; they are not negative allocations.
Nominal object sizes remain about 128 MB because they count logical column sizes,
including shared payloads. [All memory cases](results-2026-09-06-stage3/owned-memory.csv)
include those quantities separately.

Whole-process peak RSS includes startup, fixtures, operations and validation.
It remains broadly similar and is not peak memory attributable to an operation.
All twelve baseline/final-candidate processes returned exit 0. An earlier sandboxed
baseline attempt could not obtain macOS process statistics and is retained under
[discarded evidence](results-2026-09-06-stage3/discarded/memory-baseline-sandbox-denied.log);
it contributes no accepted RSS value.

The historical double matrix separately passes 36 operation and 12 component
cases, including the original five-mutation pipeline and a 100-row by 1,000-column
fixture. Its component medians are not additive profiles of a public operation.

| Rows | Columns | Operation | Baseline ms | Candidate ms | Baseline MB | Candidate MB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1000000 | 16 | filter_half | 135.561 | 54.944 | 1434.068 | 90.084 |
| 1000000 | 16 | pipeline_five | 26.749 | 2.890 | 640.219 | 0.416 |
| 100 | 1000 | rename | 11.723 | 11.650 | 1.274 | 0.474 |
| 100 | 1000 | filter_half | 74.604 | 79.655 | 10.554 | 0.698 |
| 100 | 1000 | pipeline_five | 86.718 | 91.454 | 5.921 | 1.921 |

No historical operation crosses both regression thresholds. The wide pipeline
is still slower in elapsed time while allocating less. Candidate constructors
also give the typed-tibble fixtures owned backing, so those fixtures are not
fixed-representation controls for the new handles. Full
[baseline](results-2026-09-06-stage3/historical-baseline/operations.csv) and
[candidate](results-2026-09-06-stage3/historical-candidate/operations.csv)
matrices preserve their container-specific results.

The [exact-source native runner](results-2026-09-06-stage3/qualification/native-runner-exact-45f2ba4.md)
also passes all 159 original assertions plus 15 provenance/readiness conditions,
with no numerical bound changes. Root independently checks that every original
assertion expression remains in order. Repeated generation at 400 and 1,600
columns takes 0.122 and 0.815 seconds, with 3,256 and 12,856 profiled bytes above
the original 1,000-byte threshold. These are thresholded allocation measurements;
they neither mean zero total allocation nor establish arbitrary-width linearity.
Borrowed first capture is measured separately from proven-private writes. The
[saved rename allocation gate](results-2026-09-06-stage3/qualification/rename-allocation-exact-45f2ba4.log)
also passes against this exact installation.

The downstream R shadow-backend suite exactly matches the Stage 2 baseline:
499 tests, four existing integration failure blocks and two skips. Its complete
output after the source header is identical, with no column-reallocation warning.
This is not an all-passing downstream suite. All 454 source-file hashes, Git state
and the integration output file's size/timestamp remain unchanged. The concise
[verification](results-2026-09-06-stage3/qualification/fertility-exact-45f2ba4-verification.json)
records this comparison; detailed downstream output remains in local validation.
Final integrated downstream qualification is still required after all epic stages.

Checked-in evidence copies normalize line endings and trailing whitespace only.
Numbers and source/runner identifiers are unchanged. Output hashes in copied
manifests bind original process artifacts; the
[evidence index](results-2026-09-06-stage3/evidence-index.json) records hashes of
both originals and normalized copies. Stage 3 qualifies ordinary-double backing;
strings/logicals/integers, the remaining direct verb families and optional dplyr
remain subsequent stages.
