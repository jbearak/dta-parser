# Direct dibble row and grouping operations, 2026-09-06

Stage 2 shares batch row gathering across ordinary reference-frame brackets,
`slice_dta_rows()` and dplyr row hooks. Package-owned grouping validation and
reconstruction replace runtime dplyr calls in those paths and native grouping
consumers. Each entry point retains its indexing, drop, row-name and container
policy. Grouped dataset metadata preservation and rowwise dibble helper support
are documented improvements. The raw row-name correction also repairs Stage 1
plain rename and removes the spurious Arrow row-name warning.

## Exact sources and validation

The baseline is merged Stage 1 `c8173b2af7105596f8a59e28e61a9bdd49fa8c3f`.
The measured package source is `c6696c9915c0b5e951727d1f3ed9ec80cfeffd68`.
Both were exported from git, built as source archives and installed into separate
fresh libraries. The row runner is the `da40094` version, unchanged at runner
head `cca6e8b`, MD5 `72fb3dc173e42b8e8ca4c797b2c4cc71`. The separate memory
runner includes the supplied-dibble guard at `cca6e8b`, MD5
`41a5731788317005587688adb65b2ef7`. All timings ran serially on an idle Apple
M4 Max, macOS 26.6.2, R 4.6.1, dplyr 1.2.1 and vctrs 0.7.3.

- Full standard conformance, package checks and examples passed: 13,953 test
  assertions, no failures or skips, and the four existing test warnings.
  R CMD check retained three baseline warnings and two notes: macOS deployment
  target linking, vendor GNU Makefiles, Rust `_abort`, vendor CITATION placement
  and a generated C file's missing final newline. This is not a warning-free check.
- The focused installed suite passed 3,984 assertions without warnings or skips,
  including 730 row assertions. Serialized grouped/rowwise reference fixtures
  run in a fresh process that asserts dplyr remains unloaded.
- Haven and labelled interoperability, pinned roxygen, six archive tests,
  byte-identical source/installed/macOS binary NOTICE and the 106-export
  comparison passed. Native source and Imports are unchanged.
- Both independent code fix reviews are clean. Correctness review compared 111
  key-validator cases, 735 partitions and 80 alias/cache/serialization cases,
  plus eight context corners. API review independently compared 66 validator
  cases, including custom record equality proxies and temporal casts. These
  supplement the earlier independent indexing, metadata and ownership reviews;
  withdrawn unmarked-reference probes remain excluded.

## Paired results

The complete matrix contains 96 cases, with nine iterations including GC.
Fixture construction, warming and correctness assertions occur outside timing.
All output-equivalence, source-value/attribute and compact-state guards passed.
Full-row comparisons use independently deserialized data. Grouped fixtures have
16 ordinary double columns and one explicitly ordinary double key with 1,000
groups; actual representation is asserted. Earlier compact-key setup was rejected
because baseline serialization materialized that key. Compact row fixtures remain
separate and assert unmaterialized source backing before and after operations.

The table uses one million input rows. Brackets and row hooks select every
other row, producing 500,000 output rows; reconstruction uses that same half-row
candidate. Validation and delegated mutation use the full input. MB means
1,000,000 bytes of cumulative R allocation; it is neither retained memory nor
peak RSS.

| Operation | Baseline ms | Candidate ms | Baseline MB | Candidate MB |
| --- | ---: | ---: | ---: | ---: |
| Double bracket | 152.68 | 5.99 | 1544.067 | 76.051 |
| Double row hook | 131.94 | 3.65 | 1408.066 | 66.042 |
| Compact integer bracket | 54.15 | 5.92 | 24.042 | 28.051 |
| Compact integer row hook | 40.58 | 3.03 | 16.042 | 18.042 |
| String bracket | 188.33 | 145.16 | 520.046 | 394.053 |
| Mixed bracket | 101.58 | 41.91 | 540.049 | 136.051 |
| Grouped bracket | 208.79 | 62.59 | 2006.036 | 453.337 |
| Grouped reconstruction | 54.42 | 56.51 | 506.011 | 441.332 |
| Grouped validation | 88.93 | 32.93 | 681.073 | 229.246 |
| Grouped mutation (delegated) | 161.19 | 133.27 | 970.551 | 747.970 |

Raw [baseline](results-2026-09-06-stage2/baseline/rows.csv),
[candidate](results-2026-09-06-stage2/candidate/rows.csv) and
[comparison](results-2026-09-06-stage2/comparison.csv) files retain all cases,
GC counts and allocation results. Checked-in evidence copies normalize line
endings and trailing whitespace; session copies omit author-local library paths.
The original process output is retained separately. Numerical fields and source
identifiers are unchanged. Shared-gather measurements are independent
microbenchmarks, not additive components of the public-operation medians.

## Regressions investigated

