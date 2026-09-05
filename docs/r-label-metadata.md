# Label metadata in R

`dtatools` owns the small label-metadata interface needed for Stata workflows. You do not need to install or attach `labelled` to inspect or change labels returned by `read_dta()`.

```r
library(dtatools)
data <- data.frame(
  status = c(1, 2, 1),
  stratum = c(1, 1, 2)
)

var_label(data$status)
var_label(data$status) <- "Interview status"

val_labels(data$status)
val_labels(data$status) <- c(Complete = 1, Refused = 2)

dataset_label(data)
dataset_label(data) <- "Baseline survey"
```

The pipeline forms work on vectors and data frames:

```r
data <- set_var_labels(
  data,
  status = "Interview status",
  .labels = list(stratum = "Sampling stratum")
)

data <- set_val_labels(
  data,
  status = c(Complete = 1, Refused = 2)
)

data$status <- set_val_labels(
  data$status,
  Complete = 1,
  Refused = 2
)
```

The three `set_*()` functions mutate a data frame and every binding to it by
reference. Call `copy_data()` first when another binding must remain unchanged.
Replacement syntax follows R's assignment rules for the metadata it changes:
it updates the binding on the left, while another binding keeps its original
metadata. Untouched column payloads are not deep-copied, so a later
`replace_values()` call can still be visible through both bindings. Use
`copy_data()` when later value mutations must also be isolated.

For data frames, `...` and `.labels` are combined into one atomic update. Every update must have a unique, known column name. Positional, duplicate, unknown, or overlapping updates are errors; no column is changed when validation fails. Replacement forms take a named list, while a bare `NULL` clears the corresponding metadata from every column.

## Stata-native behavior

Variable and dataset labels accept one string. `NULL`, `NA_character_`, and `""` all remove the attribute. Value-label tables are named numeric vectors in which names are the displayed text and values are Stata codes. Empty or missing displayed text is discarded, duplicate displayed text is allowed, and duplicate codes are rejected.

Value-label codes are limited to values that Stata can use in a label definition:

- whole, nonmissing values from -2,147,483,647 through 2,147,483,620;
- extended missings `.a` through `.z`.

System missing `.`, ordinary R `NA` and `NaN`, fractions, and infinities are rejected. Use `tagged_missing()`, `missing_tag()`, and `is_tagged_missing()` to create or inspect extended missing values without haven.

### Value labels and Stata table names

Four pieces of metadata matter here:

- A variable label is a human-readable description of the variable. R stores
  it in `attr(column, "label")`.
- A resolved value-label mapping assigns displayed text to the numeric codes of
  one variable. R stores it in `attr(column, "labels")`.
- A named Stata value-label definition is a dataset-level table containing one
  such mapping.
- A Stata assignment makes a variable refer to a named definition.

`dtatools` treats the resolved mapping on each variable as authoritative. It
does not maintain a live dataset-level registry in which several R columns
share one definition. Editing one column's `labels` attribute therefore does
not change any other column.

`read_dta()` and `read_arrow()` attach `value.label.name` when an imported
table name differs from the source variable name or when several source
variables share the table. A projected read still checks all source variables,
so it retains the table-name hint even if only one referring variable is
selected. The attribute is omitted for the ordinary one-variable case in which
the table and variable have the same name. `value.label.name` helps writers
reconstruct source-format metadata, but it is not shared semantic state and it
does not override the resolved `labels` mapping.

`save_dta()` and `save_arrow()` preserve the imported name. Columns with the
same name and the same mapping share one output table. Without the attribute,
each writer synthesizes a separate definition from the current variable name
and resolved mapping. Comparison covers codes, extended missing tags, label
text, duplicate imported entries, and source order. If columns claim one table
name but carry different mappings, the writer emits one warning for the whole
call and synthesizes independent variable-name definitions for the affected
columns. It never chooses one mapping merely because two name hints match.
Other unambiguous shared tables remain shared in the serialized file.

The attribute is valid only with a usable `labels` mapping. An empty named
mapping is usable and represents an empty Stata table; a table name without a
mapping is a write error. Removing all value labels with a dtatools setter also
removes `value.label.name`. Other metadata setters and supported reconstruction
operations retain it. The attribute is a serialization hint. `set_dta_metadata()` can author the
hint and mapping together, including an explicitly named zero-length mapping.
There is no shared table registry or registry editor.

### Compatibility with Stata merge

Stata resolves value labels through its dataset-level namespace. During a
merge, the master dataset's definition wins when the master and using datasets
contain different mappings under the same table name. A using-only variable
can then display the wrong text even though its values and labels were correct
before the merge.

For example, the Uzbekistan 2022 MICS birth-history data assign `bh4m` to a
table named `labels4` containing month labels. The women's data assign `wm11`
to a different `labels4` containing interview-privacy labels. With the women's
data as master, Stata retains the privacy definition and applies it to the
merged `bh4m`.

`dta_merge()` does not reproduce that namespace collision. It carries the
resolved month mapping with `bh4m` and the privacy mapping with `wm11`.
This is the expected result from the variable-level mapping: `bh4m` remains a
month variable after the merge. Stata's result can silently break a later
recode that relies on displayed label text. Exact Stata ports can therefore
differ when same-named definitions have different contents. Treat the Stata
result as a source-data bug unless the shared namespace was intentional. Rename
or reassign the definition in the Stata source before merging.

## Converting labels to factors

`factor_from_labels()` converts one numeric vector and its value-label table to
an ordinary factor. Its purpose is analysis after import: the factor is suitable
for models, plots, and data manipulation, but cannot be converted back to the
original numeric representation. The package therefore does not register an
`as.factor()` method or introduce a reversible labelled-factor class.

