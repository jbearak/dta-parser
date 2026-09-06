# Direct dibble column operations, 2026-09-06

The final stage 1 implementation replaces whole-table delegation for select,
rename and relocate with direct selector plans and a shared result finalizer.
It copies ordinary retained payloads and validates current string values through
the existing character-generation kernel. No native source changes. A copied
string result is reused only when its values and attributes are identical to
the source; missing values, stale declarations and unsupported encodings retain
the prior safe typing path.

## Exact-source validation

Starting main is `5ad44406f9b80db81789dcf7b7e1756c28502559`. Final package source is
`be9eac34b2d52efa664b9f0eb9f6e0d9e8e41c9c`, exported and installed in an isolated
library from its freshly built source archive. All timing runs were serial while
other package and fertility CPU workloads were paused. The host was Apple M4 Max,
macOS 26.6.2, R 4.6.1, dplyr 1.2.1 and vctrs 0.7.3. The complete matrix contains
71 paired cases over 13 fixture shapes, with seven iterations including GC.
Fixture construction, warming and correctness assertions are outside timing.

- The final selector, encoding and metadata suite passed 568 assertions with
  no warnings, skips or failures.
- The required conformance script passed 22 immutable TypeScript fixtures,
  32,085 decoded-cell comparisons, 10 deterministic native cases and the native
  fixture oracle. It built the current source archive and completed the full R
  package tests and examples.
- R CMD check reported three warnings and two notes, matching the starting
  revision's native/vendor diagnostics: macOS deployment-target linker warnings,
  GNU vendor Makefiles, a Rust `_abort` symbol, vendor CITATION location and a
  generated C file without a final newline. This is not a warning-free check.
- Repository Haven interoperability completed without skips. Roxygen-generated
  documentation matched the committed manuals; six archive tests passed.
- Source, installed and locally built macOS `.tgz` notices were byte-identical.
  The actual release workflow's installed/binary notice smoke code also passed.
- Both independent reviewers inspected the revised actual diff and its gate
  applicability. Additional review passed 3,600 real-dplyr selector comparisons,
  105 baseline metadata/encoding/stale/NA/custom-class/ALTREP cases, nine exact-build
  metadata/encoding cases, forced-GC generation and error-propagation checks.
  The earlier selector reviews independently passed another 5,100 cases.
  Final report review follows the completed measurements.

## Paired performance

These rows use one million observations and 16 distinct columns. MB means
1,000,000 bytes of cumulative R allocation, not retained memory or peak RSS.

| Operation and representation | Baseline ms | Candidate ms | Baseline MB | Candidate MB |
| --- | ---: | ---: | ---: | ---: |
| Rename, doubles | 2.158 | 2.168 | 128.045 | 128.045 |
| Five symbol mutations, doubles | 13.654 | 28.623 | 640.219 | 640.220 |
| Rename, dta_string | 223.545 | 129.633 | 640.049 | 128.045 |
| Five symbol mutations, dta_string | 1187.692 | 652.909 | 3216.242 | 656.220 |
| Rename, declared character | 137.885 | 122.184 | 256.046 | 128.045 |
| Five symbol mutations, declared character | 752.557 | 704.790 | 1244.226 | 604.220 |

Raw [baseline](results-2026-09-06-stage1/baseline-final/operations.csv) and
[candidate](results-2026-09-06-stage1/final/operations.csv) results include
identical-column typed-tibble controls. All value, metadata, input-preservation
and compact-source checks passed. Two initial dibble pipeline medians exceeded
the 10% and 1 ms investigation threshold: doubles above and logical columns at
5.175 versus 7.217 ms. Three isolated seven-iteration repeats did not reproduce
either result. Doubles measured 26.20/25.46/34.99 ms baseline versus
25.89/25.34/35.08 ms candidate. Logical columns measured 5.61/4.91/5.12 versus
5.65/4.98/5.15 ms. Paired repeats had identical GC counts. Allocation differed
by 1,400 bytes for doubles and 6,080 bytes for logicals. No other matrix case,
including controls, exceeded that threshold. Raw repeat logs accompany the CSVs.

