# Interim native-scanner prototype, 2026-09-06

This records source `95685536`, which was replaced by the final R-only stage 1
implementation. It is retained as measured research for the ownership stages.
It is not the final PR performance or validation result.

Stage 1 removes whole-table dplyr delegation for select, rename and relocate.
Every result still isolates ordinary borrowed payloads and checks current string
values. One native scan replaces repeated allocation-heavy validation; no source
address or class is treated as a lasting storage-validity claim.

## Fresh comparison

Both installations came from isolated source exports. Baseline:
`5ad44406f9b80db81789dcf7b7e1756c28502559`. Candidate package source:
`95685536e8b12c70aa252cd3842efad131204216`. Later source revisions replace this scanner with existing native primitives. The 2026-09-05 report and its earlier source revision
remain historical measurements, not the starting baseline for this change.

The full matrix contains 71 paired cases over 13 fixture shapes. These rows are
one million observations and 16 distinct columns. Seven iterations include GC;
fixture construction, initial warming and correctness checks are outside timing.
The host was Apple M4 Max, macOS 26.6.2, R 4.6.1, with dplyr 1.2.1 and vctrs 0.7.3.
Other test/build and fertility workloads were paused for the final comparison.

| Operation and representation | Baseline ms | Candidate ms | Baseline allocated MB | Candidate allocated MB |
| --- | ---: | ---: | ---: | ---: |
| Rename ordinary doubles | 2.163 | 2.164 | 128.045 | 128.045 |
| Rename ordinary dta_string | 225.875 | 52.556 | 640.049 | 128.078 |
| Rename declared character | 137.395 | 54.853 | 256.046 | 128.078 |
| Five symbol mutations, doubles | 29.302 | 27.602 | 640.219 | 640.220 |
| Five symbol mutations, dta_string | 1206.766 | 299.750 | 3216.242 | 640.379 |
| Five symbol mutations, declared character | 759.514 | 361.401 | 1244.226 | 600.379 |

Raw [baseline](results-2026-09-06-stage1/baseline/operations.csv) and
[candidate](results-2026-09-06-stage1/candidate/operations.csv) results include
identical-column typed-tibble controls. Values, attributes, input preservation
and compact-source assertions passed in every case. The only initial dibble
median regression above 10% and 1 ms was double filtering. Three further seven-iteration
comparisons did not reproduce it: baseline 134.38/147.09/140.88 ms, candidate
140.63/134.76/139.26 ms. Their allocation differed by only 280 bytes. The repeat
logs are retained beside the raw results. The typed-tibble compact-integer
control for the 100-row, 1,000-column five-verb pipeline also varied from
8.581 to 10.075 ms. That control does not use dibble result finalization; it is
reported as control variation, not omitted from the raw comparison.

The [separate column comparison](results-2026-09-06-stage1/columns.csv) uses the
same candidate finalizer after a whole dplyr verb as its safe-delegation control.
String rename measured 60.21 ms direct versus 62.15 ms delegated; declared
character measured 63.14 versus 63.12 ms. Both direct cases allocated 128,078,464
bytes, below the 130 MB gate. The host-specific target of less than 60 ms was met
in the full matrix but missed narrowly in this separate comparison. This stage's
measured benefit comes mainly from removing repeated validation, not from
eliminating retained payload copies. The future less-than-1-MB gate remains
pending owned backing and has not been enabled or weakened.

## Memory measures

MB above means 1,000,000 bytes of cumulative R allocation. It is neither retained
memory nor peak RSS. An isolated ordinary-string rename retained about 128.00 MB
of additional R vector heap in both builds. Nominal `object.size()` of each result
was 128,019,112 bytes. The native scanner's bounded, call-local cache is released
after validation; no source history is retained in reference bookkeeping.

Separate fresh processes measured maximum RSS of 529,088,512 bytes for baseline
and 447,119,360 bytes for candidate. These whole-process peaks include library
startup and fixture construction as well as rename, so they are not isolated
operation-only peaks. The R vector-heap delta excludes node headers and native
allocations. The [measurement script](retained-and-peak.R) and raw process logs
are retained with the results.

## Validation and review

- The new public selector suite passed 500 assertions without warnings or skips.
- Focused dibble, copy, numeric/string, mutation and slicing coverage passed
  3,718 assertions, with four existing factor-export, Date-comparison and
  tibble-row-name warnings.
- Fresh `R CMD build` and `R CMD check --no-manual` passed all 12,570 assertions
  and examples, with those four existing test warnings and no skipped tests.
  Check status was three warnings and two notes, matching the known baseline:
  macOS deployment-target linker warnings, GNU vendor Makefiles, a Rust `_abort`
  symbol, vendor CITATION location and a generated C file without a final newline.
- Required shared conformance passed 22 TypeScript fixtures, 32,085 decoded-cell
  comparisons, 10 native cases plus the fixture oracle, and the source R check.
- Repository Haven/labelled interoperability passed without skips after granting
  local loopback access to the HTTP fixture server.
- Roxygen regeneration matched committed manuals. Six archive-validation tests
  passed. Source archive, installed library and locally built macOS `.tgz` each
  contained the exact NOTICE; the release workflow now verifies installed and
  binary notices on every platform.
- Two independent actual-diff reviews found no actionable issues. They added
  5,100 selector comparisons against real dplyr, grouped/rowwise and alias checks,
  serialization/preparation probes, and native validation under forced GC. Review
  covered package source `95685536`, then benchmark head `c1e145bf`.

## Existing required allocation gate remains unresolved

The unchanged reference mutation gate **did not pass** on starting main or this
candidate. On both exact builds, every sparse patch in its first workload
allocated 5,000,048 bytes through `.deep_copy_value()` / `.mutation_copy()` /
`.mutate_data()` / `replace_values()`. The gate requires each allocation to stay
below the five-million-byte compact payload. A
[minimized reproducer](diagnose-reference-sharing.R) confirms the identical
failure in three calls. Full GC between calls and assigned `reserve_columns()`
do not remove the baseline sharing claim. No stage 1 code executes on that write
path, and neither its safety check nor the benchmark was changed.

The handoff requires this gate after native changes, so this native-scanner
prototype could not merge. The final stage 1 revision removes its native changes
and uses existing generation primitives. The original gate remains unchanged
and required before a subsequent native PR merges. Neither baseline evidence
nor that scope revision counts as passing this allocation gate.
The full runner stopped at that assertion, so its later allocation assertions
were not exercised by this run. Existing package rollback tests and the native
conformance gates passed separately.

## Reproduction

Use the exact isolated export/install procedure in [README](README.md), substituting
one of the recorded source SHAs. Then run from the repository root:

```sh
Rscript --vanilla benchmarks/r-dibble-dplyr/run.R LIBRARY OUTPUT SOURCE_SHA 7
Rscript --vanilla benchmarks/r-dibble-dplyr/columns.R LIBRARY OUTPUT SOURCE_SHA
/usr/bin/time -l Rscript --vanilla benchmarks/r-dibble-dplyr/retained-and-peak.R LIBRARY string
Rscript --vanilla benchmarks/r-dibble-dplyr/diagnose-reference-sharing.R LIBRARY
Rscript --vanilla benchmarks/r-reference-mutation/run.R
```

The column allocation gate is expected to fail on the old baseline. The minimized
sharing reproduction is expected to fail on the two recorded revisions. The
required gate must pass after repair before a later native PR can merge. The full reference runner builds the clean current checkout
itself; to reproduce starting main, run it in an isolated worktree at that SHA.