By default, missing values become factor `NA` and unused nonmissing value-label
entries remain levels. Labelled missing entries become levels only when
`missing = TRUE` or `"distinguish"`. In that mode, observed missing payloads
for `.`, extended missing codes, and R `NaN` get distinct levels. Labelled
extended-missing entries absent from the data remain as unused levels unless
`drop_unused = TRUE`. `display` selects labels, values, or both. Distinct codes
with the same label text remain distinct, qualified levels without a warning.
Double-backed `Date` and `POSIXct` vectors are supported; their Stata label
codes and displayed levels are translated to the R temporal representation.

Factor conversion and `tab()` share a native grouping path. Both preserve a
compact dtatools numeric source instead of allocating its decoded double
backing before grouping.

The helpers target the documented Stata 19 metadata limits:

| Metadata | Documented limit |
| --- | ---: |
| Dataset label | 80 Unicode characters |
| Variable label | 80 Unicode characters |
| Entries in one value-label table | 65,536 |
| Text for one value-label entry | 32,000 UTF-8 bytes |

An over-limit value is stored unchanged in R. A call emits one standard, suppressible warning that summarizes every affected column and limit. `save_dta()` supports Stata 18/19 and rejects metadata outside those limits instead of truncating it.

## Classes, attributes, and compact columns

Adding value labels to an ordinary numeric vector gives it the dependency-free classes `haven_labelled`, `vctrs_vctr`, and its R storage type. This preserves call compatibility with software that understands haven-labelled vectors without importing `labelled`.

The setters change only the requested metadata and compatibility class. They retain Stata display formats, variable labels, imported value-label table names, time zones, temporal and unrelated classes, and custom attributes. Removing every value label removes the compatibility class and `value.label.name` while retaining unrelated classes. For numeric columns read by dtatools, setting labels also preserves an ALTREP-backed compact result instead of immediately allocating a decoded double vector.

These guarantees are covered at the exported helper seam in [`test-label-metadata.R`](../r-package/dtatools/tests/testthat/test-label-metadata.R).

## Compared with `labelled`

The variable- and value-label getters and replacement functions intentionally
match common `labelled` calls. The shorter `set_var_label()`,
`set_var_labels()`, and `set_val_labels()` names are dtatools additions, as is
`dataset_label()`. dtatools promises call compatibility only for the documented
getter and replacement surface. It does not implement `prefixed`, `null_action`,
`.strict`, `.overwrite`, recursive/survey-object behavior, or the rest of the
`labelled` package.

The comparison below is specific to `labelled` 2.16.0 and `haven` 2.5.5. It is not a claim about future releases.

| Scenario on dtatools data | `dtatools` helpers | `labelled` 2.16.0 |
| --- | --- | --- |
| Read variable/value labels | Reads the native attributes | Reads the same attributes |
| Set a variable label on an unmaterialized dtatools numeric ALTREP | Keeps an unmaterialized compact result | Keeps an unmaterialized compact result |
| Set value labels on numeric ALTREP | Keeps an ALTREP result and preserves `format.stata` and custom attributes | Materializes the vector and drops `format.stata` and custom attributes |
| Set value labels on `Date` or `POSIXct` | Preserves temporal classes and time zone | Reconstructs a plain haven-labelled numeric vector |
| Remove all value labels | Removes compatibility classes added to ordinary numeric vectors while retaining unrelated classes | Reconstructs a standard haven-labelled numeric vector as an unclassed numeric vector |
| Validate labels | Enforces Stata-native codes and atomic named data-frame updates | Implements the broader `labelled` contract, including behaviors dtatools deliberately omits |

The version-pinned comparison and both package attach orders run in [`test-labelled-interop.R`](../scripts/test-labelled-interop.R). CI installs `labelled` only for that repository-level gate; it is not a dtatools runtime, suggested, or enhanced dependency.

If `labelled` is attached first and `dtatools` second, the four common getter
and replacement names resolve to dtatools. If `labelled` is attached after
dtatools, normal R masking makes those names resolve to `labelled`; dtatools
emits one scoped warning. The three `set_*()` names resolve to dtatools in
either attach order.

## Compared with `haven` helpers

The missing-code helpers and factor conversion intentionally use package-owned
names rather than masking haven. On the Haven 2.5.5 baseline, Haven accepts tag
payloads outside Stata's `.a` through `.z` domain, classifies some noncanonical
NaNs as tagged values, and materializes compact dtatools columns during tag
inspection and factor conversion. Its label-only factor display also merges
distinct numeric codes when their label text is identical.

dtatools validates the narrower Stata domain, preserves distinct factor
levels, and scans compact storage directly. Two-way missing-payload
interoperability and reader/writer comparisons run in a repository-only CI
suite. [`test-haven-helper-interop.R`](../scripts/test-haven-helper-interop.R)
retains the pinned 2.5.5 behavior comparison. dtatools does not suggest or
install Haven; users can install it separately to write older DTA releases or
read other statistical formats.

Use `set_dta_metadata(data, variable = my_name, labels = mapping,
value.label.name = table_name)` to restore a mapping and its serialization hint
atomically. This bundle preserves raw mappings, including empty display text and
named zero-length mappings, and applies DTA validation before mutation.
`set_val_labels()` retains its normalization of empty text. Runtime strings
work directly in `variable`. See the
[metadata migration examples](r-mutation-by-reference.md#explicit-metadata-migration)
for formats, notes, and characteristics.