The [separate column comparison](results-2026-09-06-stage1/final/columns.csv)
compares direct execution with whole-verb delegation using the same candidate
finalizer. String rename measured 130.91 versus 132.47 ms; declared character
measured 130.97 versus 133.31 ms. Both direct cases allocated 128,044,928 bytes,
passing the portable 130 MB gate. The host-specific 60 ms target is not met.
The benefit comes mainly from combining isolation and validation, while direct
selector planning establishes the common result path for later stages. Retained
ordinary payloads still copy; the future less-than-1-MB ownership gate remains
pending and unchanged.

## Retained memory and process peak

An isolated ordinary-string rename retained 128,000,320 additional bytes of R
vector heap on baseline and 128,000,440 on candidate. Nominal `object.size()` of
both results was 128,019,112 bytes. No permanent validity or ownership token is
inferred from those results. Separate fresh-process peak RSS measured
529,678,336 bytes on baseline and 451,084,288 on candidate. These process peaks
include startup and fixture construction as well as rename; they are not
operation-only peak allocations. R vector-heap deltas exclude node headers
and native allocations. Raw [baseline](results-2026-09-06-stage1/baseline-final/retained-and-peak.log)
and [candidate](results-2026-09-06-stage1/final/retained-and-peak.log) logs preserve
the separate measures.

The [interim scanner report](results-2026-09-06-scanner-prototype.md) records the
superseded native-scanner source `95685536`, its complete comparisons and checks.
Those measurements are not attributed to the final R-only revision. The original
2026-09-05 historical report and source revision labels remain unchanged.

## Recorded ownership prerequisites

The unchanged reference mutation runner fails on starting main and final
source `be9eac34` at its first sparse-write allocation assertion. Every call allocates
5,000,048 bytes through `.deep_copy_value()` / `.mutation_copy()` /
`.mutate_data()` / `replace_values()`. The gate requires less than one compact
column even on the first write to an unprepared data frame. A
[minimized reproducer](diagnose-reference-sharing.R) confirms the failure.
It is not a passing gate, and its later assertions were not reached.

A separate [alias-escape reproduction](diagnose-mutation-alias-escape.R) fails
identically on starting main and the revised R-only installation. A fresh private
column is exported inside the replacement expression after the early sharing
check; both the supplied table and that alias change. Ordinary public preflight
currently masks this case by creating conservative references. Moving the entry
check earlier without solving expression-created aliases would expose it.

Both findings remain required ownership prerequisites before the next native
change and before epic completion. The original runner, sharing guard, rollback
checks and container coverage remain unchanged. See the
[plan](../../docs/plans/dibble-result-performance.md#recorded-prerequisite-for-native-changes)
for the required dependency repair and the independent applicability review.

## Reproduction

Use the isolated export/install procedure in [README](README.md), substituting
the recorded source SHAs. Run from the repository root:

```sh
Rscript --vanilla benchmarks/r-dibble-dplyr/run.R LIBRARY OUTPUT SOURCE_SHA 7
Rscript --vanilla benchmarks/r-dibble-dplyr/columns.R LIBRARY OUTPUT SOURCE_SHA
Rscript --vanilla benchmarks/r-dibble-dplyr/repeat-pipelines.R LIBRARY
/usr/bin/time -l Rscript --vanilla benchmarks/r-dibble-dplyr/retained-and-peak.R LIBRARY string
Rscript --vanilla benchmarks/r-dibble-dplyr/diagnose-reference-sharing.R LIBRARY
Rscript --vanilla benchmarks/r-dibble-dplyr/diagnose-mutation-alias-escape.R LIBRARY
```

The last two diagnostics intentionally reproduce the recorded baseline blockers.
The full unchanged reference runner can be invoked against an already exact-built
installation with `DTATOOLS_BENCHMARK_CHILD=1` and
`DTATOOLS_BENCHMARK_LIBRARY=LIBRARY`, or from a clean checkout using its normal
`Rscript --vanilla benchmarks/r-reference-mutation/run.R` entry point, which
builds that checkout. Its final-build failure is preserved in
[this log](results-2026-09-06-stage1/final/reference-mutation.log); later assertions
were not reached. The original runner must pass before the next native change.
