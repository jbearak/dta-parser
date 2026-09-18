---
status: accepted
---

# Value-label tables are Stata numerics, and missing values print as Stata spells them

`val_labels()` returns a value-label table as a named Stata numeric, a
`dta_double()`, or a `dta_long()` when `haven` stored integer codes: the
names are the displayed text and the values are the Stata codes, carried
as a Stata numeric rather than a bare R double. The `labels` attribute on
the vector itself is unchanged and stays the bare named vector that
`haven` and the `labelled` package store, so files, `haven::labelled()`,
and `labelled::val_labels()` see what they always did. Only the read
accessor changes shape. Alongside it, `format()` on any `dta_numeric`
spells a missing value as Stata does, `.` for system missing and `.a`
through `.z` for a tagged missing, and that spelling reaches every console
surface: a printed vector, a dibble or tibble column through pillar, a
data frame, and the value-label table itself. A printed vector that
carries value labels lists them under the values, with the codes in the
same spelling, and a dibble or tibble column annotates each labelled cell
with its text, `1 [One]`, `.a [Refused]`, as `haven`'s shaft did before
the package's own took precedence; `options(dtatools.show_pillar_labels =
FALSE)` turns that off. One helper, `.stata_missing_text()`, owns the
spelling, and the codebooks and `tab()`, which already printed `.a`, now
read it from there.

The table's storage does one more job. `haven::write_dta()` accepts an
integer vector only with integer codes, so a table's codes must go back
in the type they came from. The accessor records that type as the
table's storage, `long` for integer codes, and every setter reads it
back, so `val_labels(x) <- val_labels(x)` is a no-op, as a read-and-set
of any accessor should be. Storing codes in the target vector's type
instead was tried and rejected: the type then goes stale when storage
promotion carries the attribute onto a wider result.

Before this decision `val_labels()` returned the attribute verbatim, and
the attribute is a bare double because that is what `haven` writes. A
bare double has no print method, so a tagged-missing code printed as
`NA`, and it compares as R compares, so `labels == .a` was `NA` for every
element and `names(labels)[labels == .a]` returned nothing useful. A user
who wanted the label of `.a` had to wrap the table in a constructor first.
The vector print had the same gap: `dta_byte(c(1, .a))` printed `1 NA`,
and a dibble column showed `NA` for both `.` and `.a`, while the labelbook
and `tab()` a few lines away printed `.a`. The package's documentation,
error messages, and codebooks all spelled the codes `.a`; only the values
themselves did not.

Returning a `dta_numeric` was chosen over a purpose-built class because
the codes of a value-label table are Stata values, and `dta_numeric` is
already how the package says that a vector of doubles carries Stata
missing semantics. It brings Stata comparison, Stata ordering, the `.a`
spelling, and the setters' acceptance of the result for free, where a
`dtatools_val_labels` class whose only job was to print would have needed
its own comparison rule to make `labels == .a` work and would have been
one more class for users to learn. Returning the attribute unchanged and
publishing a formatter was considered and rejected: it fixes the print at
the console but leaves the comparison wrong, and the comparison is the
part a user cannot work around without knowing the package's internals.
Changing the stored attribute to a `dta_numeric` was rejected because the
attribute is the interoperability surface: `haven` reads it, `labelled`
reads it, and both writers serialize it, and none of them expect a
classed vector there. `dta_double` is the storage for double codes, rather than always
`dta_long`, because a user who builds a table from doubles should not
meet a widening error; the codes are read, not written, so no file is
affected by the choice.

The consequences are that a value-label table prints and compares as a
Stata user expects, that `identical(val_labels(x), c(One = 1))` is no
longer `TRUE` and callers who pinned that wrap the expected value in
`dta_double()` or read the bare named vector from the `labels`
attribute, and that every place
the package shows a Stata numeric missing value now agrees on the
spelling. A bare double that carries labels without a `dta_*()` class is
`haven`'s object, prints through `haven`'s methods, and is left alone.
