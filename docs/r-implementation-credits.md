# R implementation credits

The direct dibble selectors, grouping metadata and row/reconstruction hooks
adapt dplyr's selector, grouping and reconstruction rules. Character/factor
recoding kernels and their tests also adapt dplyr's legacy replacement rules.
Its implementation and tests are credited in the [installed source notice](../r-package/dtatools/inst/NOTICE),
which includes the upstream MIT copyright and license. The dtplyr implementation
and tests were studied for operation planning and copying behavior; no dtplyr
implementation is incorporated. The notice records the exact source revisions
and local adaptations. Plain data-frame row subsetting adapts base R rules
credited to the R Core Team and John Chambers. The same notice preserves the
upstream GPL version 2 or later license; this package uses GPL-3. R 4.6.1 native
attribute and resizing code was also studied for the append journal; that
implementation uses public APIs and incorporates no source from those files.
R's read, coercion and concatenation code informed owned read paths. Range
receives an independent ordinary snapshot, and integer/logical exports call
R's native coercion API. No R implementation or tests were copied for these
paths; the notice lists the studied files.
R's interrupt implementation was studied for portable native fault injection;
tests call its documented interrupt entry and retain transaction rollback checks.

R's ALTSTRING, subset and serialization code informed the extension to owned
ordinary strings, logicals and integer/factor backing. The same notice records
that study; no implementation from those files was copied. String width and
missingness facts belong to backing, while declarations remain column metadata.

The direct expression and grouping implementation also adapts dplyr 1.2.1 mask
and evaluation policies. The optional helper adapter uses the installed context
and across/pick expansion functions. See [NOTICE](../r-package/dtatools/inst/NOTICE) for exact source
and license records. dplyr 1.2.1 is the supported minimum on R 4.6.0 or newer;
[the compatibility study](https://github.com/jbearak/dta-parser/blob/main/docs/research/dplyr-r46-minimum.md)
records the source-build evidence and limits of the older-binary investigation.

The direct filter, arrange, distinct and slice family also adapts dplyr 1.2.1
row policies and tests. Shared evaluation and row gathering preserve Stata
columns and metadata. Ordering uses public vctrs ranks; explicit non-C locales use
stringi, and lifecycle supplies the upstream deprecation notifications. The
installed notice identifies the source functions, test adaptations and license.

Direct summary, reframe, callback and nesting methods also adapt dplyr 1.2.1
chunk-sizing, grouping and callback policies. They use the shared expression
mask, row gatherer and result finalizer; nested publication captures frame
storage while retaining ordinary nested classes and intentional reference
objects. Cyclic nested lists and data frames produce an explicit error before
vector assembly. The installed notice identifies the source functions and test policies.

Direct dibble joins adapt the pinned dplyr 1.2.1 key, naming, match-policy and
coalescing rules. Package-owned planning calls public vctrs matching, then
uses shared batched gathering and result finalization; nested outputs pass
through the same capture boundary. The [installed notice](../r-package/dtatools/inst/NOTICE) records
the exact source functions and license. Stata-specific `dta_merge()` matching
and output policy remain separate.

Base binding also adapts R 4.6.1's data-frame construction, row binding and
column binding, preserving its factor, recycling and naming rules. Its full
GPL notice and John Chambers/R Core attribution are in the installed notice.
Direct rows methods and column modification adapt pinned dplyr policies while
retaining public vector casting, matching and reconstruction extensions.
Package-specific result caches use actual object keys or prepared result slots;
atomic nested capture retains metadata-copy and opaque-reference behavior.

Grouped display and replacement fallbacks adapt dplyr 1.2.1 policies. Grouped
and rowwise vector restoration also adapts the conditional compatibility
methods in vctrs 0.7.3. These fallbacks support grouped objects when dplyr is
absent while retaining supplied grouping methods. Source details and both MIT
notices are preserved in [NOTICE](../r-package/dtatools/inst/NOTICE).
