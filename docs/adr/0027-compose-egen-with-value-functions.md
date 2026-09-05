---
status: accepted
---

# Compose `egen()` with value functions

The fertility-surveys helpers combine Stata calculations with dataset mutation, which prevents using them as ordinary right-hand-side functions in dibble `:=` assignments. dtatools will provide value-returning functions and a by-reference `egen()` command that follows the calling conventions of `gen()` and `repl()`. Both interfaces will share the calculations; the value functions will not carry an `egen_` prefix merely because Stata exposes their counterparts through `egen`.

The migration targets dtatools first, with fertility-surveys adoption in a separate change. The function scope is the seven existing helpers plus mean, including generated group labels, Unicode handling, and storage requirements from issues #91, #93, and #96. Full `egen` parity remains outside this change.

Both interfaces call the same ordinary R functions under the `dta_` prefix, including `dta_max()` and `dta_total()`. `egen()` does not reinterpret base R function names as Stata handlers. For example, `egen(d, peak = dta_max(x), by = household)` and `d[, peak := dta_max(x), by = household]` share the maximum calculation.

`egen()` selects its calculation sample before evaluating the value function, matching Stata's exclusion of unselected observations from aggregation. In contrast, dibble `:=` retains its existing rule: the right-hand side sees the full group and the row selector restricts writes. Thus `egen(d, total = dta_total(x), where = eligible)` totals eligible observations, while `d[eligible, total := dta_total(x)]` totals every observation and writes only to eligible rows. An explicitly filtered argument supplies the selected total in the latter form. Command-specific output rules, including zero for excluded tag observations, belong to `egen()`.

The functions are `dta_mean()`, `dta_min()`, `dta_max()`, `dta_total()`, `dta_row_max()`, `dta_row_total()`, `dta_group_id()`, and `dta_group_tag()`. Multi-column functions accept ordinary vectors or a list or data frame of columns. Existing tidy injection supplies runtime names inside mutation expressions, for example `dta_row_max(!!!rlang::syms(cols))`; these functions do not introduce a separate tidyselect context.

Numeric calculation functions return unrounded doubles, stripping source variable and temporal metadata. Generation storage is chosen at assignment through the existing generate default or an explicit constructor or command type. Tags declare `byte` storage. Group identifiers offer Stata's optional `autotype` ladder of `byte`, `int`, `long`, and `double`. Ordinary calls remain usable in larger R expressions without premature float rounding.

ADR 0016 remains authoritative for labels: each variable owns its resolved code-to-text mapping. Group helpers generate labels and notes on their results, with optional table names as serialization hints. They do not create a live shared registry or replace other variables' mappings. This supersedes issue #93's older shared-registry requirement, including shared-table replacement semantics. DTA and Arrow round-trips must preserve the resulting resolved mappings under the existing serialization contract.

The existing `gen()` and `repl()` conventions govern target capture, formulas, data-mask collisions, reference aliases, and copy isolation. The older proposed command grammar in issue #91 is superseded where it conflicts with those conventions or with the ordinary value functions selected here. `egen()` creates one new column atomically; `:=` retains its create-or-replace behavior. Stata fixture checks and documentation distinguish intentional differences from missing functionality before the relevant issues close.

The available executable oracle is Stata 18. Its measured results accompany the migration as versioned fixtures; the guide identifies that baseline rather than claiming a Stata 19 execution. All-missing row maxima normalize to system missing, preserving the source helpers' contract. Long group and tag descriptions share one rule, a `see notes` label and the full expression in a note, instead of reproducing the shipped tag ado's overwritten label and different length test. These deliberate differences and ADR 0016's label ownership are recorded alongside the fixtures.
