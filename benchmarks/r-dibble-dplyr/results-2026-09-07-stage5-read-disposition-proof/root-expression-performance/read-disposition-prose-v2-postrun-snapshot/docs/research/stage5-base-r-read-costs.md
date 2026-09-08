# Stage 5 base R read costs and implementation options

Twelve base R read costs remain reproducible on the Stage 5 package source
`a2d8b6a5a00d75cf20c962d3f28cf959ed4192b9`, package tree
`b08c77d91bdce67032f13aced90c29d068d6e95a`, compared with the original ordinary
baseline `ec10a6ac34602f3bd691e8043019c1b479babda4`. They remain residual costs
for final integrated assessment. The controls below narrow their investigation;
they neither waive the costs nor establish that they cannot be reduced.
The three separate delegated-filter flags still require Stage 6 fixes and fresh
paired qualification. Stage 5's direct-expression gains do not close those flags.

The [read diagnosis archive](../../benchmarks/r-dibble-dplyr/results-2026-09-07-stage5-measurements/read-diagnosis/README.md)
and its [selection](../../benchmarks/r-dibble-dplyr/results-2026-09-07-stage5-measurements/read-diagnosis/selection.json)
identify exact drivers, completed receipts, raw samples, input bindings and both
independent reviews. Nonplain output paths in the selection are bundle members,
not separate repository files. All measurements use stock host R 4.6.1 on the
same machine, sequentially during coordinated quiet windows. They do not qualify
performance on the clean R 4.6.0 installation.

## Repeated costs

Three fresh paired repeats preserve the original twelve cases and their
100,000/1,000,000-row fixtures. Each operation reads one column of an eight-column
table. All twelve million-row cases exceed the unchanged diagnosis threshold
of both 10% and 1 ms in every pair. None of their 100,000-row cases crosses both
thresholds. One-column million-row fixtures also preserve all twelve flags.
This is a structural minimization, not a measured minimum row-count threshold.

| Kind | Operation | Three-pair delta range, ms | One-column delta, ms |
| --- | --- | ---: | ---: |
| Declared character | `anyNA` | 2.335–2.345 | 2.343 |
| Declared character | `sum(!is.na(...))` | 2.352–2.387 | 2.380 |
| Logical | `sum(!is.na(...))` | 2.185–2.197 | 2.395 |
| Logical | `as.character` | 2.005–2.227 | 2.258 |
| Logical | `as.integer` | 2.170–2.270 | 2.260 |
| Logical | `mean(..., na.rm = TRUE)` | 2.005–2.412 | 2.012 |
| Factor | `anyNA` | 2.180–2.197 | 2.196 |
| Factor | `sum(!is.na(...))` | 2.156–2.191 | 2.409 |
| Factor | `as.character` | 2.110–2.344 | 2.201 |
| Ordered factor | `anyNA` | 2.186–2.196 | 2.189 |
| Ordered factor | `sum(!is.na(...))` | 1.970–2.195 | 2.363 |
| Ordered factor | `as.character` | 2.147–2.190 | 2.306 |

Times are rounded here; the archive preserves full precision. Declared character
has no NA. Logical/factor/ordered fixtures contain 25% NA. Source values,
metadata, backing identities and the original post-read rename budgets pass.
The earlier narrowed driver omitted the original independent tiny rename
warm-up and failed that allocation gate. Cold/warm controls reproduced the
setup difference; v2 restores the warm-up without changing the gate. All failed
drivers, outputs and incomplete coverage records remain preserved.

The separate Arrow write flag and safe-reference pipeline flag did not recur in
three paired repeats each. Their original flagged observations remain retained.
They are separate from the twelve persistent read costs.

## What the native controls establish

For declared-character `anyNA`, three paired one-column runs compare the public
table expression, the same operation on a pre-extracted column, a native public
`STRING_ELT` scan, and one rooted public `DATAPTR_RO` scan. At one million rows,
pre-extraction retains a 2.338–2.344 ms increment. The matched pointer scans are
about 0.22 ms on both sources, with paired deltas from -0.001722 to +0.001886 ms.
Table lookup therefore does not explain the measured increment in this case.

Logical, factor and ordered nonmissing-count controls repeat the same four-way
comparison on the original 25%-NA fixtures. The exact public expression remains
`sum(!is.na(...))`, with an independent ordinary value and integer-type oracle.
Across three pairs, million-row public-table deltas are 1.971–2.408 ms;
pre-extracted deltas are 1.975–2.199 ms. The matched native pointer scans take
about 0.042 ms on both sources, with deltas from -0.000410 to +0.001435 ms.
Both public and native controls preserve source values, attributes and backings.