The first complete pair on earlier production `544af28` exposed structural
regressions: 1M-row grouped reconstruction allocated 1,137 MB versus 506 MB,
and the 1,000-column helper allocated 16.922 MB versus 0.732 MB. Controlled
profiles found repeated class restoration of expanded keys and repeated address
membership hashing. The final code casts observed group keys before expanding
equality proxies, checks partitions with linear counts and batches membership.
It retains input and final-result validation, roots source columns throughout,
and never caches validity or ownership on a table.

The final 100-row by 1,000-column double helper measures 5.39 to 5.11 ms and
0.732 to 0.803 MB; compact integers measure 5.62 to 5.39 ms and 0.284 to
0.355 MB. The remaining 71,872-byte planning difference is per-column overhead.
Compact integer brackets and row hooks allocate an additional 4.009 and 2.001 MB
at one million rows, respectively, while substantially reducing elapsed time.
Their row-location planning remains linear; this is not a payload-sharing claim.

One final case crossed the 10% and 1 ms investigation threshold: reconstruction
of 10,000 rows with 1,000 groups measured 2.84 to 3.97 ms. Three fresh-fixture
repeats, each with fifteen iterations, ran in separate baseline and candidate
processes. They confirmed 2.787/2.752/2.751 ms baseline versus
3.983/4.154/4.029 ms candidate. Allocation improves from 5,257,256 to
4,927,640 bytes; GC counts increase from two to four. The new hook validates the
supplied template before reconstructing. Call traces confirm that extra input
check and final group validation; the intermediate frame has grouping removed.
The standalone template-validation matrix case measures 2.06 ms. These medians
are not an additive profile, but the trace identifies the additional validation
work. The cost is retained to reject malformed templates before reconstruction.
At 100,000 and 1M rows reconstruction changes by 3.2% and 3.8%, respectively,
with lower allocation. No other final matrix case crosses both thresholds.
Raw repeats and call traces are stored alongside each side's results. This small
reconstruction regression remains an explicit native-stage and final-epic rerun
item; no timing threshold or validation requirement was relaxed.

The [fresh column check](results-2026-09-06-stage2/candidate/columns.csv) passes
the Stage 1 portable ordinary-string and declared-character rename allocation
gate at 128,044,648 bytes, below 130 MB. Their medians are 131.69 and 132.87 ms,
so the inherited 60 ms host target remains unmet. Prior Stage 1 timings retain
their own source labels; they are not attributed to this row revision.

## Retained memory and process peak

Separate fresh processes measure a 1M-row, 16-column half-row bracket. The R
vector-heap delta is sampled after GC immediately around the operation and
before result comparison. It excludes node headers and native allocations.
`object.size()` reports nominal result size, which can differ from actual
compact backing. Whole-process peak RSS includes R startup, fixtures, frozen
oracle bytes, the operation and correctness work, including oracle/result
materialization. It does not measure operation-only peak allocation. All values
below are decimal MB; raw process logs accompany the CSVs.

| Representation | Baseline retained R heap | Candidate retained R heap | Nominal result | Baseline process peak | Candidate process peak |
| --- | ---: | ---: | ---: | ---: | ---: |
| double | 64.001 | 64.000 | 64.017 | 1293.844 | 1290.486 |
| compact_int | 16.002 | 16.000 | 64.017 | 505.037 | 468.730 |
| string | 64.004 | 64.000 | 64.019 | 1348.682 | 1341.047 |
| dict_string | 64.005 | 64.005 | 64.023 | 1377.436 | 1377.796 |

The initial sandboxed `time -l` invocation could not read macOS system accounting;
its incomplete RSS result was discarded. Both complete accepted sides use the
same runner with accounting access. All actual-source byte and representation
guards pass. These results do not establish native payload ownership or certify
unknown borrowed storage.

## Scope and remaining gates

Expression-based `slice()` remains Stage 6, full vctrs/binding integration
Stage 8, and genuine dplyr-absent installation Stage 9. The installed namespace
probe is not an absence test. Pristine dplyr 1.1.0 and 1.2.0 fail compilation
under R 4.6.1 before package code runs; Stages 5 and 9 must qualify an installable
supported minimum. Current dplyr 1.2.1 is tested here.

The existing native allocation and private-seam alias-escape findings remain
open. Stage 3 must qualify unchanged budgets and guarantees with explicitly
reviewed assigned fixture setup and separate unknown-capture/private-write
measurements. No native code, sharing check or rollback gate changed in this PR.
The package's 106 exports remain; issue #172 stays open for the later stages.

Reproduce the paired matrix and separate memory processes with the commands in
[README](README.md), using the exact source installations above.
`repeat-group-reconstruct.R LIBRARY OUTPUT_CSV SOURCE_SHA` reproduces the small
case investigation with three independent fixtures and fifteen iterations each.
Final evidence reviews and latest-head CI/CodeRabbit gates must complete before
this stage merges.
