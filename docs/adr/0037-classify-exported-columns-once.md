---
status: accepted
---

# Classify exported columns once, in the Arrow profile's vocabulary

`save_dta()`, `save_arrow()`, and `datasig()` classify every column of a
table with one R ladder, `.write_column_kind()` in `R/write-column.R`. It
returns one of ten kinds: `factor`, `stata`, `date`, `datetime`, `difftime`,
`character`, `raw`, `logical`, `integer`, `double`, or `NA` for a column no
writer exports. A column with a `stata.storage` declaration is `stata`
before it is a date or a number, so its declared storage is what every
target honours. Each writer then decides only whether its target holds a
kind (`save_dta()` refuses `difftime` and `raw`) and how to lay it out. The
per-column facts both writers read the same way — the variable label, the
`stata.string.storage` declaration, the calendar a numeric column counts,
the display-format family — are resolved by shared helpers in the same
file. Value layout stays with each writer: the DTA adapter carries R-epoch
values with a shift and scale for the native writer, plans string widths
natively, and exports a factor as its codes; the Arrow adapter passes
values through with the profile's calendar and a factor's levels.

Before this decision each writer had its own ladder. They agreed on the
common cases and disagreed at the edges: `save_dta()` exported a Stata
declaration on an R integer or logical that `save_arrow()` refused, and
`save_arrow()` exported a haven-labelled date that `save_dta()` refused.
`datasig()` classifies through the Arrow path
([ADR 0013](0013-sign-datasets-order-sensitively.md)), so a table could be
signed but not saved, or saved but not signed. The DTA ladder also
reported a malformed `stata.storage` declaration as an unsupported class,
where the Arrow ladder named the declaration.

The Arrow profile's vocabulary was chosen because it is the wider one: it
distinguishes the R types the profile records (`logical`, `integer`,
`raw`, `difftime`) that a DTA file collapses or refuses, and the DTA
adapter's mapping from those kinds to Stata storage is a short table. The
reverse, extending the DTA ladder, would have had to reinvent every
distinction the profile already makes.

Moving classification into native code was considered and rejected. The
native writers never inspect R attributes: C marshals positional lists
into `repr(C)` descriptors and Rust interprets integer codes. Classifying
natively would relocate the same class-set ladder from R into C, add a
structured report so that R could still raise the classed conditions the
tests pin, and give Rust an R-API dependency it does not have. It would
move the ladder without concentrating it. The native descriptors,
`C_dtatools_write` and `C_dtatools_save_arrow`, and the Rust write sources
are unchanged by this decision.

The consequences are that the two writers accept the same tables, that a
table `datasig()` signs is a table `save_dta()` saves unless it holds a
`difftime` or `raw` column, and that a new column class is admitted in one
place. Existing signatures are unchanged: the Arrow descriptor is
value-identical for every column both ladders already accepted.
