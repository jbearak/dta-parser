# dtaparser's labelled columns are a class, so their labels survive dplyr

ADR 0017 and plan 0013 kept dtaparser's columns unclassed: tagged NAs
in plain doubles, value labels in a `labels` attribute. That assumed
attributes travel with a column. They do through base R's `[`, but
vctrs, which dplyr and tidyr combine columns with, drops attributes it
does not know: `bind_rows()`, `case_when()` and `if_else()` each return
a plain `labels` column without its labels. A factor survives the same
calls because its class tells vctrs how to combine it, but cannot hold
`.a` to `.z`.

So plan 0016 makes a column with value labels a `dtaparser_labelled`,
a vctrs class around the same codes and attributes, in 2.0.0, which
already breaks 1.x code (ADR 0026). `with_labels()` makes one. The
choices that shape it:

- **Missing values are R's.** Every missing value is `NA` to
  `is.na()`, comparisons and arithmetic, and `as.character()` gives
  `NA` for each, so no missing reason becomes a level of `factor()` or
  `table()`, or enters a survey share. `val_label()` gives the reasons.
- **Equality uses the codes alone.** A proxy that kept the letter
  would keep `.r` and `.d` apart in `unique()` and `group_by()`, but
  vctrs calls a value missing only when every proxy field is, so
  `is.na()` and `coalesce()` would miss tagged values. Grouping by
  reason goes through `val_label()` instead.
- **Combining is strict on conflicts.** Labels are the union of the
  inputs'; a code with two texts is an error, since one of them is
  wrong for some rows. The variable label is the first one found.
- **Computed numbers have no label.** Arithmetic, math and summaries
  return plain numbers.

## Considered options

- **haven's `haven_labelled`.** It does this, but brings haven, which
  dtaparser has kept to Suggests, and shares a class name whose methods
  dtaparser does not control.
- **Keep attributes and document the loss.** Every dplyr pipeline would
  have to reattach labels, and a missed one fails silently.
- **Only a constructor; readers unchanged.** Code that pools raw
  columns would still lose labels by default.

## Consequences

- Code that checks `is.object()`, `class()` or `identical()` against a
  plain vector sees the class; `is.numeric()` and `is.double()` do not
  change. `as.numeric(x)` gives the plain codes.
- `as.character(x)` gives labels where it gave numbers.
- Pooling files whose labels spell a code differently is an error until
  one is relabelled with `with_labels()`.
- The survey package treats the column as a number; shares need
  `factor(x)`.
