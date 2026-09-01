# Stata vector operations in R

dtatools treats Stata-backed vectors as R vectors with Stata storage, missing-code identity, ordering, and variable metadata. These rules apply to numeric storage, Stata dates and datetimes, and owned Stata strings.

## Missing identity and order

Stata numeric missing codes are distinct comparable values. System missing `.` equals only `.`, and each extended missing `.a` through `.z` equals only itself. Their ascending order is:

```text
finite values < . < .a < ... < .z
```

Relational operators, vctrs equality, grouping, deduplication, matching, joins, ordered identity, and dtatools set operations use this identity. Finite operands compare at a lossless common precision; comparison never casts a wide constant into narrower Stata storage. Constructors, casts, assignment, and recode replacement remain strict.

Stata missing codes remain missing to `is.na()` and `is_missing()`. Vctrs equality must encode them as distinct comparable keys, so `vctrs::vec_detect_missing()` and completeness operations treat them as present. Dplyr's `na_matches` setting does not change their identity. This deliberate split keeps Stata equality consistent across grouping and joins.

Noncanonical NaN payloads have no Stata identity. Comparison, ordering, matching, grouping, and set operations reject them and direct callers to `NA_real_` or `tagged_missing()`.

## Ordering

`order()` and `sort()` use the Stata total order for byte, int, long, float, double, date, and datetime vectors. Valid Stata missing codes are ordered values: `na.last` does not remove or relocate them. Decreasing order reverses the total order. Equal values retain the stability promised by the selected R sorting method.

Non-null `partial` is not supported yet. It errors until an efficient partial permutation can reorder values and observation-dependent metadata together. Unspecified order among rows tied on every explicit key remains the caller's responsibility.

Owned Stata strings use ordinary R character ordering. Empty string is Stata string missing and sorts before nonempty strings. Exact Stata string collation is a separate compatibility question.

## Matching and sets

Base R and vctrs operations use Stata identity wherever their class dispatch exposes both operands. `unique()`, `duplicated()`, `anyDuplicated()`, vctrs grouping, `distinct()`, and dplyr joins distinguish all 27 Stata missing codes.

Base `%in%` and `match()` cannot transform a bare tagged-missing operand into the identity representation of a Stata-backed operand. Use the package-owned operations when either side may be a bare result of `tagged_missing()`:

```r
dta_match(x, table, nomatch = NA_integer_, incomparables = NULL)
dta_in(x, table)
```

`dta_match()` applies Stata identity to `incomparables`, so `.`, `.a`, and other missing codes can be excluded separately. `dta_in()` always returns a nonmissing logical vector. Both preserve the names of `x`.

Use `dta_identical()` for an order-sensitive value comparison:

```r
dta_identical(x, y)
```

It returns one nonmissing logical value and never recycles. The vectors must have equal lengths and compatible kinds. Numeric storage widths, compact representation, classes, names, labels, formats, and other metadata do not affect the result. Bare and Stata-backed numeric vectors can therefore be identical. Strings compare by exact character identity, including `""` as Stata string missing. Dates compare only with dates, and datetimes only with datetimes. Incompatible kinds return `FALSE`.

`dta_identical(NULL, NULL)` is `TRUE`; pairing `NULL` with any vector, including a zero-length vector, is `FALSE`. As with matching and set operations, a noncanonical NaN payload errors because it has no Stata identity. Base `identical()` remains unchanged and continues to compare R structure and attributes.

Base set operations do not expose enough class dispatch to preserve metadata symmetrically. Use:

```r
dta_union(x, y)
dta_intersect(x, y)
dta_setdiff(x, y)
dta_setequal(x, y)
```

Set operations preserve stable first-occurrence order and drop names. Union keeps unique values from `x`, then novel values from `y`, and uses a lossless common storage. Intersection and difference return first occurrences from `x` and retain `x`'s type and variable metadata. `NULL` follows base set-operation behavior. Incompatible operand kinds error instead of relying on base coercion.

## Stata strings

Every imported Stata string variable uses an owned vector class. Construct one explicitly with:

```r
stata_string(x, storage = NULL)
```

`storage` accepts `str1` through `str2045` or `strL`. When omitted, dtatools selects the smallest fixed storage from the maximum UTF-8 byte width and uses `strL` above 2,045 bytes. Owned Stata strings reject `NA_character_`; use `""` for Stata string missing.

Subsetting and reordering preserve the class and DTA metadata. `c()` and `vec_c()` widen string storage losslessly. Replacement keeps the target's declared storage and rejects values that are too wide. `as.character()` deliberately returns an ordinary character vector without DTA metadata.

## Metadata restoration

dtatools classifies every package-owned attribute before restoration. Variable-level DTA metadata includes numeric or string storage, display format, variable label, value labels and their table name, notes, characteristics, temporal kind, time zone, and owned classes. It survives subsetting and reordering unchanged unless an operation combines inputs and invokes reconciliation.

The initial registry has no package-owned observation-dependent DTA attributes. R names are handled separately: ordinary subsetting and sorting permute names, while set operations drop them. A future observation-dependent attribute must register its category and follow the retained source indices. Unknown attributes are dropped with one warning per operation rather than copied with unknown semantics.

Union and concatenation reconcile variable metadata left-first. They merge complete value-label tables, warn once when the same code has conflicting text, widen numeric or string storage losslessly, keep a compatible left display format when available, and fall back to the right format or a storage default. Intersection and difference retain the left operand's complete metadata, including unused value-label entries. Repeated indices and zero-row results keep the selected prototype and correctly sized observation metadata.