These results support combined per-element access costs in the four tested
operation/type pairs. They do not isolate an individual getter's latency.
Compiled native Elt loops have different absolute costs from the public R
operations, and pointer loops permit different compiler optimizations. Their
separate untimed visit records count only the diagnostic loops. No instrument
counted base R's element visits. The other eight flagged operation/type pairs
were repeated and structurally minimized, but were not independently decomposed
by these controls.

Allocation remains a separate measurement. The count controls record `8N + 96`
R bytes for the public expression and zero recorded R bytes for their native
controls; the latter still return an R scalar. Native scans avoid the public
expression's intermediate logical vectors, so they are not allocation-equivalent
replacements for the whole expression. All 36 recorded count-control GC events
remain in the raw samples because `filter_gc = FALSE`. R allocation totals,
live retained vector heap and process RSS are distinct; these controls do not
supply per-read retained-heap or RSS conclusions. Candidate factor/ordered
backings are already private at their initial checkpoint and stay unchanged;
that is not evidence that the controls made them private.

The initial character tiny check incorrectly expected raw NA to survive Stata
string construction. Independent ec10/a2 observations and the existing source
policy established NA-to-empty normalization with storage recomputation. The
corrected raw/stored oracles passed on both sources before fresh timings.
Neither the original failure nor its incomplete final coverage was relabeled.

## Source constraints and feasible next work

The prior source-reading preparation's 27 inputs still match their recorded
hashes. `owned-columns.h` and the original atomic helper/runner are byte-identical
between qualified Stage 4 source c8 and a2. Owned Elt getters already read a
cached address whose backing record roots the exact R allocation. Read-only
pointer, integer/logical region and relevant `No_NA` methods are registered.
Adding another cache or registering those methods again would not redirect the
base loops identified below.

The pinned [R 4.6.1 coercion and missingness source](https://svn.r-project.org/R/tags/R-4-6-1/src/main/coerce.c)
shows that bare character `anyNA` and default `is.na` use element getters.
Factor/ordered `anyNA` evaluates `any(is.na(x))`, so it first creates the full
missingness mask. The same source's factor-specific character conversion reads
integer codes directly and does not enter generic ALTREP coercion.
[Logical mean](https://svn.r-project.org/R/tags/R-4-6-1/src/library/base/R/mean.R)
first computes the missingness mask and subset; in this package that subset is
ordinary before the final mean loop. These are source-based explanations of
candidate paths, not additional measured decomposition results. The retained
source copies are primary reading references, not an attestation of the
installed Homebrew R binary's complete build inputs.

The [public ALTREP API](https://svn.r-project.org/R/tags/R-4-6-1/src/include/R_ext/Altrep.h)
has no missing-mask or Mean hook. Its existing `No_NA` and region methods cannot
make those getter-based base paths use a pointer. A new visible column class,
global base override, rewritten user expression or exposed ordinary backing
would change the required interface or isolation contract. A stock-R package
cannot claim the diagnostic pointer result merely by substituting one of those
changes. Upstream R could study pointer/region use in these loops; a patched R
experiment would remain separate from supported-runtime qualification.

A narrower public opportunity does exist: a method registered through
`R_set_altrep_Coerce_method` is invoked by `coerceVector` through `ALTREP_COERCE`
before the ordinary logical-to-integer or logical-to-character loops. It could target two of the twelve flags, while declining other inputs.
That establishes an entry point, not a proven equivalent implementation.
The generic success path copies attributes after the hook, while ordinary
coercion copies them before its loop. A proof must preserve public attribute
removal, names/dimensions, empty inputs, NA, arbitrary attribute/callback and
tracing behavior, and source/result isolation. No such hook was implemented or
qualified here. Generic Coerce does not cover factor-specific character
conversion, and it does not fix missingness.

A backing-access redesign is another unproved option, but the current getter
already uses a cached address. These controls neither identify removable work
inside that getter nor justify changing its rooting and detachment rules.
Any future targeted prototype needs its own exact source, semantic checks,
paired original-case timing, allocation/retained-memory and native isolation
qualification. The residual costs remain visible while the authorized direct
verb stages continue. No blanket performance acceptance or irreducibility claim
follows from this disposition.
