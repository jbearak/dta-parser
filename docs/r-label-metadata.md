# Label metadata in R

`dtaparser` owns the small label-metadata interface needed for Stata workflows. You do not need to install or attach `labelled` to inspect or change labels returned by `read_dta()`.

```r
library(dtaparser)
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
data <- set_variable_labels(
  data,
  status = "Interview status",
  .labels = list(stratum = "Sampling stratum")
)

data <- set_value_labels(
  data,
  status = c(Complete = 1, Refused = 2)
)

data$status <- set_value_labels(
  data$status,
  Complete = 1,
  Refused = 2
)
```

For data frames, `...` and `.labels` are combined into one atomic update. Every update must have a unique, known column name. Positional, duplicate, unknown, or overlapping updates are errors; no column is changed when validation fails. Replacement forms take a named list, while a bare `NULL` clears the corresponding metadata from every column.

## Stata-native behavior

Variable and dataset labels accept one string. `NULL`, `NA_character_`, and `""` all remove the attribute. Value-label tables are named numeric vectors in which names are the displayed text and values are Stata codes. Empty or missing displayed text is discarded, duplicate displayed text is allowed, and duplicate codes are rejected.

Value-label codes are limited to values that Stata can use in a label definition:

- whole, nonmissing values from -2,147,483,647 through 2,147,483,620;
- extended missings `.a` through `.z`.

System missing `.`, ordinary R `NA` and `NaN`, fractions, and infinities are rejected. `haven` remains useful, but optional, for creating or inspecting tagged missings and for `haven::as_factor()`.

The helpers target the documented Stata 19 metadata limits:

| Metadata | Documented limit |
| --- | ---: |
| Dataset label | 80 Unicode characters |
| Variable label | 80 Unicode characters |
| Entries in one value-label table | 65,536 |
| Text for one value-label entry | 32,000 Unicode characters |

An over-limit value is stored unchanged in R. A call emits one standard, suppressible warning that summarizes every affected column and limit. Export behavior depends on the writer and may fail, truncate metadata, or create a file outside Stata's documented limits. A future dtaparser writer will support only Stata 18/19 and will not silently emit metadata outside those limits; see [issue #57](https://github.com/jbearak/dta-parser/issues/57).

## Classes, attributes, and compact columns

Adding value labels to an ordinary numeric vector gives it the dependency-free classes `haven_labelled`, `vctrs_vctr`, and its R storage type. This preserves call compatibility with software that understands haven-labelled vectors without importing `labelled`.

The setters change only the requested metadata and compatibility class. They retain Stata display formats, variable labels, time zones, temporal and unrelated classes, and custom attributes. Removing every value label removes the compatibility class while retaining unrelated classes. For numeric columns read by dtaparser, setting labels also preserves an ALTREP-backed compact result instead of immediately allocating a decoded double vector.

These guarantees are covered at the exported helper seam in [`test-label-metadata.R`](../r-package/dtaparser/tests/testthat/test-label-metadata.R).

## Compared with `labelled`

The variable- and value-label names above intentionally match common `labelled` calls; `dataset_label()` is a dtaparser addition. dtaparser promises call compatibility only for the documented surface. It does not implement `prefixed`, `null_action`, `.strict`, `.overwrite`, recursive/survey-object behavior, or the rest of the `labelled` package.

The comparison below is specific to `labelled` 2.16.0 and `haven` 2.5.5. It is not a claim about future releases.

| Scenario on dtaparser data | `dtaparser` helpers | `labelled` 2.16.0 |
| --- | --- | --- |
| Read variable/value labels | Reads the native attributes | Reads the same attributes |
| Set a variable label on numeric ALTREP | Keeps an ALTREP result | Materializes the vector |
| Set value labels on numeric ALTREP | Keeps an ALTREP result and preserves `format.stata` and custom attributes | Materializes the vector and drops `format.stata` and custom attributes |
| Set value labels on `Date` or `POSIXct` | Preserves temporal classes and time zone | Reconstructs a plain haven-labelled numeric vector |
| Remove all value labels | Removes compatibility classes added to ordinary numeric vectors while retaining unrelated classes | Reconstructs a standard haven-labelled numeric vector as an unclassed numeric vector |
| Validate labels | Enforces Stata-native codes and atomic named data-frame updates | Implements the broader `labelled` contract, including behaviors dtaparser deliberately omits |

The version-pinned comparison and both package attach orders run in [`test-labelled-interop.R`](../scripts/test-labelled-interop.R). CI installs `labelled` only for that repository-level gate; it is not a dtaparser runtime, suggested, or enhanced dependency.

If `labelled` is attached first and `dtaparser` second, unqualified common helper names resolve to dtaparser. If `labelled` is attached after dtaparser, normal R masking makes them resolve to `labelled`; dtaparser emits one scoped warning. Qualified calls such as `dtaparser::set_value_labels()` always select this implementation.
