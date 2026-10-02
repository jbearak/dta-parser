import csv,json
from pathlib import Path
r=Path('<compact-work>')
repo=Path('<repository>')
v=json.loads((r/'final-validation.json').read_text())
s=list(csv.DictReader((r/'acceptance/summary.csv').open()));p=list(csv.DictReader((r/'acceptance/parity.csv').open()))
def selected(case,op,kinds=None):
 fmt,kind,operation=case.split('-');return operation in op and (kinds is None or kind in kinds)
def extent(values,digits=3):return f'{min(values):.{digits}f}–{max(values):.{digits}f}'
def row(label,ops,kinds=None):
 a=[float(x['cpu_median'])/int(x['reps'])*1000 for x in s if x['representation']=='compact' and selected(x['case'],ops,kinds)]
 b=[float(x['cpu_median'])/int(x['reps'])*1000 for x in s if x['representation']=='plain' and selected(x['case'],ops,kinds)]
 c=[float(x['paired_ratio']) for x in p if x['metric']=='cpu' and selected(x['case'],ops,kinds)]
 return f'| {label} | {extent(a)} | {extent(b)} | {extent(c)}× |'
rows=[row('`is.na(x)`',{'is_na'}),row('`is_missing(x)`',{'is_missing'}),row('`is_missing(a, b, c, d)`',{'multi4'}),row('`sum(x, na.rm = TRUE)`, byte/int/long',{'sum'},{'byte','int','long'}),row('`sum(x, na.rm = TRUE)`, float',{'sum'},{'float'}),row('`min` / `max`, `na.rm = TRUE`',{'min','max'})]
report=f'''# Compact kernels, 2026-10-02

The new compact missing-mask and sum kernels meet the predeclared target of at most 1.25× ordinary-double CPU in all 42 measured cases. Six fresh-process rounds produced 504 observations across DTA and retained Arrow columns. The largest median paired CPU ratio is 1.019×, with a 95% bootstrap upper bound of 1.029×. The largest elapsed-time upper bound is 1.031×.

Compact `is.na()` is faster than ordinary doubles for every tested storage type. Integer sums are within about 2%; float sums are faster. The unchanged min/max paths were already faster and remain so. These measurements show that compact storage does not impose a universal scalar-access penalty on operations the package controls.

## Public operation results

CPU milliseconds per call on one million rows, with ranges across byte, int, long and float storage and both file formats. The four-input predicate processes four million input values. Ratios are medians of within-round compact/double ratios, so they need not equal ratios of the separately reported medians.

| Public operation | Compact ms | Ordinary-double ms | Paired CPU ratio |
| --- | ---: | ---: | ---: |
{chr(10).join(rows)}

`is_missing()` compares dtatools' public function on both representations. Its ordinary-double path is slower than base `is.na()`; the first row is the standard missing-predicate comparison. Reduction timings use `na.rm = TRUE` and include public class dispatch and typed result construction. No min/max optimization is claimed in this change.

Public Stata result-storage behavior is preserved. In particular, a `dta_float` sum rounds its scalar result back to float precision. On this fixture the native sum is 62438580647, while the public typed result is 62438580224, both before and after the change. The worker separately verifies native reduction equality against ordinary doubles, then verifies the public result under the existing storage policy. This distinction is part of qualification, outside timing.

## Implementation

The former public compact `is.na()` path fell through to R's generic ALTREP scalar traversal. The replacement admits known compact storage through the existing guarded mask producer. It selects type and legacy/modern format once per contiguous span, then compares raw storage codes without constructing doubles. The same kernel writes fresh masks or ORs into `is_missing()`'s accumulated mask. Temporal missing predicates use it too.

Interrupt checks occur between bounded blocks, outside the inner loops. Compiler inspection using the accepted build's original optimization flags confirms all sixteen mask variants vectorize: sixteen byte lanes, eight int lanes, or four long/float lanes. Retained Arrow owners are captured before allocation, and the descriptor is derived from the private retained owner. That avoids dangling owner pointers if a callback materializes the public source. Names, foreign-source fallback and argument-level short circuits retain their existing behavior.

Sums use contiguous typed loads, select temporal conversion and missing policy before scanning, and keep one ordered accumulator across every block and Arrow chunk. Ordinary observed floats take one comparison before accumulation; large positive values and exceptional encodings retain the full missing-code and NaN predicate. No fast-math flags or reassociated partial sums were introduced. Compiler diagnostics and cancellation tests confirm the intended ordered path.

The original minimal missing-mask reproduction moved from RED at 39.62× ordinary-double CPU to GREEN at 0.25×. That short diagnostic uses four rounds of 32 scans; the table above uses the independent, longer confirmation. The earlier two-round screen is retained as diagnostic evidence. Its reductions used stripped native views and must not be presented as a public-reduction before/after comparison.

## Protocol and limits

Each confirmation process loads the DTA and verified Arrow fixtures and the independent ordinary RDS reference, then measures one case on compact and ordinary doubles in alternating order. A timed interval contains 256 calls and retains only the final result. Explicit GC, input reads, reference traversal and qualification are outside timing. Automatic GC, R wrappers and result allocations remain inside. User and system CPU come from the same interval; wall time is recorded separately.

The worker checks complete predicate outputs, full same-order scalar checksums and missing counts, selected exact values and tags, and unmaterialized input state before and after timing. Native reductions are checked exactly against the reference outside timing. All source, installed-library, runtime, probe and input bindings match before and after. The tested production package matches all 449 source files in the accepted build.

These are repeated warm-data scans on one host, using R 4.6.1 and Apple clang 21.0.0. Inputs have sparse missingness and ordinary observed values. Results do not establish parity for every length, distribution, operation or machine. Bootstrap intervals use six paired rounds and are unadjusted across comparisons. Builds, tests and profiling did not overlap timing; unrelated desktop activity was not hardware-isolated.

This change targets column consumption. It does not claim a new parser/read-time improvement. Generic consumers such as `is.na(as.double(x))`, after removing the class that selects the package method, still use R's scalar fallback. `anyNA()`, missing-tag extraction and other unrelated operations were not given new kernels here.

## Validation and evidence

The accepted installed package passes the full R suite: {v['full_r_suite']['passed']:,} assertions, zero failures, errors or skips, and {v['full_r_suite']['warning']} warnings matching the preceding accepted build by test and count. Focused checks add exact-byte coverage for legacy formats, all missing tags, both IEEE NaN signs, infinities, signed zero, temporal conversions, callback/GC behavior and retained chunks. Twenty additional cancellation cases cross the new 65,536-row block boundary with plain and retained inputs. The original parity reproduction and `git diff --check` pass.

Rust sources are unchanged by this step; their earlier 41-test/Clippy/format validation is recorded in the [scalar follow-up](results-2026-10-02-scalar.md). `R CMD check` and the full cross-language conformance matrix were not rerun.

The [raw observations](results-2026-10-02-compact-kernels/acceptance/raw.csv), [paired ratios and intervals](results-2026-10-02-compact-kernels/acceptance/parity.csv), [protocol](results-2026-10-02-compact-kernels/acceptance/protocol.json), [incremental patch](results-2026-10-02-compact-kernels/patches/accepted-incremental.patch), [accepted build receipt](results-2026-10-02-compact-kernels/builds/accepted/build-receipt.json), [compiler evidence](results-2026-10-02-compact-kernels/compiler/summary.json) and [validation record](results-2026-10-02-compact-kernels/validation/final-validation.json) preserve the result's scope and source bindings.

[Reproduction instructions](results-2026-10-02-compact-kernels/controllers/README.md) explain the workers, source-bound builds and probe. Private path transformations are listed in the [source map](results-2026-10-02-compact-kernels/publication-source-map.json), with published hashes in the [manifest](results-2026-10-02-compact-kernels/publication-manifest.json). Input binaries and installed libraries are not published.
'''
(repo/'benchmarks/reader-cpu-scaling/results-2026-10-02-compact-kernels.md').write_text(report)
