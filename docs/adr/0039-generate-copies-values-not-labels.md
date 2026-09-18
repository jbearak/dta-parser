---
status: accepted
---

# `gen()` copies values, not labels

`gen()` and a new column through `:=` copy a value's values and typing and
nothing else. The new column takes the value's Stata storage, string
storage, and date or datetime class, and none of its variable-level DTA
metadata: no variable label, value labels, display format, notes, or
characteristics, and no `haven_labelled` class. This holds whatever
produced the value, a bare column reference, an arithmetic expression, or
a vector the caller labelled first. `set_var_label()`, `set_val_labels()`,
and the other setters author metadata on the new variable, as `label
variable` and `label values` follow `generate` in a Stata script.
`egen()` keeps authoring its own labels. `dplyr::mutate()`, the
replacement operators, `repl()`, and `:=` on an existing column are
unchanged: the R operations copy the vector with its attributes, and a
replacement keeps the target's metadata.

Before this decision the metadata came along exactly when the expression
happened to return the column object: `gen(data, y = x)` copied the label,
value labels, format, and notes of `x`, and `gen(data, y = x + 0)` copied
nothing. The divergences page recorded the first case as a deliberate
difference from Stata "because in R the labels are attributes of the
vector". That reasoning did not describe the code, which already dropped
attributes through arithmetic where base R keeps them, and it excused a
behaviour Stata avoids on purpose. Stata separates `generate`, which
copies values, from `clonevar`, which copies metadata, because a derived
variable that inherits its source's labels misdescribes itself: value
labels stay attached to codes that a later `replace` changes the meaning
of, a copied variable label describes the source in a codebook, and a
copied note usually names the variable it was written about. The
inconsistency was its own cost, since a user who learned that a bare
reference copies labels lost them on the first arithmetic expression with
no signal.

[ADR 0022](0022-give-gen-statas-generate-default.md) already draws the
line this decision follows: `gen()` and a new `:=` column translate
Stata's `generate` and take its defaults, while `mutate()` and the
operators are R operations on the container and follow R. Storage was
placed on the `generate` side of that line for value fidelity, so a value
that carries storage keeps it. Labels are about meaning, not fidelity,
and belong on the same side for the opposite reason: a translated line
must not attach a description its author never wrote. `mutate(data, y =
x)` and `data$y <- data$x` therefore become the R spelling of `clonevar`.

Keeping caller-authored metadata while dropping column-sourced metadata
was considered and rejected. Distinguishing the two needs a rule for what
counts as sourced, and `x[seq_along(x)]` or `ifelse(cond, x, x)` show how
little the expression's shape says about the metadata's origin. The
uniform rule is what a Stata user expects and what the setters already
support. Dropping the display format with the rest was chosen because
Stata's `generate` assigns the storage's default format rather than
copying the source's, and the writers do the same.

The consequences are that a generated column is described only by what
its author writes, that `gen()` and `mutate()` differ in one more
documented way, and that code relying on `gen(data, y = x)` carrying
labels adds a `set_var_label()` or `set_val_labels()` line, or uses
`mutate()`.
