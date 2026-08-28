# R joins with Stata columns

This note examines `base::merge()` and dplyr joins whose `by` argument is built
with `join_by()`. `join_by()` only describes the match; `left_join()`,
`full_join()`, and the other join verbs do the work.

The short answer is that dplyr preserves the most column information. The
dtaparser 0.6.0 development tree now also supports native keys in base right
and full merges. Dplyr uses vctrs, so dtaparser's proxy, common-type, cast, and
restore methods participate. That support does not make either join
Stata-equivalent. Equality joins treat every Stata missing code as the same R
missing value.

## What the columns contain

`read_dta()` returns a tibble. Numeric columns retain their declared Stata
storage type, value and variable labels, display format, and system or extended
missing values. Source byte, int, long, and float columns can remain compact
ALTREP vectors until an operation needs ordinary R doubles. Stata `.` becomes
`NA_real_`; `.a` through `.z` become tagged NA payloads. These facts are part of
dtaparser's [`read_dta()` contract](../r-package/dtaparser/R/read-dta.R) and
agree with Haven's documented representation of [Stata data and variable
labels](https://haven.tidyverse.org/reference/read_dta.html) and [tagged missing
values](https://haven.tidyverse.org/reference/tagged_na.html).

That leaves four separate concerns for a join:

- whether the key can be compared;
- which missing keys match;
- what happens when the two key columns have different classes or metadata;
- whether row slicing and output construction retain compact storage and
  attributes.

## Base `merge()`

### Right and full native-key merges require extension-aware assignment

`merge.data.frame()` extracts a one-column key, passes it through `match()`, and
optionally sorts the result. For multiple keys it first pastes the key columns
into strings. The implementation is visible in R's
[`merge.R`](https://github.com/wch/r-source/blob/trunk/src/library/base/R/merge.R),
and the public contract is in the [`merge` manual](https://stat.ethz.ch/R-manual/R-devel/library/base/html/merge.html).

Before the 0.6.0 fix, a single native Stata key worked for inner and left
merges. A right or full merge failed if it had to add a key found only in `y`.
After matching, `merge.data.frame()` starts with the selected `x` keys and
fills right-only positions using subassignment. Dtaparser's strict
`[<-.stata_numeric` method rejects assignment past the current vector length.
For example, merging byte keys `c(1, 2)` and `c(2, 3)` with `all.y = TRUE`
errors because the result needs another key slot. `all = TRUE` fails for the
same reason. This happens even when both keys declare the same Stata storage
type.

The fix makes extension with another declared Stata numeric use the existing
vctrs common-type rules. It promotes storage when needed, combines compatible
value labels, restores compact backing, and leaves ordinary replacement strict.
This is a deep vector seam: the same implementation fixes `rbind()` and
`merge()` without a join wrapper. Regression coverage lives in
[`test-stata-numeric.R`](../r-package/dtaparser/tests/testthat/test-stata-numeric.R).

Base merge still has an information limit. When no right-only key requires
extension, `merge.data.frame()` keeps the selected `x` key and never combines
it with the `y` key. Value labels or other attributes present only on `y` are
therefore unavailable to the column methods. Base merge has no column-level
dispatch point where dtaparser can reconcile them.

### Columns keep metadata in common cases, but the data frame does not

When the key is an ordinary R vector, `merge()` subsets and combines the input
data frames. S3 subsetting keeps the attributes on non-key Stata columns in the
cases checked here, including `label`, `labels`, `format.stata`, class, and
declared storage. In the 0.6.0 checks, result columns were compact ALTREP
vectors and source columns remained unmaterialized. This follows dtaparser's
current subsetting methods, not a guarantee made by `merge.data.frame()`. Test
it at the package boundary if memory use matters.

Dataset-level metadata is shakier. Base `merge()` constructs a new data frame
with `cbind()` and finally resets row names; it does not promise to preserve
arbitrary attributes from `x`. The base manual promises a data frame, not an
object of the same type as `x`.

### Missing keys follow R, not Stata

By default, base `merge()` matches `NA` to `NA`. `incomparables = NA` disables
that for a single key, as the [base manual](https://stat.ethz.ch/R-manual/R-devel/library/base/html/merge.html)
documents. R's `match()` regards tagged NAs as missing values rather than as
27 Stata codes. Native keys containing `.`, `.a`, and `.z` can therefore match
one another and create an accidental
many-to-many expansion.

This differs from the source semantics dtaparser preserves. Stata defines
distinct numeric missings ordered `. < .a < .b < ... < .z`, as StataCorp's
[missing-value FAQ](https://www.stata.com/support/faqs/data-management/replacing-missing-values/)
states. A join intended to reproduce Stata key identity must encode the missing
tag into an ordinary nonmissing surrogate key before calling `merge()`.

## Dplyr joins and `join_by()`

### Equality, inequality, rolling, and overlap joins are available

`join_by()` accepts equality and inequality conditions plus rolling and overlap
helpers. It does not allow an arbitrary computed expression, so derived keys
must be created before the join. The official [`join_by()`
reference](https://dplyr.tidyverse.org/reference/join_by.html) gives the full
grammar.

Dplyr's data-frame joins use vctrs for comparison, slicing, common types, and
restoration. The [mutating-join contract](https://dplyr.tidyverse.org/reference/mutate-joins.html)
says that equality keys are coalesced by default, `keep = TRUE` retains both,
and a coalesced key is cast to the common type. It also documents output row
order, suffixes, `multiple`, `unmatched`, and `relationship` checks.

This fits dtaparser much better than base `merge()`. Current dtaparser defines
`vec_proxy()`, `vec_restore()`, `vec_ptype2()`, and `vec_cast()` methods for
Stata numerics and Stata temporal vectors in
[`stata-numeric.R`](../r-package/dtaparser/R/stata-numeric.R). Vctrs applies
operations to a proxy and restores the original representation afterward, as
its [proxy and restore documentation](https://vctrs.r-lib.org/reference/vec_proxy.html)
describes.

### Coalescing invokes dtaparser's metadata policy

When both equality keys are native dtaparser columns and `keep` is false, the
common-type methods choose a lossless Stata storage type, preserve the left
variable label unless it is absent, and combine compatible value-label tables.
Conflicting text for one value warns and the left label wins. Restoration
re-encodes compact byte, int, long, or float storage. These rules are explicit
in dtaparser's [`vec_ptype2.stata_numeric.stata_numeric()` and restoration
code](../r-package/dtaparser/R/stata-numeric.R).

`keep = TRUE` avoids coalescing the keys. Each side then retains its own key
column and metadata, with suffixes where names collide. This is the safer form
when variable labels, display formats, or value-label tables differ and the
caller wants to inspect both definitions.

Plain Haven vectors have a narrower policy. Haven's
[`vec_ptype2.haven_labelled.haven_labelled()`](https://github.com/tidyverse/haven/blob/main/R/labelled.R)
combines value labels and takes the first available variable label, but creates
a new labelled prototype. Attributes outside that constructor's contract, such
as `format.stata` or custom attributes, are not promised on a coalesced key.
Native dtaparser classes should dispatch dtaparser's earlier class method and
retain the package's broader metadata contract. A vector reduced to plain
`haven_labelled` gets Haven's behavior instead.

### All Stata missing codes match each other by default

Dplyr defaults to `na_matches = "na"`, which treats missing keys as equal.
`na_matches = "never"` prevents any missing-key match. Those two choices are
documented in the [mutating-join reference](https://dplyr.tidyverse.org/reference/mutate-joins.html).
Neither choice distinguishes `.`, `.a`, and `.z`.

A direct check with tagged NAs confirms the consequence: three left keys
containing `.a`, `.b`, and `.` joined to the same three right keys produce nine
matches under `na_matches = "na"`, and zero under `"never"`. This happens
because dtaparser's equality proxy is the underlying R double vector and all
tagged payloads enter dplyr's missing bucket.

For Stata-faithful equality, precompute a surrogate key with two components:
the observed numeric value and the missing tag. A character encoding also
works if it assigns separate tokens to `.`, `.a`, through `.z` and cannot
collide with observed values. Keep the original Stata column out of the match
or retain both keys with `keep = TRUE`.

An automatic equality proxy was prototyped and rejected. A two-field proxy can
distinguish every missing code and also reproduce Stata's missing-value order.
Vctrs uses that same proxy for `vec_detect_missing()`, however. Encoding the
tags as comparable values makes vctrs report them as nonmissing, changes
`na_matches = "never"`, and affects missing-data operations outside joins.
That would violate the existing R-facing contract in order to improve one
consumer. There is no separate dplyr join-comparison seam to use instead.

### Relationship checks matter more with Stata missings

Dplyr warns about unexpected many-to-many equality joins and can enforce
`"one-to-one"`, `"one-to-many"`, or `"many-to-one"` through `relationship`.
It can also error on unmatched keys with `unmatched`. These checks are worth
setting explicitly. A column containing several different Stata missing codes
can otherwise become a many-to-many block solely because R considers all of
them missing.

Inequality joins need a separate decision. Stata orders its missing codes above
observed numbers, but R comparisons involving any NA return NA. A dplyr
inequality or rolling join therefore does not reproduce Stata's numeric order
for `.`, `.a`, through `.z`. Encode that order into a nonmissing surrogate
before using `<`, `>=`, `closest()`, or an overlap helper.

## Practical recommendation

When Stata key identity matters, use dtaparser's own `stata_merge()`. It
matches `.` and each of `.a` through `.z` only to themselves, requires a
declared merge relationship, generates Stata's `_merge` indicator, and
reconciles key storage and metadata through the package's vctrs methods.
ADR 0009 records its semantics and the rejected alternatives, including the
equality-proxy change discussed below.

For R-semantics joins, use dplyr joins for data frames containing native
dtaparser columns, and name the intended key relationship. Use `keep = TRUE` when the two key columns have
metadata worth comparing. Before any join in which Stata missing codes are
valid keys, create an explicit surrogate that preserves the tag. Do the same
for inequality joins that are supposed to use Stata's missing-value ordering.

Base right and full merges now accept native Stata keys. They preserve and
promote metadata when right-only keys exercise the extension path, but cannot
reconcile right-key metadata in every merge shape. Verify dataset-level
metadata after a base merge because base returns a new data frame and does not
promise arbitrary attributes.

For either join system, construct ordinary surrogate keys when Stata missing
codes are valid keys. With base merge, `incomparables = NA` is available only
for a single key and means that no missing key should match.

## Versioned check

The local behavior checks used R 4.6.1, dplyr 1.2.1, vctrs 0.7.3, Haven 2.5.5,
and a fresh local installation of the dtaparser 0.6.0 workspace tree on
2026-08-28. The durable claims above come from the linked public contracts and
source. The former base error text, ALTREP behavior, and shape of a
tagged-missing many-to-many result are versioned observations. Tests should pin
them at the package boundary rather than treat the messages as API.
