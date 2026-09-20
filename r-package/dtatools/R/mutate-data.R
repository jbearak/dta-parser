#' Generate and replace variables by reference
#'
#' See [mutation-containers] for supported classes, grouping and conversion.
#' `gen()` and `replace_values()` modify a dibble by reference.
#' `repl()` is a direct alias for `replace_values()`. The return value is the
#' updated dataset, invisibly. Within spare capacity, aliases observe generation
#' and replacement. When generation needs more room, it creates an isolated
#' table and warns: existing aliases keep the old table. Return the updated
#' table from functions and assign it in the caller, for example `x <- f(x)`.
#' Ordinary caller symbols and supported plain-list/environment targets are
#' rebound after a successful growth commit. Computed or unsafe destinations
#' require explicit assignment of the returned result. Columns shared
#' with a separate table or standalone vector detach before values change;
#' Same-storage patches change all slots that hold the identical vector.
#' Promotion replaces only the named column, as do metadata setters.
#' Use `copy_data()` when an independent dataset is required.
#' Ordinary replacement operators and nested attribute or label replacement
#' follow R copy-and-rebind semantics, including on a [dibble]. Use explicit
#' metadata setters such as [set_var_format()] and [set_var_label()] to
#' update the caller's table inside a function.
#' Every generated column is stored in the physical column list, so direct
#' consumers such as `unclass()`, `dplyr::bind_rows()`, `purrr::map()`, and
#' `write.csv()` see the complete dataset. Constructors and readers reserve
#' 1,024 spare column-pointer slots by default, controlled by
#' `options(dtatools.alloccol = 1024L)`. With the default
#' `options(dtatools.auto_grow = TRUE)`, generation reserves the requested
#' addition plus that many spare slots when needed. Preparation and its warning
#' precede values, row selection and `bysort`. Set `options(dtatools.auto_grow = FALSE)`
#' to fail at that boundary instead; assign [reserve_columns()] first in strict
#' mode. No-growth helpers retain their separate preparation requirements.
#' [copy_data()] returns an isolated table with default spare capacity.
#' See [column_capacity()] and [can_add_columns()] for inspection.
#' `gen()` and `replace_values()` accept a grouped tibble and treat its dplyr
#' groups as assignment groups (see below). They reject rowwise tibbles;
#' `copy_data()` accepts both and preserves their class.
#'
#' The target and its values arrive through `...` in one of two shapes.
#' The tagged shape names the target on the left of `=`:
#' `gen(data, adjusted = income + 5)`. The positional shape is the
#' Stata-shaped spelling with the same meaning: `gen(data, adjusted,
#' income + 5)`. Exactly one target is set per call; two tags, a tag after
#' an untagged argument, or more than one trailing argument is an error.
#' `where` may follow either shape as a further untagged argument or be
#' given by name, but not both. Because the pair lives in `...`, the
#' formals `variable` and `values` no longer exist, so
#' `gen(data, values = 1)` generates a column called `values`, and no
#' argument is partially matched: `where` must be spelled in full.
#'
#' `variable` must be one unquoted name or one string. Tidy-evaluation
#' injection is supported, so `gen(data, !!name, value)` handles a name stored
#' in a string. No `rlang::inject()` wrapper is needed, because
#' `rlang::enquo()` already applies quasiquotation. The older
#' `gen(data, !!rlang::sym(name), value)` is equivalent and still works, but
#' `rlang::sym()` is not required: unquoting a string yields a character
#' scalar, and one nonempty, non-missing string is accepted in the `variable`
#' position. A literal `gen(data, "adjusted", value)` names a column the same
#' way. An empty string, `NA`, a character vector of length other than one, a
#' call other than `.()`, `...`, and a missing argument are errors. In the
#' tagged shape the same runtime names are spelled as tags:
#' `gen(data, !!name := value)`, `gen(data, .(name) := value)`, and
#' `gen(data, "adjusted" = value)`.
#'
#' `.(name)` is the one spelling that works in every position. It is
#' evaluated where it sits, so it can stand inside a larger expression the
#' way `!!` cannot: `values = income + .(name)` reads the column that `name`
#' holds. The argument is evaluated in the caller's environment, never in
#' the data mask, so a column sharing the variable's name cannot shadow it,
#' and it must be one nonempty, non-missing string.
#'
#' In the `values` and `where` expressions a runtime name is also reached
#' through the mask's `.data` pronoun: `values = .data[[name]]` and
#' `where = !is_missing(.data[[name]])`. Note the asymmetry, which is the
#' surprising part: `.data[[name]]` works in `values` and `where` but not in
#' the `variable` position, because `variable` names a target rather than
#' reading a column. Use `!!name` or `.(name)` there.
#'
#' `values` and `where` use a data mask built from the dataset before the
#' mutation. Columns win over objects in the calling environment. When a
#' bare symbol in either expression is both a column and an object bound
#' anywhere from the calling frame up to the global environment, the call
#' is an error rather than a silent choice: write `.data$name` for the
#' column or `.env$name` for the object. Bindings in attached packages and
#' base are not consulted, so a column named `pi` or `T` is not flagged;
#' an object that is a function does not count, so a script named after
#' the column it builds is not flagged either; and the right-hand side of
#' `$`, the body of `.()`, and function positions are never treated as
#' column reads.
#' `options(dtatools.shadow_check = FALSE)` disables the check. A stored or
#' inline one-sided formula evaluates its right-hand side in the same data
#' mask and uses the formula environment as its fallback; a formula is a
#' request to read the data, so its symbols are exempt from the check and
#' columns win. Two-sided formulas are rejected.
#'
#' `where = NULL` selects every row. A logical result must have size one or the
#' dataset row count; missing logical values do not select a row. Numeric row
#' positions must be positive, finite, whole, and in range. Zero, negative,
#' missing, and out-of-range positions are errors. Duplicate positions are
#' accepted and the last replacement for a row wins. Numeric positions are
#' snapshotted before writing, including when `where` returns the target column
#' or another column sharing its payload. `values` must have size
#' one, the selected-row count, or the full dataset row count. Full-length
#' values are indexed by the selected row positions.
#'
#' Two mask variables stand beside the columns in `values` and `where`:
#' `.N` is the row count and `.n` the row number, `1` through `.N`. Both
#' are exempt from the shadow check, so a caller object called `.N` is
#' never consulted. Without groups they describe the whole dataset, so
#' `repl(d, last = 1, where = .n == .N)` marks the final row.
#'
#' @section Group-wise assignment:
#' `by` and `bysort` evaluate the mutation separately within groups, as
#' Stata's `by varlist:` prefix does. Groups are formed first. Then, for
#' each group, `where` is evaluated on that group's rows and `values`
#' against that group's columns, with `.N` the group's row count and `.n`
#' the within-group row number. Per group, `values` must have size one,
#' the group's selected-row count, or `.N`; anything else is an error
#' naming the group's key values. The per-group results are gathered into
#' one full-length assignment and written through the same path as an
#' ungrouped call, so storage validation, compact patching, and
#' transactions are unchanged. Rows a group's `where` does not
#' select are left alone by `replace_values()` and hold missing after
#' `gen()`, which still appends the new column once.
#'
#' This is Stata's order of operations, not data.table's. data.table's
#' `dt[i, j, by]` applies `i` first and groups only the surviving rows,
#' so under a non-empty `i` its `.N` counts selected rows and its groups
#' omit any group `i` empties. Here `.N` counts the group's rows whatever
#' `where` selects, and `where = .n == .N` marks each group's last row.
#' The data.table special symbols `.SD`, `.GRP`, and `.BY` are not provided.
#' Use [dplyr::summarise()] to produce a new aggregated table. Grouped
#' `gen()` and `egen()` write their statistics into the existing rows.
#'
#' `by` groups the dataset in its current row order and never sorts.
#' `bysort` sorts the dataset by reference on every listed column, in
#' Stata's total order for `dta_*()` columns (finite values, then `.`,
#' then `.a` through `.z`), and groups by those same columns, so the
#' rows within each group are the sorted rows and `.n` follows the sort.
#' The sort is written together with the assignment: a call that fails
#' before its assignment writes leaves the dataset in its original
#' order. Several `:=` assignments in one bracket call sort with the
#' first that writes; once that one has written, the sort stays, and a
#' later assignment that fails leaves the dataset sorted with the earlier
#' ones written, as two Stata lines would.
#' Stata's parenthesized sort-only keys are not supported: `bysort id
#' (date):` is an `arrange()` or `reorder_dta_rows()` line followed by
#' `by = id`. Group identity uses Stata value identity for `dta_*()`
#' columns and ordinary identity otherwise, so missing values form their
#' own group, as in Stata, and each extended missing code its own.
#'
#' A grouped tibble supplies its dplyr groups. Giving `by` or `bysort` to
#' one is an error rather than a precedence rule; ungroup it first.
#' Supplying both `by` and `bysort` is also an error. Column names follow
#' the package's usual rules: `by = g`, `by = c(g1, g2)`, `by = c("g1",
#' "g2")`, `by = !!name`, and `by = .(name)`, where `.()` evaluates its
#' argument to a string as it does everywhere else in dtatools, not
#' data.table's `list()`.
#'
#' `gen()` appends one variable, or inserts it beside an existing column
#' with `before` or `after`, as Stata's `generate ..., before(varname)` and
#' `after(varname)` do. The new column takes the storage in
#' [dta-storage-defaults]: a declared `dta_*()` result keeps its storage,
#' bare integer results are `long`, bare double results take Stata's
#' `generate` default of `float`, or `double` under
#' `options(dtatools.generate_type = "double")`, the equivalent of Stata's
#' `set type double`; logical results stay logical, `Date` and `POSIXct`
#' results keep their class with a Stata date or datetime declaration, and
#' character results
#' keep a valid declared `stata.string.storage` or take the smallest
#' `str1` through `str2045` width that fits, or `strL` above 2,045 UTF-8
#' bytes. Like Stata's `generate`, `gen()` copies values, not labels: the
#' new column takes the storage, string storage, and date or datetime
#' class of its value and none of its variable metadata, so `gen(data, y =
#' x)` has no variable label, value labels, display format, notes, or
#' characteristics, and a `haven_labelled` value arrives as a plain typed
#' column. Author them with [set_var_label()], [set_val_labels()], and the
#' other setters, as `label variable` and `label values` follow `generate`
#' in Stata. [dplyr::mutate()] and the replacement operators are R
#' operations and copy the vector with its attributes (see [ADR
#' 0039](https://github.com/jbearak/dta-parser/blob/main/docs/adr/0039-generate-copies-values-not-labels.md)).
#' Other classed numeric results, including `difftime` and
#' `bit64::integer64`, are rejected because their physical representation
#' does not have Stata numeric semantics; convert them first. Numeric rows
#' excluded by `where` contain system missing. Excluded string rows contain
#' `""`, Stata's string missing, and excluded logical rows `NA`. Wrap the
#' value expression in a Stata constructor to request other storage.
#' `gen()` never changes what kind of table it was handed: a tibble stays
#' a tibble and a data frame a data frame, with their existing columns
#' untouched. Only the column `gen()` writes is typed. Call
#' [as_dibble()] for a Stata dataset, where every column is typed.
#' Stata `[in]` and `:lblname` authoring are not supported; the
#' `by varlist:` prefix is `by`/`bysort`.
#' `replace_values()` and `repl()` preserve the input R numeric value by
#' default. A target whose declared storage cannot hold it exactly widens
#' to the narrowest eligible storage, accounting for range, integrality,
#' and precision without reducing the column's integer capacity. See
#' [dta-storage-defaults] for the ladder. Promotion is reported as an R
#' message, such as \code{variable `x` was byte now int}; suppress it with
#' `suppressMessages()`. An assignment selecting no rows promotes nothing.
#'
#' This precision policy intentionally differs from Stata. A `float`
#' receiving 16777217 becomes `double` here, preserving 16777217; Stata 18
#' keeps `float` and rounds to 16777216. A `byte` receiving 0.1 becomes
#' `double` here rather than Stata's rounded `float`. "Exact" means the
#' input binary64 R value, not exact decimal arithmetic: R's 0.1 is already
#' a binary approximation of one tenth. Promotion cannot recover digits
#' lost before assignment, including an explicit `dta_float()` conversion.
#'
#' \tabular{llll}{
#' Input and replacement \tab Stata 18 \tab `promote = TRUE` \tab `promote = FALSE` \cr
#' `float`, 16777217 \tab `float`, 16777216 \tab `double`, 16777217 \tab `float`, 16777216 \cr
#' `byte`, 0.1 \tab `float`, rounded to float \tab `double`, exact input R double \tab Error \cr
#' }
#'
#' `promote = FALSE` disables widening and uses the declared storage's
#' conversion rules. Float targets can round without an error. Integer
#' targets reject fractional or out-of-range values, leaving the column
#' unchanged. This is neither a general Stata-compatibility mode nor a
#' guarantee against precision loss.
#'
#' For identifiers, choose sufficient storage in Stata before assignment,
#' for example `generate long cluster = source_cluster` within the `long`
#' range, or `recast double cluster` before replacing an existing column.
#' Widening an already rounded identifier cannot restore lost digits.
#' Investigate disagreements before adding casts that reproduce rounding
#' in R. The
#' [intentional differences guide](https://github.com/jbearak/dta-parser/blob/main/docs/r-stata-divergences.md#numeric-replacement)
#' includes the executable Stata example, migration guidance, and links to
#' the Stata conformance probes and R tests. See also
#' [ADR 0024](https://github.com/jbearak/dta-parser/blob/main/docs/adr/0024-promote-in-replace-values-as-stata-does.md).
#' Character `NA` replacement values are normalized to `""`, Stata's string
#' missing value.
#'
#' The table records the deliberate first-release choices relative to Stata's
#' `generate [type] newvar = exp [if] [in]` command.
#'
#' \tabular{lll}{
#' Topic \tab Stata \tab dtatools \cr
#' Existing name \tab Error \tab Error before mutation \cr
#' Numeric default \tab `float`, or `double` after `set type` \tab `float`, or `double` under `options(dtatools.generate_type = "double")`; integer results `long` (see [dta-storage-defaults]) \cr
#' Explicit storage \tab Type prefix \tab `dta_*()` value expression \cr
#' Strings \tab Smallest fitting `str#` or `strL` \tab Declared width, otherwise smallest UTF-8-byte width or `strL` \cr
#' Rows outside `if` \tab Numeric `.` or string `""` \tab Same \cr
#' Expression with `if` \tab Evaluated only for selected observations \tab Evaluated once for all rows, then selected \cr
#' Placement \tab Optional placement commands \tab Append only \cr
#' Missing report \tab Command output \tab No printed report \cr
#' }
#'
#' Compact `byte`, `int`, `long`, and `float` columns are patched in their
#' native storage after validation. A direct compact target allocates work
#' proportional to the selected rows and does not create a full R double copy.
#' Newly generated compact columns retain exclusive ownership, so their first
#' replacement uses the same direct path without detaching a full native copy.
#' The native path keeps compact rollback bytes until the write commits so an
#' interrupt restores the original payload and missing-value cache.
#' A metadata proxy first detaches by copying its compact native payload so an
#' independent source remains unchanged; it still avoids a full R double copy.
#' Materialized compact numeric columns are validated against their declared
#' storage and patched directly in their decoded R buffer. A `where` expression
#' that is one comparison of a Stata numeric column with a scalar or another
#' Stata numeric column is fused with compact-target replacement, avoiding a
#' logical selection vector. Other selections keep the general path. Ordinary
#' numeric columns and character columns are patched in their existing R
#' representation. Replacing a dictionary-backed string materializes that
#' target character column, but does not copy the data frame.
#' Dictionary-backed replacement values are validated through a read-only
#' native reader, so a successful mutation, error, or interrupt does not
#' populate a shared source cache. `copy_data()` keeps unmaterialized compact
#' numeric and dictionary-string columns compact, and deep-copies dataset
#' attributes such as names and grouped-tibble metadata. It rejects columns or
#' attributes containing environments, functions, bytecode, external pointers,
#' or weak references because those objects cannot be isolated by ordinary R
#' copying.
#'
#' @param data A dibble to mutate; assign `data <- as_dibble(data)` to
#'   convert another container first. A grouped dibble's groups become the
#'   assignment groups. Rowwise dibbles are rejected; `copy_data()` accepts
#'   them.
#' @param ... The target and its values, as one tagged pair
#'   `variable = values` or as the two positional arguments `variable,
#'   values`, optionally followed by one untagged `where`. `variable` is
#'   exactly one unquoted name, or one nonempty, non-missing character
#'   string, which is what `!!name` unquotes to and what a `.(name)` call
#'   supplies in place. An empty string, `NA`, a character vector of length
#'   other than one, a call other than `.()`, `...`, and a missing argument
#'   are errors. `values` is a value expression or one-sided formula. It may
#'   reference a column whose name is a string through the mask's `.data`
#'   pronoun.
#' @param where `NULL`, a logical expression, valid row positions, or a
#'   one-sided formula. It may also be supplied as the last untagged
#'   argument in `...`. Under groups it is evaluated per group, and row
#'   positions count within the group.
#' @param by `NULL`, or the columns to group by, as bare names, strings,
#'   `c()` of those, `!!name`, or `.(name)`. Rows keep their current
#'   order. Not allowed with `bysort` or on a grouped tibble.
#' @param bysort `NULL`, or the columns to sort the dataset by, by
#'   reference, and then group by. Same spellings as `by`. Not allowed with
#'   `by` or on a grouped tibble.
#' @param before,after An optional existing column name before or after
#'   which `gen()` inserts the new column, as Stata's `before()` and
#'   `after()` options. Supply at most one. Uses the target-name syntax:
#'   a bare name, a string, `!!name`, or `.(name)`. Without either the
#'   column is appended. `replace_values()` has no placement, since its
#'   column already has a position.
#' @param promote Whether `replace_values()` widens a target whose declared
#'   storage cannot preserve the input R value exactly, reporting the
#'   change. Defaults to `TRUE`. `FALSE` holds declared storage fixed:
#'   float targets can round, while integer targets reject fractional or
#'   out-of-range values. It is not a Stata-compatibility mode. Ignored by `gen()`, which creates
#'   the column and so has no prior storage to widen.
#' @return `gen()` returns the updated table invisibly: `data` when existing
#'   capacity is sufficient, or an isolated table after automatic growth.
#'   Return the updated table from functions and assign it in the caller.
#'   `replace_values()` returns `data` invisibly.
#'   `copy_data()` returns an independent dibble.
#' @references
#' StataCorp, \href{https://www.stata.com/manuals/dgenerate.pdf}{generate manual}.
#' @seealso [dibble-bracket] for `data[i, y := value]` on a [dibble], which
#'   creates or overwrites in one call and takes the same `by`, `bysort`,
#'   and grouped input.
#' @examples
#' data <- dibble(x = dta_float(1))
#' repl(data, x = 16777217)
#' dta_storage_type(data$x)  # "double"
#' as.double(data$x)        # 16777217
#'
#' fixed <- dibble(x = dta_float(1))
#' repl(fixed, x = 16777217, promote = FALSE)
#' dta_storage_type(fixed$x)  # "float"
#' as.double(fixed$x)        # 16777216
#'
#' fraction <- dibble(x = dta_byte(1))
#' repl(fraction, x = 0.1)
#' dta_storage_type(fraction$x)  # "double"
#' identical(as.double(fraction$x), 0.1)  # TRUE
#'
#' survey <- dibble(income = c(10, 20), eligible = c(TRUE, FALSE))
#' gen(survey, adjusted = income + 5)
#' gen(survey, id = .n, before = income)   # generate id = _n, before(income)
#' names(survey)                           # "id" "income" "eligible" "adjusted"
#' replace_values(survey, income = income * 2, where = eligible)
#' # The positional, Stata-shaped spelling means the same thing
#' gen(survey, tripled, income * 3)
#' replace_values(survey, tripled, 0, eligible)
#' independent <- copy_data(survey)
#' repl(independent, income = 0)
#'
#' # A name known only at run time, in each position that accepts one
#' target_name <- "adjusted"
#' source_name <- "income"
#' repl(survey, !!target_name := 0)
#' repl(survey, .(target_name) := 1)
#' repl(survey, !!target_name, 2)
#' gen(survey, doubled = .data[[source_name]] * 2)
#' repl(survey, doubled = 0, where = .data[[source_name]] > 15)
#'
#' # Group-wise assignment in Stata's `by varlist:` order
#' panel <- dibble(id = c(2, 1, 2, 1), t = c(1, 1, 2, 2), x = 1:4)
#' gen(panel, rows = .N, by = id)               # each group's row count
#' gen(panel, last = .n == .N, by = id)         # each group's last row
#' gen(panel, above = x - mean(x), by = id)     # centred within group
#' repl(panel, x = 0, where = .n == 1, bysort = c(id, t))  # sorts first
#' @export
replace_values <- function(data, ..., where = NULL, by = NULL,
                           bysort = NULL, promote = TRUE) {
    .require_mutation_target(data)
    shared <- .Call(C_dtatools_shared_columns, data)
    .preflight_mutation_target(data)

    arguments <- .mutation_arguments(
        substitute(...()), rlang::enquo(where), missing(where),
        function() .capture_positional_pair(...),
        function() .capture_positional_triple(...),
        function() rlang::enquos(..., .ignore_empty = "none"),
        function() rlang::enquos0(...)
    )
    # `missing()` keeps the two extra quosure captures off the ungrouped
    # path, which `repl()` in a loop depends on.
    result <- .mutate_data(
        data, arguments$variable, arguments$values, arguments$where,
        generate = FALSE,
        by = if (missing(by)) NULL else rlang::enquo(by),
        bysort = if (missing(bysort)) NULL else rlang::enquo(bysort),
        promote = .validate_promote(promote), report_promotion = TRUE,
        entry_shared = shared
    )
    invisible(result)
}

.validate_promote <- function(promote) {
    if (!rlang::is_bool(promote)) {
        stop("`promote` must be `TRUE` or `FALSE`", call. = FALSE)
    }
    promote
}

#' @rdname replace_values
#' @export
repl <- replace_values

#' @rdname replace_values
#' @export
gen <- function(data, ..., where = NULL, by = NULL, bysort = NULL,
                before = NULL, after = NULL) {
    target_expr <- substitute(data)
    destination <- if (is.call(target_expr)) .capture_mutation_binding(target_expr, parent.frame()) else NULL
    if (!is.null(destination)) data <- destination$data
    .require_mutation_target(data)
    auto_grow <- .mutation_auto_grow()
    if (is.null(.mutation_fast_shape(data))) {
        .preflight_mutation_target(data)
    }
    # Before `...` is captured: injection in the dots can run caller code,
    # and a call whose placement is wrong must fail with nothing evaluated.
    placement <- .generate_placement(rlang::enquo(before), rlang::enquo(after))
    .placement_anchor(placement, attr(data, "names", exact = TRUE))

    arguments <- .mutation_arguments(
        substitute(...()), rlang::enquo(where), missing(where),
        function() .capture_positional_pair(...),
        function() .capture_positional_triple(...),
        function() rlang::enquos(..., .ignore_empty = "none"),
        function() rlang::enquos0(...)
    )
    result <- .mutate_data(
        data, arguments$variable, arguments$values, arguments$where,
        generate = TRUE,
        by = if (missing(by)) NULL else rlang::enquo(by),
        bysort = if (missing(bysort)) NULL else rlang::enquo(bysort),
        auto_grow = auto_grow, placement = placement
    )
    .return_mutation(data, result, if (is.null(destination)) target_expr else destination, parent.frame())
}

# Stata's `before(varname)` and `after(varname)` on `generate`. Read before
# any evaluation so a call that names both fails with the table untouched;
# the anchor is checked by `.placement_anchor()` and the final order
# computed by `.mutation_placement()` at the commit.
.generate_placement <- function(before, after) {
    has_before <- !rlang::quo_is_null(before)
    has_after <- !rlang::quo_is_null(after)
    if (has_before && has_after) {
        stop("supply either `before` or `after`, not both", call. = FALSE)
    }
    if (!has_before && !has_after) return(NULL)
    list(side = if (has_before) "before" else "after",
         anchor = .unquoted_variable_name(if (has_before) before else after))
}

# The anchor's position among `names`, or `NULL` without a placement. The
# anchor must be an existing column; the target is not one yet, so it cannot
# anchor itself. Checked twice per `gen()`: on entry, so a bad anchor fails
# before anything is evaluated, and at the commit, against the names the
# table has by then, since evaluating `values` may have mutated it.
.placement_anchor <- function(placement, names) {
    if (is.null(placement)) return(NULL)
    index <- match(placement$anchor, names)
    if (is.na(index)) {
        stop(sprintf("Column `%s` does not exist", placement$anchor), call. = FALSE)
    }
    index
}

# The column order once the new column sits beside its anchor, as positions
# into `c(names, target)`, or `NULL` when it is appended.
.mutation_placement <- function(placement, names, target) {
    index <- .placement_anchor(placement, names)
    if (is.null(index)) return(NULL)
    order <- append(names, target, after = index - (placement$side == "before"))
    match(order, c(names, target))
}

.MUTATION_SHAPE_MESSAGE <- paste(
    "`...` must be `variable, values` or one `variable = values` pair,",
    "optionally followed by `where`"
)

# `gen()` and `replace_values()` take their target and value through
# `...`, in one of two shapes: the positional pair `variable, values`, or
# one tagged pair `variable = values`. Either may be followed by one
# untagged `where`. Placing the pair in `...` is what lets a tag name the
# target, and it also removes partial matching of `variable`, `values`,
# and `where`, so a column called `val` or `w` can be a target.
#
# The shape is read from the unevaluated dots first. The common shapes
# are then captured by forwarding `...` into a fixed-arity helper, which
# costs a fraction of `rlang::enquos()` and matters because `repl()` is
# often called in tight loops. Untagged dots of any other count take
# `rlang::enquos()` so its own errors apply. Tagged dots are captured with
# `rlang::enquos0()`, which is cheaper still and, unlike `enquos()`, lets
# a `.(name) := value` tag through: rlang rejects a call on the left of
# `:=` before evaluating anything. Each dot is then re-quoted in its own
# frame so `!!` and `:=` inside it keep their ordinary meaning.
.mutation_arguments <- function(quoted, where, where_missing, pair, triple,
                                quosures, quosures0) {
    count <- length(quoted)
    tags <- names(quoted)
    if (is.null(tags)) tags <- rep("", count)
    tagged <- nzchar(tags)
    empty <- vapply(
        as.list(quoted), function(dot) identical(dot, quote(expr = )),
        logical(1L)
    )
    assigned <- vapply(
        as.list(quoted),
        function(dot) is.call(dot) && identical(dot[[1L]], quote(`:=`)),
        logical(1L)
    )
    if (!any(tagged) && !any(assigned)) {
        if (!any(empty) && (count == 2L || (count == 3L && where_missing))) {
            captured <- if (count == 2L) pair() else triple()
            return(list(
                variable = captured[[1L]], values = captured[[2L]],
                where = if (count == 3L) captured[[3L]] else where
            ))
        }
        dots <- quosures()
    } else {
        dots <- .mutation_dots_with_runtime_names(quosures0())
    }
    tags <- names(dots)
    if (is.null(tags)) tags <- rep("", length(dots))
    tagged <- nzchar(tags)
    count <- length(dots)
    if (count == 0L) stop(.MUTATION_SHAPE_MESSAGE, call. = FALSE)
    if (tagged[[1L]]) {
        variable <- rlang::new_quosure(tags[[1L]], emptyenv())
        values <- dots[[1L]]
        rest <- dots[-1L]
        rest_tagged <- tagged[-1L]
    } else {
        variable <- dots[[1L]]
        if (count >= 2L && tagged[[2L]]) {
            stop(.MUTATION_SHAPE_MESSAGE, call. = FALSE)
        }
        values <- if (count >= 2L) {
            dots[[2L]]
        } else {
            rlang::new_quosure(rlang::missing_arg(), emptyenv())
        }
        rest <- dots[-(1:2)]
        rest_tagged <- tagged[-(1:2)]
    }
    if (any(rest_tagged) || length(rest) > 1L) {
        stop(.MUTATION_SHAPE_MESSAGE, call. = FALSE)
    }
    if (length(rest) == 1L) {
        if (!where_missing || rlang::quo_is_missing(rest[[1L]])) {
            stop(.MUTATION_SHAPE_MESSAGE, call. = FALSE)
        }
        where <- rest[[1L]]
    }
    list(variable = variable, values = values, where = where)
}

.capture_positional_pair <- function(variable, values) {
    list(rlang::enquo(variable), rlang::enquo(values))
}

.capture_positional_triple <- function(variable, values, where) {
    list(rlang::enquo(variable), rlang::enquo(values), rlang::enquo(where))
}

.mutation_dots_with_runtime_names <- function(quosures) {
    labels <- names(quosures)
    if (is.null(labels)) labels <- rep("", length(quosures))
    result <- vector("list", length(quosures))
    for (index in seq_along(quosures)) {
        quosure <- quosures[[index]]
        if (rlang::quo_is_missing(quosure)) {
            result[[index]] <- quosure
            next
        }
        expression <- rlang::quo_get_expr(quosure)
        frame <- rlang::quo_get_env(quosure)
        if (.is_runtime_name_tag(expression)) {
            labels[[index]] <- .runtime_name_call_value(
                expression[[2L]], frame
            )
            expression <- expression[[3L]]
        }
        # The function object heads the call, because a constant's
        # quosure carries the empty environment, where `::` is unbound.
        requoted <- eval(as.call(list(rlang::quos, expression)), frame)
        if (!nzchar(labels[[index]]) && !is.null(names(requoted))) {
            labels[[index]] <- names(requoted)[[1L]]
        }
        result[[index]] <- requoted[[1L]]
    }
    names(result) <- labels
    result
}

# Stored type information is separate from current ownership. Readers use
# the supplied physical table, never a cached owner or column. An in-place
# conversion that removes the marker also removes its meaning.
.reference_state <- function(data) {
    if (!inherits(data, "dtatools_ref_data")) return(NULL)
    state <- attr(data, ".dtatools_ref_state", exact = TRUE)
    if (is.environment(state)) state else NULL
}

# The bare column list. Every dibble snapshot and reference-state
# construction passes through here, so this is one shallow copy with its
# attributes cleared rather than a closure call per column.
.plain_data_columns <- function(data) {
    physical <- unclass(data)
    attributes(physical) <- NULL
    physical
}

.column_access <- function(data) {
    list(data = data, names = attr(data, "names", exact = TRUE))
}

.data_column_at <- function(access, index) .subset2(access$data, index)

.set_data_column_at <- function(access, index, column) {
    .Call(C_dtatools_set_data_column, access$data, as.integer(index), column)
    invisible(NULL)
}

.native_data_column_location <- function(access, index) index

.data_columns <- function(data) {
    physical <- .plain_data_columns(data)
    names(physical) <- attr(data, "names", exact = TRUE)
    physical
}

# Every dibble's columns are physical: the reference state records only
# the base classes the next mark restores. The native marker adds `owner`,
# a non-owning identity token. Do not retain column vectors here: extra
# references would hide whether a physical vector is shared with an
# ordinary R copy at the write boundary.
.new_reference_state <- function(data) {
    state <- new.env(parent = emptyenv())
    state$classes <- .reference_base_classes(class(data))
    state
}

.reference_state_valid <- function(data) {
    isTRUE(.Call(C_dtatools_reference_state_valid, data))
}

.reserve_column_capacity <- function(x, n = getOption("dtatools.alloccol", 1024L)) {
    n <- .validate_alloccol(n, length(x))
    .Call(C_dtatools_reserve_column_capacity, x, as.double(length(x)) + n)
}

# The public dataset identity comes before shared reference dispatch. Stored
# base classes contain grouping and metadata behavior, never package identity.
.reference_base_classes <- function(classes) {
    setdiff(classes, c("dibble", "dtatools_ref_data"))
}

.reference_classes <- function(classes) {
    c("dibble", "dtatools_ref_data", .reference_base_classes(classes))
}

# The native marker records a non-owning identity token. Serialization clears
# it; validation never follows it or repairs a shared environment in place.
.mark_reference_data <- function(data, state) {
    classes <- .reference_classes(state$classes)
    .Call(C_dtatools_mark_reference_data, data, state, classes)
}

# Fresh bookkeeping for a table whose physical shape is final. Every write
# that changes the column set or the backing ends here.
.mark_fresh_reference <- function(data) {
    .mark_reference_data(data, .new_reference_state(data))
}

# A prepared table: spare column slots, then fresh bookkeeping. Assign the
# result; the input is left as it was.
.new_prepared_table <- function(x, n = getOption("dtatools.alloccol", 1024L)) {
    .mark_fresh_reference(.reserve_column_capacity(x, n))
}

# Commit shapes. Each by-reference writer ends in one native commit; the
# table records what follows it, so the decision is not re-derived per
# writer. A write remarks when it changes the column set or the backing,
# because the mark records the base classes and the owner of that shape;
# a value or row-order write leaves both alone. A grouped input regroups
# after any value write, since a target may share its vector with a key.
#
#   writer                          native commit                  remark  regroup  interrupt guard
#   gen(), :=, direct scalar        append_data_column             yes     no       suspendInterrupts
#   repl(), := on existing column   patch_slot / fused_patch_slot  no      grouped  none (C stages first)
#   repl() storage promotion        set_data_column                no      grouped  none
#   keep/drop/rename/order, egen()  select_data_columns            yes     no       none (C validates first)
#   metadata table setters          set_data_column, set_attribute yes     no       none
#   reorder_dta_rows()              replace_reference_columns      no      no       none (C validates first)
#   bysort's sort, first write      the writer's, then disarm undo  (the writer's)    suspendInterrupts
#   reserve_columns(), constructors reserve_column_capacity         yes     no       none (fresh table)

.reference_snapshot <- function(data) {
    if (!any(class(data) %in% c("dibble", "dtatools_ref_data"))) return(data)
    # Every column is physical, so the snapshot is the object minus its
    # mark. Dropping the attribute shallow-copies the list, which is what
    # every `[` and dplyr call on a read result pays.
    attr(data, ".dtatools_ref_state") <- NULL
    class(data) <- .reference_base_classes(class(data))
    data
}

# Value helpers accept grouped tibbles; structural helpers require ungrouped
# input. Metadata setters and assigned utilities also accept rowwise tibbles.
# Validate the physical shape and grouping before caller expressions run.
.as_mutation_data <- function(data, allow_grouped = FALSE,
                              allow_rowwise = allow_grouped,
                              private_views = FALSE) {
    .validate_mutation_container(data, allow_grouped, allow_rowwise)
    names <- attr(data, "names", exact = TRUE)
    if (is.null(names) || anyNA(names) || any(names == "") ||
        anyDuplicated(names)) {
        stop("`data` must have unique, non-missing column names; duplicated names are ambiguous", call. = FALSE)
    }
    row_count <- abs(.row_names_info(data, 2L))
    if (.data_table_container(data) && length(data) == 0L && row_count != 0L) {
        stop("An empty data.table must have zero rows; assign `data <- as_dibble(data)` to convert its public contents",
             call. = FALSE)
    }
    columns <- if (private_views) {
        .Call(C_dtatools_mutation_views, data)
    } else .data_columns(data)
    sizes <- attr(columns, ".dtatools_mutation_sizes", exact = TRUE)
    if (is.null(sizes)) {
        sizes <- vapply(columns, NROW, numeric(1))
    } else {
        unknown <- is.na(sizes)
        sizes[unknown] <- vapply(columns[unknown], NROW, numeric(1))
    }
    if (any(sizes != row_count)) {
        stop("`data` has columns with inconsistent row counts; assign `data <- dplyr::ungroup(data)` and group again", call. = FALSE)
    }
    grouping_columns <- columns
    if (private_views && (inherits(data, "grouped_df") || inherits(data, "rowwise_df"))) {
        # Group validation can invoke user-defined casts and proxies. Only the
        # keys cross that callback boundary, and must have isolated handles.
        keys <- intersect(names, setdiff(names(attr(data, "groups", exact = TRUE)), ".rows"))
        grouping_columns[keys] <- lapply(columns[keys], .metadata_copy)
    }
    .validate_group_metadata(data, grouping_columns, names, row_count)
    list(columns = columns, names = names, nrow = row_count)
}

# Validate supported physical shapes without retaining their columns or names.
# Both public preflight and direct generation call this: argument capture can
# execute quasiquotation callbacks between those two validation moments.
.mutation_fast_shape <- function(data) {
    .validate_mutation_container(data, allow_grouped = TRUE, allow_rowwise = FALSE)
    if (inherits(data, "grouped_df")) return(NULL)
    rows <- abs(.row_names_info(data, 2L))
    if (isTRUE(.Call(C_dtatools_mutation_shape, data, rows))) rows else NULL
}

# Eligibility checks must not dispatch methods while examining a literal AST.
.mutation_literal_member <- function(value) {
    is.character(value) && is.null(attributes(value)) && !.is_altrep(value) &&
        length(value) == 1L && !is.na(value)
}

# Only already evaluated, unclassed scalar bindings qualify. Promises and
# active bindings can return formulas or retain/mutate a table before a later
# mask read, so they must use the complete snapshot path from the outset.
.mutation_scalar_binding <- function(quo, data) {
    expression <- rlang::quo_get_expr(quo)
    environment <- rlang::quo_get_env(quo)
    value <- expression
    if (is.symbol(expression)) {
        name <- as.character(expression)
        if (name %in% c(".n", ".N", ".data", ".env")) return(NULL)
        location <- .Call(C_dtatools_mutation_name_location, data, name)
        if (is.null(location) || !is.na(location)) return(NULL)
    } else if (is.call(expression) && is.null(attributes(expression)) && length(expression) == 3L &&
               identical(expression[[2L]], quote(.env)) &&
               ((identical(expression[[1L]], quote(`$`)) && is.symbol(expression[[3L]])) ||
                (identical(expression[[1L]], quote(`[[`)) &&
                 .mutation_literal_member(expression[[3L]])))) {
        name <- as.character(expression[[3L]])
    } else if (!is.atomic(expression)) return(NULL) else name <- NULL
    if (!is.null(name)) {
        if (is.na(name) || !nzchar(name)) return(NULL)
        while (!identical(environment, emptyenv()) &&
               !exists(name, environment, inherits = FALSE)) environment <- parent.env(environment)
        if (identical(environment, emptyenv()) || bindingIsActive(name, environment) ||
            rlang::env_binding_are_lazy(environment, name)[[1L]]) return(NULL)
        value <- get(name, environment, inherits = FALSE)
    }
    if (!typeof(value) %in% c("integer", "double", "logical", "character") ||
        !is.null(attributes(value)) || .is_altrep(value) || length(value) != 1L) return(NULL)
    list(value = value)
}

.generate_direct_scalar <- function(data, variable, values, where, auto_grow,
                                    selection = NULL) {
    row_count <- .mutation_fast_shape(data)
    if (is.null(row_count) || rlang::quo_is_missing(values) ||
        (!is.null(selection) && !is.null(selection$groups))) return(NULL)
    selected <- .direct_scalar_rows(data, where, selection)
    if (is.null(selected)) return(NULL)
    if (!is.null(selected$rows) &&
        (!typeof(selected$rows) %in% c("integer", "double") ||
         !is.null(attributes(selected$rows)) || .is_altrep(selected$rows))) return(NULL)
    expression <- rlang::quo_get_expr(variable)
    if (!is.symbol(expression) && !is.character(expression)) return(NULL)
    if (is.character(expression) && (!is.null(attributes(expression)) || .is_altrep(expression))) return(NULL)
    name <- .unquoted_variable_name(variable)
    location <- .Call(C_dtatools_mutation_name_location, data, name)
    if (is.null(location)) return(NULL)
    if (!is.na(location)) stop(sprintf("Column `%s` already exists", name), call. = FALSE)
    scalar <- .mutation_scalar_binding(values, data)
    if (is.null(scalar)) return(NULL)
    data <- .prepare_column_growth(data, length(data) + 1L, auto_grow)
    rows <- .mutation_rows(selected$rows, row_count)
    column <- .generated_column(
        scalar$value, rows, row_count, generate = TRUE, carry_metadata = FALSE
    )
    .prepare_column_operation(data, length(data) + 1L)
    .append_generated_column(data, name, column)
    data
}

# Reuse the callback-free scalar lookup used by generation. Expressions that
# need a mask, lazy bindings, and selections that need evaluation retain the
# full view path. A bracket supplies its already evaluated selection once.
.replace_direct_scalar <- function(data, variable, values, where, selection, promote) {
    if (rlang::quo_is_missing(variable) || rlang::quo_is_missing(values)) return(NULL)
    expression <- rlang::quo_get_expr(variable)
    if (!is.symbol(expression) && !.mutation_literal_member(expression)) return(NULL)
    if (!is.null(selection) && !is.null(selection$groups)) return(NULL)
    selected <- .direct_scalar_rows(data, where, selection)
    if (is.null(selected)) return(NULL)
    scalar <- .mutation_scalar_binding(values, data)
    if (is.null(scalar)) return(NULL)
    .Call(C_dtatools_patch_scalar, data, .unquoted_variable_name(variable),
          selected$rows, scalar$value, promote)
}

.direct_scalar_rows <- function(data, where, selection = NULL) {
    if (!is.null(selection)) return(list(rows = selection$rows))
    if (rlang::quo_is_missing(where)) return(NULL)
    if (is.null(rlang::quo_get_expr(where))) return(list(rows = NULL))
    selected <- .mutation_scalar_binding(where, data)
    if (is.null(selected) || !typeof(selected$value) %in% c("integer", "double")) return(NULL)
    list(rows = selected$value)
}

.RUNTIME_NAME_MESSAGE <-
    "`.()` takes one nonempty, non-missing string naming a column"

# `.(name)` reads a column whose name is known only at run time. It is
# recognised in every position dtatools evaluates: in `values` and `where`
# it reads that column, and in the name position it names the target. The
# argument is evaluated in the caller's environment rather than in the data
# mask, so a column sharing a name with a local variable cannot shadow it.
# `.()` is unambiguous here: `.` is not a legal Stata variable name, so no
# column read from a `.dta` file can collide with it. data.table spells
# `list()` as `.()`, but only inside `[.data.table`, which this mask is not.
.is_runtime_name_call <- function(expression) {
    is.call(expression) && identical(expression[[1L]], quote(.))
}

.validated_runtime_name <- function(name) {
    if (!is.character(name) || length(name) != 1L || is.na(name) ||
        !nzchar(name)) {
        stop(.RUNTIME_NAME_MESSAGE, call. = FALSE)
    }
    name
}

.runtime_name_call_value <- function(expression, environment) {
    if (length(expression) != 2L) {
        stop(.RUNTIME_NAME_MESSAGE, call. = FALSE)
    }
    if (!is.environment(environment)) environment <- parent.frame()
    .validated_runtime_name(eval(expression[[2L]], environment))
}

.has_mutation_column <- function(columns, name) {
    if (is.environment(columns)) {
        return(exists(name, envir = columns, inherits = FALSE))
    }
    name %in% names(columns)
}

.mutation_column <- function(columns, name) {
    if (is.environment(columns)) {
        return(get(name, envir = columns, inherits = FALSE))
    }
    columns[[name]]
}

.runtime_name_reader <- function(columns, environment) {
    function(x) {
        name <- .runtime_name_call_value(
            as.call(list(quote(.), substitute(x))), environment
        )
        if (!.has_mutation_column(columns, name)) {
            stop(sprintf("Column `%s` does not exist", name), call. = FALSE)
        }
        .mutation_column(columns, name)
    }
}

# `!!` is the supported escape for a name held in a string. `rlang::enquo()`
# already applies quasiquotation, so `gen(data, !!name, value)` needs no
# `rlang::inject()` wrapper. Unquoting a character string yields a character
# scalar rather than a symbol, which is why one length-one character is
# accepted here alongside a symbol.
#
# `.(name)` reaches the same place and is the one spelling that works in
# every position: `!!` unquotes at capture, so it cannot appear inside a
# larger expression the way `y + .(name)` can.
.unquoted_variable_name <- function(variable) {
    message <- paste(
        "`variable` must be one unquoted column name or one nonempty,",
        "non-missing string"
    )
    if (rlang::quo_is_missing(variable)) stop(message, call. = FALSE)
    expression <- rlang::quo_get_expr(variable)
    if (is.character(expression)) {
        if (length(expression) != 1L || is.na(expression) ||
            !nzchar(expression)) {
            stop(message, call. = FALSE)
        }
        return(expression)
    }
    if (.is_runtime_name_call(expression)) {
        return(.runtime_name_call_value(
            expression, rlang::quo_get_env(variable)
        ))
    }
    if (!is.symbol(expression) || identical(expression, quote(...))) {
        stop(message, call. = FALSE)
    }
    as.character(expression)
}

.mutation_name <- function(variable, generate, data) {
    name <- .unquoted_variable_name(variable)
    location <- match(name, data$names)
    if (generate && !is.na(location)) {
        stop(sprintf("Column `%s` already exists", name), call. = FALSE)
    }
    if (!generate && is.na(location)) {
        stop(sprintf("Column `%s` does not exist", name), call. = FALSE)
    }
    list(name = name, location = location)
}

.formula_expression <- function(value, argument) {
    if (!inherits(value, "formula")) return(NULL)
    if (length(value) != 2L) {
        stop(sprintf("`%s` formulas must be one-sided", argument),
             call. = FALSE)
    }
    list(expression = value[[2L]], environment = environment(value))
}

.plain_mutation_expression <- function(expression) {
    if (is.symbol(expression)) {
        return(!identical(expression, quote(.data)) &&
            !identical(expression, quote(.env)))
    }
    if (rlang::is_quosure(expression)) return(FALSE)
    if (.is_runtime_name_call(expression)) return(FALSE)
    if (is.call(expression) || is.pairlist(expression)) {
        for (index in seq_along(expression)) {
            if (identical(expression[[index]], quote(expr = ))) next
            if (!.plain_mutation_expression(expression[[index]])) {
                return(FALSE)
            }
        }
    }
    TRUE
}

# A bare symbol in `values` or `where` resolves to a column first and to
# the calling environment second, so a local that happens to share a
# column's name is shadowed without a word. When one symbol is bound in
# both places the expression is ambiguous to a reader as well as to the
# evaluator, so it is an error naming the two spellings that are not.
# `.mutate_data()` runs it on `where` before building the fused
# comparison plan, since that plan reads columns without evaluating.
# The environment search runs from the capture frame up to and including
# the global environment, not into attached packages or base, so column
# names like `pi` or `T` do not trip it, and a binding that is a function
# does not count, since a masked symbol reads a vector. `options(
# dtatools.shadow_check = FALSE)` turns the check off.
.SHADOW_CHECK_SKIP <- c(".data", ".env", ".", ".n", ".N")

.masked_symbols <- function(expression, found = character()) {
    if (is.symbol(expression)) {
        name <- as.character(expression)
        if (nzchar(name) && !(name %in% .SHADOW_CHECK_SKIP)) {
            found <- c(found, name)
        }
        return(found)
    }
    if (!is.call(expression)) return(found)
    head <- expression[[1L]]
    if (identical(head, quote(.))) return(found)
    if (identical(head, quote(`$`)) || identical(head, quote(`@`))) {
        return(.masked_symbols(expression[[2L]], found))
    }
    if (identical(head, quote(`~`))) return(found)
    if (identical(head, quote(`function`))) return(found)
    if (identical(head, quote(`::`)) || identical(head, quote(`:::`))) {
        return(found)
    }
    for (index in seq.int(2L, length.out = length(expression) - 1L)) {
        if (identical(expression[[index]], quote(expr = ))) next
        found <- .masked_symbols(expression[[index]], found)
    }
    if (is.call(head)) found <- .masked_symbols(head, found)
    found
}

# A function binding is skipped: a masked symbol reads a vector, and a
# recode script is often named after the column it builds. The walk
# stops after the global environment or at a package namespace, so
# `pi`, `T`, and package constants never count as shadows.
.bound_in_caller_chain <- function(name, environment) {
    while (!identical(environment, emptyenv())) {
        if (identical(environment, baseenv()) || isNamespace(environment)) {
            return(FALSE)
        }
        if (exists(name, envir = environment, inherits = FALSE)) {
            return(!is.function(get(name, envir = environment,
                                    inherits = FALSE)))
        }
        if (identical(environment, globalenv())) return(FALSE)
        environment <- parent.env(environment)
    }
    FALSE
}

.check_shadowed_symbols <- function(expression, columns, environment) {
    if (!is.environment(environment)) return(invisible(NULL))
    if (!isTRUE(getOption("dtatools.shadow_check", TRUE))) {
        return(invisible(NULL))
    }
    symbols <- unique(.masked_symbols(expression))
    if (length(symbols) == 0L) return(invisible(NULL))
    is_column <- if (is.environment(columns)) {
        vapply(
            symbols, exists, logical(1L),
            envir = columns, inherits = FALSE, USE.NAMES = FALSE
        )
    } else {
        symbols %in% names(columns)
    }
    for (name in symbols[is_column]) {
        if (.bound_in_caller_chain(name, environment)) {
            stop(sprintf(paste(
                "`%s` is both a column and an object in the calling",
                "environment; write `.data$%s` for the column or",
                "`.env$%s` for the object"
            ), name, name, name), call. = FALSE)
        }
    }
    invisible(NULL)
}

# `extras` holds the mask variables that are not columns, `.n` and `.N`,
# on the ungrouped path. They are layered in front of the columns rather
# than written into a reference state's column store, so nothing that
# enumerates columns ever sees them. A grouped evaluation binds them in
# its own group environment instead and passes no extras.
.eval_plain_mutation <- function(expression, columns, environment,
                                 extras = NULL) {
    if (!is.environment(columns)) {
        if (is.null(extras)) return(eval(expression, columns, environment))
        # A column list may itself hold a `.n` or `.N` column. Layering the
        # counters in a child frame keeps the columns uniquely named and
        # lets the counters win, as they do on the reference-state path.
        frame <- list2env(extras, new.env(
            parent = list2env(columns, new.env(parent = environment))
        ))
        return(eval(expression, frame))
    }
    previous_parent <- parent.env(columns)
    on.exit(parent.env(columns) <- previous_parent, add = TRUE)
    parent.env(columns) <- environment
    frame <- new.env(parent = columns)
    if (!is.null(extras)) list2env(extras, frame)
    eval(expression, frame)
}

.exposed_mutation_columns <- function(columns) {
    # An arbitrary expression may retain its entire environment before reading
    # any column. Freeze numeric views now. Ordinary physical handles stay in
    # this separate snapshot list, where the final native sharing guard sees
    # their aliases. The internal preflight list can then be released safely.
    lapply(columns, function(column) {
        .Call(C_dtatools_expose_mutation_column, column)
    })
}

# Literal and symbol reads never execute code in a newly created data frame.
# Resolve these directly; every function call receives a complete snapshot.
.mutation_direct_read <- function(expression, columns, environment, extras) {
    if (rlang::is_quosure(expression)) {
        environment <- rlang::quo_get_env(expression)
        expression <- rlang::quo_get_expr(expression)
    }
    if (is.null(expression) || is.atomic(expression)) return(list(value = expression))
    if (is.symbol(expression)) {
        name <- as.character(expression)
        if (!is.null(extras) && name %in% names(extras)) return(list(value = extras[[name]]))
        if (name %in% names(columns)) return(list(value = .metadata_copy(columns[[name]])))
        return(list(value = eval(expression, environment)))
    }
    # The .env pronoun reads only the caller's environment. Its literal member
    # cannot retain the data mask, including when the referenced value is a promise.
    if (is.call(expression) && is.null(attributes(expression)) && length(expression) == 3L &&
        identical(expression[[2L]], quote(.env)) &&
        ((identical(expression[[1L]], quote(`$`)) &&
          (is.symbol(expression[[3L]]) ||
           .mutation_literal_member(expression[[3L]]))) ||
         (identical(expression[[1L]], quote(`[[`)) &&
          .mutation_literal_member(expression[[3L]])))) {
        return(list(value = rlang::eval_tidy(expression, data = list(), env = environment)))
    }
    NULL
}

.eval_in_mutation_data <- function(expression, columns, environment = NULL,
                                   extras = NULL, shadow = TRUE) {
    if (isTRUE(attr(columns, ".dtatools_mutation_views", exact = TRUE))) {
        caller <- if (!is.null(environment)) environment else
            if (rlang::is_quosure(expression)) rlang::quo_get_env(expression) else parent.frame()
        if (shadow) {
            .check_shadowed_symbols(
                if (rlang::is_quosure(expression)) rlang::quo_get_expr(expression) else expression,
                columns, caller
            )
        }
        direct <- .mutation_direct_read(expression, columns, caller, extras)
        if (!is.null(direct)) return(direct$value)
        columns <- .exposed_mutation_columns(columns)
    }
    # Plain expressions -- no `.data`/`.env` pronouns and no embedded
    # quosures -- have identical semantics under base evaluation with the
    # columns masking the expression environment. Skipping the rlang data
    # mask there removes the dominant per-call cost of `gen()`/`repl()`.
    if (is.null(environment)) {
        if (shadow && rlang::is_quosure(expression)) {
            .check_shadowed_symbols(
                rlang::quo_get_expr(expression), columns,
                rlang::quo_get_env(expression)
            )
        }
        if (rlang::is_quosure(expression) &&
            .plain_mutation_expression(rlang::quo_get_expr(expression))) {
            return(.eval_plain_mutation(
                rlang::quo_get_expr(expression), columns,
                rlang::quo_get_env(expression), extras
            ))
        }
    } else {
        if (shadow) .check_shadowed_symbols(expression, columns, environment)
        if (.plain_mutation_expression(expression)) {
            return(.eval_plain_mutation(
                expression, columns, environment, extras
            ))
        }
    }
    reader_environment <- if (!is.null(environment)) {
        environment
    } else if (rlang::is_quosure(expression)) {
        rlang::quo_get_env(expression)
    } else {
        parent.frame()
    }
    if (!is.environment(columns)) {
        mask <- if (is.null(extras)) {
            rlang::as_data_mask(columns)
        } else {
            bottom <- list2env(columns, new.env(parent = emptyenv()))
            rlang::new_data_mask(
                list2env(extras, new.env(parent = bottom)), top = bottom
            )
        }
        if (!is.null(extras)) mask$.data <- rlang::as_data_pronoun(columns)
        mask$. <- .runtime_name_reader(columns, reader_environment)
        return(if (is.null(environment)) {
            rlang::eval_tidy(expression, data = mask)
        } else {
            rlang::eval_tidy(expression, data = mask, env = environment)
        })
    }
    previous_parent <- parent.env(columns)
    on.exit(parent.env(columns) <- previous_parent, add = TRUE)
    mask <- if (is.null(extras)) {
        rlang::new_data_mask(columns)
    } else {
        rlang::new_data_mask(
            list2env(extras, new.env(parent = columns)), top = columns
        )
    }
    mask$.data <- rlang::as_data_pronoun(columns)
    mask$. <- .runtime_name_reader(columns, reader_environment)
    if (is.null(environment)) {
        rlang::eval_tidy(expression, data = mask)
    } else {
        rlang::eval_tidy(expression, data = mask, env = environment)
    }
}

# `all.names()` walks the call in C, so this costs under a microsecond
# on the ungrouped path and lets `.n`/`.N` be built only when mentioned.
# A quosure is a two-element call, so its expression is read directly
# rather than through the slower `rlang::quo_get_expr()`.
.mentions_row_counters <- function(expression) {
    if (inherits(expression, "quosure")) {
        expression <- .subset2(expression, 2L)
    }
    names <- all.names(expression)
    any(names == ".n") || any(names == ".N")
}

# The ungrouped `.n`/`.N` pair, or `NULL` when neither `where` nor
# `values` mentions one. Decided once per call: a stored formula hides
# its body behind a symbol, so `.eval_mutation_expression()` looks again
# when it unwraps one.
.mutation_row_counters <- function(where, values, row_count) {
    names <- c(
        all.names(.subset2(where, 2L)), all.names(.subset2(values, 2L))
    )
    if (!any(names == ".n") && !any(names == ".N")) return(NULL)
    list(.n = seq_len(row_count), .N = row_count)
}

.row_counter_extras <- function(expression, extras, row_count) {
    if (!is.null(extras) || is.null(row_count)) return(extras)
    if (!.mentions_row_counters(expression)) return(NULL)
    list(.n = seq_len(row_count), .N = row_count)
}

# `extras` supplies `.n` and `.N`, for one group or for the whole dataset;
# `row_count` lets a stored formula's body have them built on demand.
.eval_mutation_expression <- function(quo, columns, argument,
                                      extras = NULL, shadow = TRUE,
                                      row_count = NULL) {
    if (rlang::quo_is_missing(quo)) {
        stop(sprintf("`%s` is required", argument), call. = FALSE)
    }
    expression <- rlang::quo_get_expr(quo)
    if (is.call(expression) && identical(expression[[1L]], quote(`~`))) {
        if (length(expression) != 2L) {
            stop(sprintf("`%s` formulas must be one-sided", argument),
                 call. = FALSE)
        }
        return(.eval_in_mutation_data(
            expression[[2L]],
            columns,
            rlang::quo_get_env(quo),
            extras, shadow = FALSE
        ))
    }
    value <- .eval_in_mutation_data(quo, columns, extras = extras,
                                    shadow = shadow)
    formula <- .formula_expression(value, argument)
    if (is.null(formula)) return(value)
    .eval_in_mutation_data(
        formula$expression,
        columns,
        formula$environment,
        .row_counter_extras(formula$expression, extras, row_count),
        shadow = FALSE
    )
}

.fused_comparison_operator <- function(operator) {
    switch(operator,
        "==" = 0L, "!=" = 1L, "<" = 2L, "<=" = 3L,
        ">" = 4L, ">=" = 5L, NULL
    )
}

.fused_comparison_column <- function(expression, columns, row_count) {
    if (!is.symbol(expression)) return(NULL)
    name <- as.character(expression)
    present <- if (is.environment(columns)) {
        exists(name, envir = columns, inherits = FALSE)
    } else {
        name %in% names(columns)
    }
    if (!present) return(NULL)
    value <- columns[[name]]
    sizes <- attr(columns, ".dtatools_mutation_sizes", exact = TRUE)
    size <- if (is.null(sizes)) NA_real_ else sizes[[match(name, names(columns))]]
    if (is.na(size)) size <- length(value)
    if (!inherits(value, "dta_numeric") || size != row_count ||
        !is.null(attr(value, "dim", exact = TRUE))) {
        return(NULL)
    }
    value
}

# `.mutate_data()` has already shadow-checked a non-formula `where` in
# full, and a formula body is exempt, so the operand is not checked here.
.fused_comparison_scalar <- function(expression, columns, environment) {
    # `.N` is a scalar too, but it lives outside the columns; leave that
    # comparison to the general path rather than teach the plan about it.
    if (.mentions_row_counters(expression)) return(NULL)
    value <- .eval_in_mutation_data(expression, columns, environment,
                                    shadow = FALSE)
    if (length(value) != 1L) return(NULL)
    scalar <- .dta_compare_scalar(value)
    if (is.null(scalar)) return(NULL)
    list(value = value, scalar = scalar)
}

.fused_comparison_plan <- function(where, columns, row_count) {
    if (rlang::quo_is_missing(where)) return(NULL)
    expression <- rlang::quo_get_expr(where)
    environment <- rlang::quo_get_env(where)
    if (is.call(expression) && identical(expression[[1L]], quote(`~`))) {
        if (length(expression) != 2L) return(NULL)
        expression <- expression[[2L]]
    }
    if (!is.call(expression) || length(expression) != 3L ||
        !is.symbol(expression[[1L]])) {
        return(NULL)
    }
    operator <- as.character(expression[[1L]])
    op_code <- .fused_comparison_operator(operator)
    if (is.null(op_code)) return(NULL)
    left_column <- .fused_comparison_column(
        expression[[2L]], columns, row_count
    )
    right_column <- .fused_comparison_column(
        expression[[3L]], columns, row_count
    )
    if (is.null(left_column) && is.null(right_column)) return(NULL)
    if (!is.null(left_column) && !is.null(right_column)) {
        if (inherits(left_column, "dta_temporal") &&
            inherits(right_column, "dta_temporal") &&
            !identical(
                .dta_temporal_kind(left_column),
                .dta_temporal_kind(right_column)
            )) {
            return(NULL)
        }
        return(list(
            op = operator, op_code = op_code,
            left = left_column, right = right_column, scalar = NULL,
            original_left = left_column, original_right = right_column
        ))
    }
    if (is.null(left_column)) {
        left_scalar <- .fused_comparison_scalar(
            expression[[2L]], columns, environment
        )
        if (is.null(left_scalar)) return(NULL)
        flipped <- c(0L, 1L, 4L, 5L, 2L, 3L)[[op_code + 1L]]
        return(list(
            op = operator, op_code = flipped,
            left = right_column, right = NULL,
            scalar = left_scalar$scalar,
            original_left = left_scalar$value,
            original_right = right_column
        ))
    }
    right_scalar <- .fused_comparison_scalar(
        expression[[3L]], columns, environment
    )
    if (is.null(right_scalar)) return(NULL)
    list(
        op = operator, op_code = op_code,
        left = left_column, right = NULL, scalar = right_scalar$scalar,
        original_left = left_column, original_right = right_scalar$value
    )
}

.fused_comparison_value <- function(plan) {
    # The plan already has validated sizes and a normalized scalar. Keep its
    # internal read handles inside native code, including for owned doubles.
    native <- .Call(C_dtatools_dta_compare, plan$op_code, plan$left,
                    plan$right, plan$scalar, .mutation_threads())
    if (!is.null(native)) return(native)
    # Unsupported operands can enter user-defined R methods. Fork handles at
    # that boundary, so retaining an operand cannot observe a later table write.
    .dta_compare(plan$op, .metadata_copy(plan$original_left),
                 .metadata_copy(plan$original_right))
}

.fused_replacement_plan <- function(values, target, row_count) {
    native_numeric <- inherits(target, "dta_numeric") &&
        !inherits(target, "dta_temporal") &&
        typeof(values) %in% c("logical", "integer", "double") &&
        (!is.object(values) || inherits(values, "dta_numeric"))
    native_temporal <- inherits(target, "dta_temporal") &&
        ((inherits(target, "dta_date") && inherits(values, "Date")) ||
         (inherits(target, "dta_datetime") &&
          inherits(values, "POSIXct")))
    if ((!native_numeric && !native_temporal) || is.factor(values) ||
        !is.null(dim(values))) {
        return(NULL)
    }
    size <- vctrs::vec_size(values)
    if (size == 1L) {
        scalar <- .dta_compare_scalar(values)
        if (is.null(scalar)) return(NULL)
        return(list(values = NULL, scalar = scalar))
    }
    if (size == row_count && typeof(values) == "double") {
        return(list(values = values, scalar = NULL))
    }
    NULL
}

.mutation_threads <- function() {
    threads <- getOption("dtatools.threads", 0L)
    if (!is.numeric(threads) || length(threads) != 1L || is.na(threads) ||
        threads < 0) {
        return(0L)
    }
    as.integer(threads)
}

.mutation_rows <- function(value, row_count) {
    if (is.null(value)) return(NULL)
    classified <- if (inherits(value, .dta_metadata_vector_class)) {
        .dta_metadata_vector_base(value)
    } else value
    dta_positions <- inherits(classified, "dta_numeric") &&
        !inherits(classified, "dta_temporal")
    if (!is.null(dim(classified)) ||
        (!is.logical(classified) &&
         (!is.numeric(classified) ||
          (is.object(classified) && !dta_positions)))) {
        stop("`where` must yield logical values or numeric row positions",
             call. = FALSE)
    }
    .Call(C_dtatools_mutation_rows, classified, as.double(row_count))
}

.mutation_selected_count <- function(rows, row_count) {
    if (is.null(rows)) row_count else length(rows)
}

# `group` names the group whose sizes are being checked, so a grouped
# error points at the offending key values instead of the whole dataset.
.mutation_value_mode <- function(values, rows, row_count, group = NULL) {
    size <- vctrs::vec_size(values)
    selected <- .mutation_selected_count(rows, row_count)
    if (size == 1L) return("scalar")
    if (!is.null(rows) && size == row_count) return("row")
    if (size == selected || (selected == 0L && size == 0L)) {
        return("selected")
    }
    if (is.null(group)) {
        stop(sprintf(
            paste0(
                "`values` has size %s; expected size 1, the selected-row ",
                "count (%s), or the data row count (%s)"
            ),
            size, selected, row_count
        ), call. = FALSE)
    }
    stop(sprintf(
        paste0(
            "`values` has size %s in group %s; expected size 1, the ",
            "group's selected-row count (%s), or the group's row count (%s)"
        ),
        size, group, selected, row_count
    ), call. = FALSE)
}

# Group-wise assignment follows Stata's `by varlist:` rather than
# data.table's `by`: the groups are formed first, then `where` and
# `values` are evaluated on each group's rows, so `.N` is the group's row
# count even under a `where` that selects only some of its rows.
# data.table applies `i` first and groups only the surviving rows. The
# groups come from `by`, from `bysort`, or from the dplyr grouping of a
# `grouped_df`; combining the two sources is an error rather than a
# precedence rule. The plan is `.assignment_groups()`, which `egen()`
# shares; `bysort`'s sort is applied by the first successful commit
# (`.apply_group_order()`). Each group's selection and values are
# gathered into one row vector and one value vector and handed to the
# ungrouped write path, so storage validation, compact patching, and
# transactions are shared rather than duplicated.
.MUTATION_GROUPED_MESSAGE <-
    "`data` is already grouped; drop `by`/`bysort` or ungroup"

.mutation_group_expression <- function(expression, environment, argument) {
    message <- sprintf(paste(
        "`%s` must be column names: a bare name, a string, `c()` of",
        "those, `!!name`, or `.(name)`"
    ), argument)
    if (is.symbol(expression)) return(as.character(expression))
    if (is.character(expression)) {
        if (anyNA(expression) || !all(nzchar(expression))) {
            stop(message, call. = FALSE)
        }
        return(expression)
    }
    if (.is_runtime_name_call(expression)) {
        return(.runtime_name_call_value(expression, environment))
    }
    if (is.call(expression) &&
        .selection_call_is(expression[[1L]], "c", "base")) {
        return(unlist(lapply(
            as.list(expression)[-1L], .mutation_group_expression,
            environment = environment, argument = argument
        ), use.names = FALSE))
    }
    stop(message, call. = FALSE)
}

.mutation_group_names <- function(quo, columns, argument) {
    names <- .mutation_group_expression(
        rlang::quo_get_expr(quo), rlang::quo_get_env(quo), argument
    )
    if (length(names) == 0L) {
        stop(sprintf("`%s` must name at least one column", argument),
             call. = FALSE)
    }
    for (name in names) {
        if (!.has_mutation_column(columns, name)) {
            stop(sprintf("Column `%s` does not exist", name), call. = FALSE)
        }
    }
    if (anyDuplicated(names)) {
        stop(sprintf("`%s` must name unique columns", argument), call. = FALSE)
    }
    names
}

# Names one group in an error the way Stata prints it: missing codes as
# `.`, `.a`, and so on, strings in quotes.
.mutation_group_label <- function(keys, index) {
    parts <- vapply(names(keys), function(name) {
        piece <- vctrs::vec_slice(keys[[name]], index)
        text <- if (inherits(piece, "dta_numeric")) {
            code <- .tab_missing_codes(as.double(piece))
            if (!is.na(code)) .tab_missing_name(code) else
                format(as.double(piece))
        } else if (is.character(piece)) {
            encodeString(piece, quote = "\"")
        } else if (is.numeric(piece) && is.na(piece)) {
            "."
        } else {
            format(piece)
        }
        paste0(name, " = ", text)
    }, character(1L))
    paste(parts, collapse = ", ")
}

.mutation_group_slice <- function(column, rows) {
    # The vctrs fallback may invoke an R proxy that retains its input. Native
    # compact and declared-double gathering cannot expose that full read view.
    if (!.dta_merge_has_compact_storage(column) &&
        !identical(.declared_dta_storage(column), "double")) {
        column <- .Call(C_dtatools_expose_mutation_column, column)
    }
    .dta_merge_slice(column, rows, fill_string_missing = FALSE)
}

# A column view over one group at a time. Every column is an active
# binding that slices the full column to the current group's rows on
# first use and caches the slice until the group changes, so an
# expression pays for the columns it reads and nothing else, and a
# runtime name through `.data[[name]]` or `.(name)` still resolves.
.mutation_group_view <- function(columns) {
    if (isTRUE(attr(columns, ".dtatools_mutation_views", exact = TRUE))) {
        columns <- .exposed_mutation_columns(columns)
    }
    view <- new.env(parent = emptyenv())
    view$rows <- integer()
    view$cache <- new.env(hash = TRUE, parent = emptyenv())
    view$columns <- new.env(hash = TRUE, parent = emptyenv())
    column_names <- if (is.environment(columns)) {
        ls(columns, all.names = TRUE, sorted = FALSE)
    } else {
        names(columns)
    }
    for (name in column_names) {
        local({
            column_name <- name
            makeActiveBinding(column_name, function(value) {
                if (!missing(value)) {
                    stop(
                        "columns cannot be assigned inside `values` or `where`",
                        call. = FALSE
                    )
                }
                hit <- view$cache[[column_name]]
                if (is.null(hit)) {
                    hit <- .mutation_group_slice(
                        .mutation_column(columns, column_name), view$rows
                    )
                    view$cache[[column_name]] <- hit
                }
                hit
            }, view$columns)
        })
    }
    view
}

# The `where` half of `.grouped_mutation()` on its own: each group's rows
# as validated group-relative positions, or `NULL` for the whole group.
# The bracket form calls it once and hands the result to every assignment
# in the same `j`, so rows are chosen before any assignment writes.
.grouped_selection <- function(where, columns, groups) {
    view <- .mutation_group_view(columns)
    lapply(seq_along(groups$rows), function(index) {
        rows <- groups$rows[[index]]
        size <- length(rows)
        if (size == 0L) return(NULL)
        view$rows <- rows
        view$cache <- new.env(hash = TRUE, parent = emptyenv())
        selected <- .eval_mutation_expression(
            where, view$columns, "where",
            list(.n = seq_len(size), .N = size), shadow = FALSE
        )
        .mutation_rows(selected, size)
    })
}

# Evaluates `where` and `values` once per group and gathers the results
# into one selected-row vector and one aligned value vector for the
# shared write path. Duplicate positions from a numeric `where` keep the
# last value, as the ungrouped path does; when every row is selected the
# values are put into row order and `rows` becomes `NULL`, so the native
# writers see the same plain full-column write as an ungrouped call.
# `selected` is a `.grouped_selection()` result; when given, `where` is
# not evaluated again.
.grouped_mutation <- function(where, values, columns, groups, row_count,
                              selected = NULL, drop_unselected = FALSE,
                              generate = FALSE) {
    view <- .mutation_group_view(columns)
    count <- length(groups$rows)
    row_pieces <- vector("list", count)
    value_pieces <- vector("list", count)
    kept <- logical(count)
    first <- TRUE
    for (index in seq_len(count)) {
        rows <- groups$rows[[index]]
        size <- length(rows)
        if (size == 0L) next
        kept[[index]] <- TRUE
        view$rows <- rows
        view$cache <- new.env(hash = TRUE, parent = emptyenv())
        extras <- list(.n = seq_len(size), .N = size)
        group_rows <- if (is.null(selected)) {
            .mutation_rows(.eval_mutation_expression(
                where, view$columns, "where", extras, shadow = FALSE
            ), size)
        } else {
            selected[[index]]
        }
        evaluated <- .eval_mutation_expression(
            values, view$columns, "values", extras, shadow = first
        )
        first <- FALSE
        mode <- .mutation_value_mode(
            evaluated, group_rows, size,
            group = .mutation_group_label(groups$keys, index)
        )
        if (is.null(group_rows)) {
            positions <- seq_len(size)
        } else if (inherits(group_rows, "dta_numeric")) {
            positions <- as.integer(.dta_data(group_rows))
        } else {
            positions <- as.integer(group_rows)
        }
        if (drop_unselected && length(positions) == 0L) {
            kept[[index]] <- FALSE
            next
        }
        piece <- switch(mode,
            scalar = vctrs::vec_recycle(evaluated, length(positions)),
            row = vctrs::vec_slice(evaluated, positions),
            selected = evaluated
        )
        row_pieces[index] <- list(rows[positions])
        # A generated column keeps none of its pieces' variable metadata
        # (ADR 0039), so it comes off each piece here, before the pieces
        # are gathered, and two groups whose columns carry different value
        # labels do not raise a conflict over labels the result drops.
        if (generate && !is.null(piece)) piece <- .generate_value(piece)
        # Single-bracket assignment keeps a `NULL` piece, which a group
        # that selects no rows and evaluates `values` to `NULL` produces.
        value_pieces[index] <- list(piece)
    }
    # `.drop = FALSE` grouping can carry empty groups; they contribute
    # nothing. A dataset with rows always has at least one nonempty group.
    row_pieces <- row_pieces[kept]
    value_pieces <- value_pieces[kept]
    if (!length(value_pieces)) return(list(rows = integer(), values = NULL))
    all_rows <- unlist(row_pieces, use.names = FALSE)
    gathered <- .mutation_gather_values(value_pieces)
    if (anyDuplicated(all_rows) > 0L) {
        last <- !duplicated(all_rows, fromLast = TRUE)
        all_rows <- all_rows[last]
        gathered <- vctrs::vec_slice(gathered, last)
    }
    order <- order(all_rows)
    all_rows <- all_rows[order]
    gathered <- vctrs::vec_slice(gathered, order)
    if (length(all_rows) == row_count) {
        return(list(rows = NULL, values = gathered))
    }
    list(rows = all_rows, values = gathered)
}

# A replacement that rewrote a grouping column leaves the `grouped_df`
# metadata describing the old values. Rebuild it in place from the
# current columns, keeping the `.drop` setting, so a following dplyr verb
# or `.N` assignment partitions the rows the way the data now reads.
.regroup_after_replacement <- function(data) {
    groups <- .build_group_metadata(.data_columns(data), .group_vars(data),
                                    nrow(data), drop = .group_drop_default(data))
    .Call(C_dtatools_set_attribute, data, "groups", groups)
    invisible(NULL)
}

# `list_unchop()` finds the common type of the pieces but drops bare
# attributes such as a variable label; restore them when every piece
# agrees, so a grouped `gen()` keeps the label an ungrouped one would.
.mutation_gather_values <- function(pieces) {
    result <- vctrs::list_unchop(pieces)
    first <- attributes(pieces[[1L]])
    first$names <- NULL
    if (length(first) == 0L) return(result)
    # A classed result, such as a factor or a Stata vector, keeps the
    # attributes of its common type; the pieces' own are restored only
    # when they agree and describe that same class, which is how a
    # factor's variable label survives a grouped `gen()`.
    if (is.object(result) && !identical(first$class, class(result))) {
        return(result)
    }
    for (piece in pieces[-1L]) {
        other <- attributes(piece)
        other$names <- NULL
        if (!identical(other, first)) return(result)
    }
    attributes(result) <- first
    result
}

.validate_numeric_values <- function(values) {
    if (!(typeof(values) %in% c("logical", "integer", "double")) ||
        is.factor(values) || !is.null(dim(values))) return(invisible(NULL))
    if (typeof(values) == "double") {
        codes <- .tab_missing_codes(values)
        invalid <- (!is.na(codes) & codes == 256L) | is.infinite(values)
        if (any(invalid)) {
            stop(paste0(
                "`values` cannot contain `NaN` or infinities; use ",
                "`NA_real_` for Stata system missing"
            ), call. = FALSE)
        }
    }
    invisible(NULL)
}

.cast_replacement <- function(values, target, rows, value_mode) {
    if (is.factor(target) || !is.null(attr(target, "dim", exact = TRUE)) ||
        !(typeof(target) %in% c("logical", "integer", "double", "character"))) {
        stop("The target column has an unsupported replacement type",
             call. = FALSE)
    }
    native_numeric <- inherits(target, "dta_numeric") &&
        !inherits(target, "dta_temporal") &&
        typeof(values) %in% c("logical", "integer", "double") &&
        (!is.object(values) || inherits(values, "dta_numeric"))
    native_temporal <- inherits(target, "dta_temporal") &&
        ((inherits(target, "dta_date") && inherits(values, "Date")) ||
         (inherits(target, "dta_datetime") &&
          inherits(values, "POSIXct")))
    if ((.is_unmaterialized_numeric_altrep(target) ||
         .is_materialized_numeric_altrep(target) ||
         .Call(C_dtatools_is_owned_double, target)) &&
        (native_numeric || native_temporal) &&
        !is.factor(values) && is.null(dim(values))) {
        # The native patcher validates and encodes these values directly for
        # the target's declared storage. Going through vec_cast() would build
        # a replacement compact column or owned scalar and, for ordinary input,
        # a full double temporary before decoding it again.
        return(values)
    }
    if (typeof(target) == "character" &&
        .is_unmaterialized_dictstring(values)) {
        # Native reads leave the shared source cache unchanged. R-level string
        # operations would populate it before the mutation can commit.
        return(values)
    }
    # Fallback casts and string-width checks apply only to selected values.
    # Direct compact targets gather the same full vector in native code above.
    if (identical(value_mode, "row")) {
        slice_rows <- if (inherits(rows, "dta_numeric")) {
            .dta_data(rows)
        } else {
            rows
        }
        values <- vctrs::vec_slice(values, slice_rows)
    }
    # `replace_values()` normalizes character `NA` to `""`, Stata's string
    # missing, before the cast, which refuses `NA` for a declared string.
    # After slicing, so a sparse replacement scans only its selected rows.
    if (typeof(target) == "character" && typeof(values) == "character" &&
        !is.object(values)) {
        values <- .stata_string_text(values)
    }
    .validate_numeric_values(values)
    # Build Stata prototypes from metadata rather than proxying the target.
    # A real metadata copy must revoke exclusive patch ownership; this internal
    # cast must not.
    prototype <- if (inherits(target, "dta_temporal")) {
        .dta_temporal_ptype(.declared_dta_storage(target), target)
    } else if (inherits(target, "dta_numeric")) {
        .dta_ptype(.declared_dta_storage(target), target)
    } else if (inherits(target, "dta_string")) {
        # Built from the declaration and metadata alone: subsetting a
        # metadata copy of a dictionary-backed column would decode and copy
        # the whole column to produce an empty prototype.
        .new_dta_string(character(),
            .declared_string_storage(target), target)
    } else {
        # A supported owned prototype needs attributes, not the target values.
        # Forking its full read view would make every later private write copy.
        empty <- .Call(C_dtatools_mutation_prototype, target)
        if (is.null(empty)) .metadata_copy(target)[integer()] else empty[integer()]
    }
    result <- vctrs::vec_cast(values, prototype)
    .validate_numeric_values(result)
    result
}

# The shadow check for `where`. A formula body is exempt: `~` asks for the
# data mask outright.
.check_where_shadowing <- function(where, columns) {
    if (rlang::quo_is_missing(where) ||
        rlang::is_formula(rlang::quo_get_expr(where))) {
        return(invisible(NULL))
    }
    .check_shadowed_symbols(
        rlang::quo_get_expr(where), columns, rlang::quo_get_env(where)
    )
}

# `where` as a row plan: per group when `groups` is given, so `.n` and
# `.N` are each group's, and otherwise one native-normalized selection
# for the whole dataset. `extras` supplies `.n` and `.N` for the
# ungrouped evaluation; a caller that also evaluates `values` passes the
# counters both share.
.resolve_where_rows <- function(where, columns, groups, row_count, extras) {
    if (!is.null(groups)) {
        return(list(
            rows = NULL,
            group_rows = .grouped_selection(where, columns, groups)
        ))
    }
    selected <- .eval_mutation_expression(
        where, columns, "where", extras, row_count = row_count
    )
    list(rows = .mutation_rows(selected, row_count), group_rows = NULL)
}

# Selects the rows of one bracket call, `data[i, j, by]`, before any of
# its assignments writes: `i` is evaluated once, with the shadow check
# and `.n`/`.N` of `where`, and the groups it was evaluated under are
# kept so each assignment reuses them. The result is `.mutate_data()`'s
# `selection`. The group plan is made here, once, and `bysort` sorts the
# dataset here, before `i` is evaluated; the bracket undoes the sort
# through `staged` if the call fails before its first write. The private
# views taken here serve this evaluation only; each assignment opens its
# own.
.mutation_selection <- function(data, where, by, bysort, staged) {
    grouped_input <- inherits(data, "grouped_df")
    if (!grouped_input && is.null(by) && is.null(bysort)) {
        row_count <- .Call(C_dtatools_fast_shape, data)
        if (!is.null(row_count)) {
            selected <- .direct_scalar_rows(data, where)
            if (!is.null(selected)) return(list(
                groups = NULL, rows = .mutation_rows(selected$rows, row_count),
                group_rows = NULL
            ))
        }
    }
    original <- .as_mutation_data(
        data, allow_grouped = TRUE, allow_rowwise = FALSE, private_views = TRUE
    )
    on.exit(.Call(C_dtatools_release_mutation_views, original$columns), add = TRUE)
    groups <- if (grouped_input || !is.null(by) || !is.null(bysort)) {
        .assignment_groups(data, original, by, bysort, grouped_input)
    } else {
        NULL
    }
    if (!is.null(groups) && .apply_group_order(groups, data, staged)) {
        # The sort permuted every column by reference; the views taken
        # before it are stale, so release them and open new ones.
        .Call(C_dtatools_release_mutation_views, original$columns)
        original <- .as_mutation_data(
            data, allow_grouped = TRUE, allow_rowwise = FALSE, private_views = TRUE
        )
    }
    .check_where_shadowing(where, original$columns)
    selected <- .resolve_where_rows(
        where, original$columns, groups, original$nrow,
        .row_counter_extras(where, NULL, original$nrow)
    )
    list(groups = groups, rows = selected$rows, group_rows = selected$group_rows)
}

# One assignment, in three steps. `.mutate_data()` opens the target:
# the sharing snapshot, the private views, the target name, capacity, and
# the group plan. `.resolve_mutation()` reads the views and settles what
# to write, `rows`, `values`, and their `value_mode`, without touching
# the table. The commit helpers write: the fused adapter, the
# generated-column append, or the replacement, which chooses promotion
# or a cast. `bysort` sorts before the resolve step and a failure before
# the commit undoes the sort. Nothing after the resolve step evaluates
# user code, and nothing before the commit writes.
#
# `selection` is a `.mutation_selection()` result. When given, `where` is
# not evaluated again and the groups it carries stand in for `by` and
# `bysort`, so every assignment in one `data[i, j]` writes to the rows
# `i` chose before the first of them wrote. `where` still arrives so
# `values` can be given `.n` and `.N` on the same terms. `staged` is the
# bracket's `bysort` undo state, disarmed by its first write.
.mutate_data <- function(data, variable, values, where, generate,
                         by = NULL, bysort = NULL, selection = NULL,
                         promote = FALSE, report_promotion = FALSE,
                         entry_shared = NULL, auto_grow = FALSE,
                         staged = NULL, placement = NULL) {
    if (!generate && is.null(by) && is.null(bysort) &&
        !inherits(data, "grouped_df") && is.null(staged$restore)) {
        direct <- .replace_direct_scalar(data, variable, values, where, selection, promote)
        if (!is.null(direct)) return(invisible(direct))
    }
    if (generate && is.null(by) && is.null(bysort) &&
        is.null(placement) && is.null(staged$restore)) {
        direct <- .generate_direct_scalar(data, variable, values, where, auto_grow, selection)
        if (!is.null(direct)) return(invisible(direct))
    }
    # Inspect before masks and snapshots add temporary column references.
    shared <- if (!is.null(entry_shared)) entry_shared else
        if (is.data.frame(data)) .Call(C_dtatools_shared_columns, data) else NULL
    grouped_input <- inherits(data, "grouped_df")
    original <- .as_mutation_data(
        data, allow_grouped = TRUE, allow_rowwise = FALSE, private_views = TRUE
    )
    # An error or interrupt before the commit releases the views too; the
    # native release is a no-op on a list released before the commit.
    on.exit(.Call(C_dtatools_release_mutation_views, original$columns), add = TRUE)
    target <- .mutation_name(variable, generate, original)
    if (generate) {
        grown <- .grow_mutation_target(data, original, length(data) + 1L,
                                       auto_grow, private_views = TRUE)
        data <- grown$data
        original <- grown$original
    } else {
        .prepare_column_operation(data, length(data))
    }
    groups <- if (!is.null(selection)) {
        selection$groups
    } else if (grouped_input || !is.null(by) || !is.null(bysort)) {
        .assignment_groups(data, original, by, bysort, grouped_input)
    } else {
        NULL
    }
    # `bysort` sorts before `where` and `values` are evaluated, so they
    # see the sorted dataset. The sort permuted every column by
    # reference, so the views are reopened on the sorted table. Any exit
    # from the sort until the write commits, an error, an interrupt, or
    # a restart, puts the columns back, so the call changes nothing. The
    # undo runs on exit, not from a condition handler: a handler would
    # also run for a signalled condition evaluation resumes from, and
    # undo a sort still in use, while the exit hook runs only when the
    # call unwinds, and lets the condition continue unchanged, so a user
    # interrupt stays an interrupt. The write and the disarming of the
    # undo are one uninterruptible step, since a column appended in
    # sorted order cannot be left on a restored table. A bracket call
    # sorted in its selection and hands its `staged` down so its first
    # assignment disarms the same way.
    if (is.null(staged)) staged <- new.env(parent = emptyenv())
    completed <- FALSE
    on.exit(if (!completed) .undo_group_order(data, staged), add = TRUE)
    write <- function() {
        if (generate) {
            .commit_generated_column(data, target, resolved, original$nrow,
                                     placement)
        } else {
            .commit_replacement(data, original, target, resolved, shared,
                                promote, report_promotion, grouped_input)
        }
        .disarm_group_order(staged)
    }
    {
        if (is.null(selection) && !is.null(groups) &&
            .apply_group_order(groups, data, staged)) {
            .Call(C_dtatools_release_mutation_views, original$columns)
            original <- .as_mutation_data(
                data, allow_grouped = TRUE, allow_rowwise = FALSE,
                private_views = TRUE
            )
        }
        resolved <- .resolve_mutation(
            where, values, original$columns, groups, selection, target,
            original$nrow, generate
        )
        if (identical(resolved$kind, "fused")) {
            # Only an ungrouped assignment resolves to a fused plan, so no
            # sort is staged here.
            if (.commit_fused_patch(data, target$location, shared[[target$location]],
                                    resolved$fused, resolved$replacement)) {
                completed <- TRUE
                return(invisible(data))
            }
            resolved <- .resolve_fused_fallback(resolved, original$nrow)
        }
        if (is.null(staged$restore)) write() else suspendInterrupts(write())
    }
    completed <- TRUE
    invisible(data)
}

# What one assignment writes, read from the private `columns` without
# writing to the table. A `"plain"` result carries `rows`, `values`, and
# `value_mode`. A `"fused"` result carries the comparison and replacement
# plans for the fused adapter instead: the comparison is not evaluated
# here, because a successful fused patch never needs its rows. Groups take
# `.grouped_mutation()`'s gathered rows and values, a bracket `selection`
# supplies its rows, and the fused plan is attempted only for an ungrouped
# replacement with no selection made up front, since the native patch
# reads the whole target column.
.resolve_mutation <- function(where, values, columns, groups, selection,
                              target, row_count, generate) {
    if (is.null(selection)) .check_where_shadowing(where, columns)
    if (!is.null(groups)) {
        gathered <- .grouped_mutation(
            where, values, columns, groups, row_count,
            selected = selection$group_rows, drop_unselected = !generate,
            generate = generate
        )
        return(.resolved_assignment(
            gathered$values, .mutation_rows(gathered$rows, row_count), row_count
        ))
    }
    extras <- .mutation_row_counters(where, values, row_count)
    if (!is.null(selection)) {
        evaluated <- .eval_mutation_expression(
            values, columns, "values", extras, row_count = row_count
        )
        return(.resolved_assignment(evaluated, selection$rows, row_count))
    }
    fused <- if (generate) NULL else {
        .fused_comparison_plan(where, columns, row_count)
    }
    if (is.null(fused)) {
        selected <- .resolve_where_rows(where, columns, NULL, row_count, extras)
        evaluated <- .eval_mutation_expression(
            values, columns, "values", extras, row_count = row_count
        )
        return(.resolved_assignment(evaluated, selected$rows, row_count))
    }
    evaluated <- .eval_mutation_expression(
        values, columns, "values", extras, row_count = row_count
    )
    column <- columns[[target$location]]
    replacement <- if (.is_unmaterialized_numeric_altrep(column)) {
        .fused_replacement_plan(evaluated, column, row_count)
    } else NULL
    if (is.null(replacement)) {
        return(.resolved_assignment(
            evaluated, .mutation_rows(.fused_comparison_value(fused), row_count),
            row_count
        ))
    }
    list(kind = "fused", values = evaluated, fused = fused,
         replacement = replacement)
}

# `rows` is already native-normalized: `NULL` for every row, else positions.
.resolved_assignment <- function(values, rows, row_count) {
    list(
        kind = "plain", rows = rows, values = values,
        value_mode = .mutation_value_mode(values, rows, row_count)
    )
}

# The rows of a fused plan the native patch declined, evaluated the way
# an ungrouped `where` is, so the replacement commits through the
# ordinary path with the values already evaluated.
.resolve_fused_fallback <- function(resolved, row_count) {
    .resolved_assignment(
        resolved$values,
        .mutation_rows(.fused_comparison_value(resolved$fused), row_count),
        row_count
    )
}

# The fused adapter: one native call compares and patches a compact
# numeric target for a simple comparison and a scalar or full-length
# value. `TRUE` when it wrote; `FALSE` when the native code declined and
# the caller falls back to the ordinary replacement.
.commit_fused_patch <- function(data, location, shared, fused, replacement) {
    patched <- .Call(
        C_dtatools_fused_patch_slot,
        data, as.integer(location), shared,
        fused$op_code, fused$left, fused$right,
        fused$scalar, replacement$values,
        replacement$scalar, .mutation_threads()
    )
    !is.null(patched)
}

# Builds the new column from the resolved rows and values and appends
# it; the append and the reference remark run as one uninterruptible step.
.commit_generated_column <- function(data, target, resolved, row_count,
                                     placement = NULL) {
    # Resolved against the names the table has now, not the ones read on
    # entry: a `values` expression that mutated this table may have moved
    # or removed the anchor, and one that is gone stops the call here.
    names <- attr(data, "names", exact = TRUE)
    column_order <- .mutation_placement(placement, names, target$name)
    column <- .generated_column(
        resolved$values, resolved$rows, row_count, generate = TRUE,
        carry_metadata = FALSE
    )
    .prepare_column_operation(data, length(data) + 1L)
    if (is.null(column_order)) {
        .append_generated_column(data, target$name, column)
    } else {
        .insert_generated_column(data, target$name, column, column_order, row_count)
    }
}

# Installs the new column beside its `before` or `after` anchor in the one
# native commit `order_vars()` uses, on the complete column list with the
# new column in place, so no observer sees it appended and then moved. The
# columns are read plainly, without dispatch, from the prepared table.
.insert_generated_column <- function(data, name, column, column_order, row_count) {
    columns <- .data_columns(data)
    columns[[name]] <- column
    suspendInterrupts(
        .install_column_selection(data, list(nrow = row_count), columns[column_order])
    )
    invisible(NULL)
}

.append_generated_column <- function(data, name, column) {
    suspendInterrupts({
        if (!.Call(C_dtatools_append_data_column, data, name, column)) {
            stop("internal error: prepared table cannot append a column")
        }
        .mark_fresh_reference(data)
    })
    invisible(NULL)
}

# Writes resolved values into an existing column: a storage promotion
# replaces the whole column, and otherwise the values are cast to the
# target's declared storage and patched in place. The target view is
# read here and dropped before the native patch; `shared` says whether
# the slot must detach from other tables first.
.commit_replacement <- function(data, original, target, resolved, shared,
                                promote, report_promotion, grouped_input) {
    rows <- resolved$rows
    values <- resolved$values
    value_mode <- resolved$value_mode
    column <- original$columns[[target$location]]
    # An assignment that selects no rows changes nothing and returns
    # here: it neither declares storage nor promotes. Stata's
    # `replace` behaves the same way, reporting `(0 real changes
    # made)` and leaving the storage alone, so `repl()` takes this
    # path as `:=` does.
    if (promote &&
        .mutation_selected_count(rows, original$nrow) == 0L) {
        return(invisible(NULL))
    }
    declared <- if (promote) {
        .wider_declared_storage(values, column)
    } else {
        NULL
    }
    if (!is.null(declared) ||
        (promote &&
         !.replacement_fits(values, column, rows, value_mode))) {
        # Promotion widens storage; it admits no value Stata cannot
        # hold at any width, and says so as `repl()` does.
        .validate_numeric_values(values)
        # `:=` promotes: the column is rebuilt at the storage the
        # right-hand side declares when that is wider, and otherwise
        # at the narrowest storage that holds the current and new
        # values together.
        promoted <- .promoted_replacement(
            values, column, rows, value_mode, original$nrow, declared
        )
        if (report_promotion) {
            .report_storage_promotion(target$name, column, promoted)
        }
        .set_data_column_at(.column_access(data), target$location, promoted)
        if (grouped_input) .regroup_after_replacement(data)
        return(invisible(NULL))
    }
    replacement <- .cast_replacement(values, column, rows, value_mode)
    # No selected group supplied a value. vctrs accepts NULL here, but
    # the native patcher requires a vector even for an empty selection.
    if (is.null(replacement) &&
        .mutation_selected_count(rows, original$nrow) == 0L) {
        return(invisible(NULL))
    }
    if (is.null(rows) && .is_unmaterialized_dictstring(column) &&
        .same_mutation_object(column, replacement)) return(invisible(NULL))
    # Evaluation and casting are complete. Release the internal read list
    # and the local target before the patch, which may detach the slot's
    # backing; callbacks' independent aliases remain live.
    .Call(C_dtatools_release_mutation_views, original$columns)
    column <- NULL
    .Call(
        C_dtatools_patch_slot, data, as.integer(target$location),
        rows, replacement, shared[[target$location]]
    )
    # Rebuild after every grouped replacement, not only one that names
    # a grouping column: a target can share its vector with a key
    # under the package's alias semantics, so the key may have changed
    # without being named.
    if (grouped_input) .regroup_after_replacement(data)
    invisible(NULL)
}

# Preserve aliases within the supplied table while detaching its payload
# from other tables. Every binding of the table observes the pointer commit.
.mutation_copy <- function(column) {
    # A write must detach the payload now. Return a native compact numeric
    # object so later Date/as.double methods keep their compact-read behavior.
    if (.is_unmaterialized_numeric_altrep(column)) .deep_copy_value(column) else .metadata_copy(column)
}

.aliased_column_names <- function(data, column) {
    address <- rlang::obj_address(column)
    matches <- vapply(seq_along(data), function(index) {
        identical(rlang::obj_address(.subset2(data, index)), address)
    }, logical(1))
    names(data)[matches]
}

.commit_detached_column <- function(data, before, after) {
    locations <- match(.aliased_column_names(data, before), names(data))
    # Validate and stage the complete plan before a native commit that cannot
    # allocate or be interrupted between same-vector column slots.
    .Call(C_dtatools_replace_reference_columns, data, NULL, locations,
          rep(NA_character_, length(locations)), rep(list(after), length(locations)))
    invisible(NULL)
}

.generated_numeric_class_supported <- function(values) {
    if (inherits(values, .dta_metadata_vector_class)) {
        values <- .dta_metadata_vector_base(values)
    }
    if (!is.object(values) || inherits(values, "dta_numeric")) return(TRUE)
    classes <- class(values)
    if (inherits(values, "Date")) {
        return(all(classes %in% "Date"))
    }
    if (inherits(values, "POSIXct")) {
        return(all(classes %in% c("POSIXct", "POSIXt")))
    }
    inherits(values, "haven_labelled") &&
        all(classes %in% c("haven_labelled", "vctrs_vctr", typeof(values)))
}

.generated_numeric <- function(values, rows, row_count, caller = "gen()",
                               generate = FALSE) {
    if (!.generated_numeric_class_supported(values)) {
        stop(sprintf(
            paste(
                "`%s` does not support this classed numeric result;",
                "convert it explicitly"
            ),
            caller
        ), call. = FALSE)
    }
    declared <- .declared_dta_storage(values)
    base_date <- inherits(values, "Date") &&
        !inherits(values, "dta_temporal")
    base_datetime <- inherits(values, "POSIXct") &&
        !inherits(values, "dta_temporal")
    temporal <- inherits(values, "dta_temporal") ||
        base_date || base_datetime
    storage <- if (!is.null(declared)) {
        declared
    } else if (base_datetime) {
        # Stata datetimes are millisecond counts and require double storage to
        # preserve ordinary POSIXct values.
        "double"
    } else if (base_date) {
        "float"
    } else if (generate && typeof(values) == "double" &&
        !is.object(values)) {
        .generate_storage()
    } else {
        .bare_dta_storage(values)
    }
    prototype <- if (base_date) {
        structure(values, class = unique(c(
            "dta_temporal", "dta_date", class(values)
        )))
    } else if (base_datetime) {
        structure(values, class = unique(c(
            "dta_temporal", "dta_datetime", class(values)
        )))
    } else {
        values
    }
    source <- if (inherits(values, "dta_numeric") &&
        !identical(storage, "double")) {
        values
    } else {
        # The native reader consumes logical, integer, and double vectors
        # directly. Preserve their storage to avoid a full double temporary.
        vctrs::vec_data(values)
    }
    temporal_code <- if (temporal) .dta_temporal_code(prototype) else 0L
    kind <- match(storage, c("byte", "int", "long", "float", "double")) - 1L
    generated_attributes <- .dta_attribute_plan(
        prototype, storage, temporal = temporal, labelled = !temporal
    )
    .Call(
        C_dtatools_generate_numeric, source, rows,
        as.double(row_count), as.integer(kind), as.integer(temporal_code),
        generated_attributes
    )
}

.generated_character <- function(values, rows, row_count) {
    declared <- .declared_string_storage(values)
    source_attributes <- attributes(values)
    source_attributes$names <- NULL
    source_attributes$stata.string.storage <- NULL
    if (is.null(source_attributes)) {
        source_attributes <- structure(list(), names = character())
    }
    .Call(
        C_dtatools_generate_character, values, rows,
        as.double(row_count), declared, source_attributes
    )
}

# `generate` marks `gen()`, `egen()`, and a new column through `:=`, the
# Stata commands, whose bare double result takes Stata's `generate`
# default rather than the container mapping; see `.generate_storage()`.
# `carry_metadata = FALSE` is `generate`'s other half: Stata's `generate`
# copies values, not labels, so `gen()` and a new `:=` column keep only
# what types the result (ADR 0039). The value is stripped before anything
# reads it, so a note, a label, or the haven class cannot change the
# dispatch or the storage the result takes. `egen()` authors its own
# labels on the value and carries them; the container mapping carries
# everything, as R does.
.generated_column <- function(values, rows, row_count, caller = "gen()",
                              generate = FALSE, carry_metadata = TRUE) {
    if (generate && !carry_metadata && is.null(attributes(values)) &&
        typeof(values) %in% c("integer", "double") && !.is_altrep(values) &&
        length(values) == 1L) {
        return(.Call(C_dtatools_generate_scalar, values, rows, as.double(row_count),
                     if (typeof(values) == "integer") "long" else .generate_storage()))
    }
    message <- sprintf(
        "`%s` values must be numeric, logical, character, or a factor",
        caller
    )
    if (!is.null(dim(values))) stop(message, call. = FALSE)
    if (!carry_metadata) values <- .generate_value(values)
    if (typeof(values) == "character") {
        return(.generated_character(values, rows, row_count))
    }
    if (is.factor(values)) {
        return(.generated_factor(values, rows, row_count))
    }
    if (typeof(values) == "logical" && !is.object(values)) {
        return(.generated_logical(values, rows, row_count))
    }
    if (typeof(values) %in% c("logical", "integer", "double")) {
        return(.generated_numeric(values, rows, row_count, caller, generate))
    }
    stop(message, call. = FALSE)
}

# The attributes a generated column keeps from its value: the ones that
# type it. Everything that describes a variable (its label, value labels,
# display format, notes, and characteristics) is left behind, as Stata's
# `generate` leaves it; `set_var_label()` and `set_val_labels()` author it
# on the new variable. The haven class goes with the labels, and the
# metadata marker with the notes.
.generate_kept_attributes <- c(
    "class", "stata.storage", "stata.string.storage", "levels", "tzone",
    "units"
)

.generate_attributes <- function(source) {
    kept <- source[intersect(names(source), .generate_kept_attributes)]
    if (!is.null(kept$class)) {
        classes <- kept$class
        haven <- startsWith(classes, "haven_labelled")
        if (any(haven)) {
            # haven's chain is `haven_labelled` or a subclass such as
            # `haven_labelled_spss`, then `vctrs_vctr`, then the base type.
            # Without its head the tail is an orphaned vctrs class with no
            # methods, so a haven value that carries no `dta_*()` class of
            # its own goes back to a plain vector.
            classes <- classes[!haven]
            if (!any(startsWith(classes, "dta_"))) {
                classes <- setdiff(
                    classes,
                    c("vctrs_vctr", "double", "integer", "character", "logical")
                )
            }
        }
        classes <- setdiff(classes, .dta_metadata_vector_class)
        kept$class <- if (length(classes)) classes else NULL
    }
    kept
}

# The value with only the attributes a generated column keeps. A value
# that carries nothing else, the common bare result, is returned as is; a
# column reference is copied through `.metadata_copy()`, which keeps a
# compact backing compact, and its attributes are then removed one at a
# time: replacing them wholesale would wrap the copy in R's own ALTREP
# wrapper, and the native readers would no longer see the dictionary
# behind a string column.
.generate_value <- function(values) {
    source <- attributes(values)
    if (is.null(source)) return(values)
    kept <- .generate_attributes(source)
    if (identical(kept, source)) return(values)
    values <- .metadata_copy(values)
    for (name in setdiff(names(source), names(kept))) {
        attr(values, name) <- NULL
    }
    if (!identical(kept$class, source$class)) class(values) <- kept$class
    values
}

# A factor result stays a factor, which `save_dta()` writes as a
# value-labelled `long`, so `gen()` and `mutate()` agree on it. Rows
# outside `where` are `NA`, and the levels and other attributes are kept.
.generated_factor <- function(values, rows, row_count) {
    codes <- .generated_logical(unclass(values), rows, row_count)
    kept <- attributes(values)
    kept$names <- NULL
    attributes(codes) <- c(list(levels = kept$levels), kept[
        setdiff(names(kept), "levels")
    ])
    codes
}

# A bare logical result stays logical (see `.dta_typed_column()`). Rows
# outside `where` hold `NA`, as numeric rows hold system missing. Value
# attributes other than names, such as a label, are kept.
.generated_logical <- function(values, rows, row_count) {
    value_attributes <- attributes(values)
    value_attributes$names <- NULL
    data <- as.vector(values)
    size <- length(data)
    # Size rules as `.mutation_value_mode()`: one value recycles, a
    # full-length vector is indexed by the selected rows, and otherwise
    # the values are the selected rows' values in order.
    result <- if (is.null(rows)) {
        if (size == 1L) rep(data, row_count) else data
    } else {
        filled <- rep(NA, row_count)
        filled[rows] <- if (size == 1L) {
            data
        } else if (size == row_count) {
            data[rows]
        } else {
            data
        }
        filled
    }
    if (length(value_attributes)) attributes(result) <- value_attributes
    .Call(C_dtatools_capture_column, result)
}

.deep_copy_value <- function(value) {
    .Call(C_dtatools_deep_copy_value, value)
}

.contains_reference_object <- function(value) {
    if (is.environment(value) || is.function(value) ||
        typeof(value) %in% c("bytecode", "externalptr", "weakref")) {
        return(TRUE)
    }
    contents <- if (typeof(value) %in%
        c("list", "expression", "pairlist", "language")) {
        .Call(C_dtatools_reference_contents, value)
    } else {
        list()
    }
    nested <- c(contents, unname(attributes(value)))
    any(vapply(nested, .contains_reference_object, logical(1)))
}

.reference_row_reads <- function(enabled) {
    .Call(C_dtatools_reference_row_reads, enabled)
}

# Test control for exercising transaction cleanup after a completed write.
.inject_reference_write_interrupt <- function(enabled) {
    invisible(.Call(C_dtatools_inject_reference_write_interrupt, enabled))
}

#' @rdname replace_values
#' @export
copy_data <- function(data) {
    .open_mutation_target(data, allow_grouped = TRUE)
    snapshot <- .reference_snapshot(data)
    source <- .as_mutation_data(snapshot, allow_grouped = TRUE)
    snapshot_columns <- source$columns
    snapshot_attributes <- attributes(snapshot)
    reference_values <- c(snapshot_columns, unname(snapshot_attributes))
    if (any(vapply(
        reference_values, .contains_reference_object, logical(1)
    ))) {
        stop(
            paste0(
                "`copy_data()` cannot isolate environments, functions, ",
                "bytecode, external pointers, or weak references"
            ),
            call. = FALSE
        )
    }
    columns <- lapply(snapshot_columns, .deep_copy_value)
    copied_attributes <- lapply(
        snapshot_attributes, .deep_copy_value
    )
    attributes(columns) <- copied_attributes
    .as_dibble(columns, "copy_data()")
}

# A column read must not make the next by-reference write copy: wrapping
# the vector in `list()` on the way out would mark its handle shared, so
# the absent case is signalled with a sentinel instead.
.absent_column <- new.env(parent = emptyenv())

.reference_column <- function(data, name) {
    value <- .subset2(data, name)
    if (is.null(value)) .absent_column else value
}

#' @export
`$.dibble` <- function(x, name) {
    found <- .reference_column(x, as.character(name))
    if (!identical(found, .absent_column)) return(found)
    call <- sys.call()
    call[[1L]] <- quote(`$`)
    call[[2L]] <- .reference_snapshot(x)
    eval(call, parent.frame())
}

#' @export
`[[.dibble` <- function(x, i, ..., exact = TRUE) {
    if (...length() == 0L && isTRUE(exact) && length(i) == 1L) {
        name <- if (is.character(i)) {
            i
        } else if (is.numeric(i) && !is.na(i)) {
            names <- attr(x, "names", exact = TRUE)
            if (i >= 1 && i <= length(names)) names[[i]] else NULL
        } else {
            NULL
        }
        if (!is.null(name)) {
            found <- .reference_column(x, name)
            if (!identical(found, .absent_column)) return(found)
        }
    }
    .reference_snapshot(x)[[i, ..., exact = exact]]
}

# `[.dibble` is defined in dibble.R beside its documentation: it is the
# bracket mutation entry as well as the snapshot delegate.

#' @export
length.dibble <- function(x) {
    .Call(C_dtatools_physical_column_count, x)
}

#' @export
dim.dibble <- function(x) {
    c(abs(.row_names_info(x, 2L)), length(x))
}

#' @export
dimnames.dibble <- function(x) {
    list(row.names(.reference_snapshot(x)), names(x))
}

#' @export
as.data.frame.dibble <- function(x, ...) {
    as.data.frame(.reference_snapshot(x), ...)
}

#' @export
as.matrix.dibble <- function(x, ...) {
    as.matrix(.reference_snapshot(x), ...)
}

#' @export
as.list.dibble <- function(x, ...) {
    as.list(.data_columns(x), ...)
}

# The `[` primitive marks its result visible after S3 dispatch, so a
# bracket assignment cannot return invisibly the way `gen()` does. As
# data.table does for its `:=`, the assignment records the dataset it
# just mutated, and the next top-level print of that dataset is skipped,
# which is the autoprint of the assignment's own result. The record is
# dropped at that first print, so a `print(data)` or bare `data` on the
# next line prints, and a print from inside a function or a test never
# skips, because it sits deeper in the call stack.
#
# The autoprint only happens when the bracket call is itself the
# top-level statement. Inside `<-`, a loop, `invisible()`, or a function
# body nothing consumes the record, and left alone it would swallow the
# user's next bare `data`. A task callback clears the record when the
# top-level statement that set it finishes, so it can never outlive that
# statement. The callback is registered once per statement and removes
# itself, so an idle session carries no callback.
.bracket_print <- new.env(parent = emptyenv())
.bracket_print$skip <- NULL
.bracket_print$callback <- FALSE

.suppress_bracket_autoprint <- function(x) {
    .bracket_print$skip <- .reference_state(x)
    if (!.bracket_print$callback) {
        .bracket_print$callback <- TRUE
        addTaskCallback(function(...) {
            .bracket_print$skip <- NULL
            .bracket_print$callback <- FALSE
            FALSE
        }, name = "dtatools_bracket_autoprint")
    }
    invisible(NULL)
}

# Implicit autoprint calls `print` through the function object itself, so
# the outer call's head is a closure rather than the symbol `print`; an
# explicit `print(data[, y := 1])` arrives with the symbol. Only the former
# is the assignment's own echo, so only it is skipped, as data.table does.
# The record is spent either way, so a stale one cannot outlive its
# statement.
.skip_bracket_autoprint <- function(x, frames, call) {
    skip <- .bracket_print$skip
    if (is.null(skip)) return(FALSE)
    .bracket_print$skip <- NULL
    identical(skip, .reference_state(x)) && frames <= 2L &&
        is.call(call) && is.function(call[[1L]])
}

# Ordinary replacement follows R's copy-and-rebind semantics. Type and
# validate the snapshot, then isolate every column before closing the result.
#' @export
`$<-.dibble` <- function(x, name, value) {
    result <- .reference_snapshot(x)
    result[[name]] <- value
    .install_replacement(x, result, value, "`$<-`")
}

#' @export
`[[<-.dibble` <- function(x, i, ..., value) {
    result <- .reference_snapshot(x)
    result[[i, ...]] <- value
    .install_replacement(x, result, value, "`[[<-`")
}

#' @export
`[<-.dibble` <- function(x, i, j, ..., value) {
    call <- sys.call()
    call[[1L]] <- quote(`[<-`)
    # `data["s"] <- NULL` deletes a column; `call$value <- NULL` would
    # delete the argument instead.
    call["value"] <- list(value)
    snapshot <- .reference_snapshot(x)
    call[[2L]] <- snapshot
    # The subscripts are evaluated once here, so the promoting retry
    # below does not run `i` or `j` a second time; an empty argument, as
    # in `x[i, ] <- v`, stays empty.
    argument_names <- names(call)
    for (index in seq_along(call)[-(1:2)]) {
        if (identical(argument_names[[index]], "value")) next
        # An empty argument cannot be bound to a name, so it is tested
        # on the call itself. `call[index] <- list(...)` keeps a `NULL`
        # subscript in place, where `[[<-` would delete the argument and
        # select everything.
        empty <- is.symbol(call[[index]]) && !nzchar(as.character(call[[index]]))
        if (!empty) call[index] <- list(eval(call[[index]], parent.frame()))
    }
    result <- .bracket_replace_promoting(snapshot, call, parent.frame())
    .install_replacement(x, result, value, "`[<-`", envir = parent.frame())
}

.install_replacement <- function(x, result, value, caller, envir = parent.frame()) {
    if (!is.data.frame(result)) return(result)
    if (nrow(result) != nrow(x)) {
        stop(sprintf("%s cannot change a dibble's row count", caller), call. = FALSE)
    }
    names <- names(result)
    if (is.null(names) || anyNA(names) || any(names == "") || anyDuplicated(names)) {
        stop(sprintf("%s needs unique, non-missing column names", caller), call. = FALSE)
    }
    generic <- switch(caller, "`$<-`" = "[[<-", "`[[<-`" = "[[<-",
                      "`[<-`" = "[<-", "`names<-`" = "names<-",
                      "`dimnames<-`" = "names<-", NULL)
    grouping <- if (!is.null(generic)) .native_group_method_missing(
        x, generic, envir = envir)
    if (!is.null(grouping) && identical(caller, "`dimnames<-`") &&
        is.null(.native_group_method_missing(x, "dimnames<-", envir = envir))) {
        grouping <- NULL
    }
    # dplyr does not supply a rowwise [[<- method.
    if (identical(grouping, "rowwise_df") && identical(generic, "[[<-")) {
        grouping <- NULL
    }
    if (!is.null(grouping)) {
        .as_mutation_data(x, allow_grouped = TRUE)
        template <- .reference_snapshot(x)
        rowwise_groups <- if (identical(grouping, "rowwise_df") &&
                              identical(generic, "[<-")) {
            # The rowwise replacement method groups before dibble retyping.
            # Its raw key representation remains observable after promotion.
            .capture_dibble_nested(.build_group_metadata(.data_columns(result),
                intersect(names(result), .group_vars(template)), nrow(result),
                rowwise = TRUE))
        }
        result <- .ungrouped_result_frame(.data_columns(result), attributes(result),
                                          .row_names_info(result, 0L))
        typed <- .retype_changed_columns(result, .data_columns(x), caller)
        context <- .begin_dibble_result(x, caller, "unknown")
        restore <- if (identical(generic, "names<-")) {
            groups <- attr(template, "groups", exact = TRUE)
            keys <- setdiff(names(groups), ".rows")
            names(groups) <- c(names[match(keys, names(x))], ".rows")
            function(value) {
                attr(value, "row.names") <- .set_row_names(nrow(value))
                attr(value, "groups") <- groups
                class(value) <- .reference_base_classes(class(template))
                value
            }
        } else if (!is.null(rowwise_groups)) function(value) {
            attr(value, "row.names") <- .set_row_names(nrow(value))
            attr(value, "groups") <- rowwise_groups
            class(value) <- .reference_base_classes(class(template))
            value
        } else function(value) .restore_group_metadata(value, template)
        return(.finish_dibble_result(context, typed, grouping = restore))
    }
    typed <- .retype_changed_columns(result, .data_columns(x), caller)
    .close_dibble(x, typed, caller)
}

# Row or cell assignment into a typed column runs the column's own strict
# `[<-`, which refuses a value its storage cannot hold before the dibble
# can promote. The strict path is tried first, since it keeps compact
# columns compact. If it fails, the assignment is redone on a copy whose
# typed numeric and string columns are bare R vectors, columns the
# assignment did not touch get their typed vectors back, and the changed
# ones are promoted from their prior storage by the caller.
.bracket_replace_promoting <- function(snapshot, call, environment) {
    strict <- tryCatch(eval(call, environment), error = identity)
    if (!inherits(strict, "error")) return(strict)
    bare <- snapshot
    bare_columns <- list()
    column_names <- names(snapshot)
    for (index in seq_along(column_names)) {
        column <- .subset2(snapshot, index)
        plain <- if (inherits(column, "dta_numeric") &&
            !inherits(column, "dta_temporal")) {
            as.double(.dta_snapshot(column))
        } else if (is.character(column) &&
            !is.null(.declared_string_storage(column))) {
            .stata_string_text(column)
        } else {
            NULL
        }
        if (is.null(plain)) next
        bare[[index]] <- plain
        bare_columns[[column_names[[index]]]] <- plain
    }
    if (length(bare_columns) == 0L) stop(strict)
    call[[2L]] <- bare
    result <- eval(call, environment)
    result_names <- names(result)
    for (name in names(bare_columns)) {
        index <- match(name, result_names)
        if (is.na(index)) next
        if (identical(
            rlang::obj_address(.subset2(result, index)),
            rlang::obj_address(bare_columns[[name]])
        )) {
            result[[index]] <- .subset2(snapshot, name)
        }
    }
    result
}

# `names(d)[1] <- "k"` returns a renamed copy.
#' @export
`names<-.dibble` <- function(x, value) {
    result <- .reference_snapshot(x)
    names(result) <- value
    .install_replacement(x, result, NULL, "`names<-`")
}

#' @export
`dimnames<-.dibble` <- function(x, value) {
    result <- .reference_snapshot(x)
    dimnames(result) <- value
    .install_replacement(x, result, NULL, "`dimnames<-`")
}

#' @export
`row.names<-.dibble` <- function(x, value) {
    result <- .reference_snapshot(x)
    row.names(result) <- value
    .install_replacement(x, result, NULL, "`row.names<-`")
}

#' @export
as_tibble.dibble <- function(x, ...) {
    tibble::as_tibble(.reference_snapshot(x), ...)
}

#' @export
vec_proxy.dibble <- function(x, ...) {
    vctrs::vec_proxy(.reference_snapshot(x), ...)
}

#' @export
vec_restore.dibble <- function(x, to, ...) {
    grouping <- .native_group_method_missing(
        to, "vec_restore", envir = environment(), registry = asNamespace("vctrs"))
    if (is.null(grouping)) {
        return(.close_dibble(to, vctrs::vec_restore(x, .reference_snapshot(to), ...)))
    }
    .as_mutation_data(to, allow_grouped = TRUE)
    template <- .reference_snapshot(to)
    plain <- .ungrouped_result_frame(.data_columns(template), attributes(template),
                                     .row_names_info(template, 0L))
    result <- vctrs::vec_restore(x, plain, ...)
    result <- .ungrouped_result_frame(.data_columns(result), attributes(result),
                                      .row_names_info(result, 0L))
    if (identical(grouping, "rowwise_df")) {
        # vec_restore.rowwise_df restores rowwise rows without identifiers.
        attr(template, "groups") <- attr(template, "groups", exact = TRUE)[".rows"]
    }
    context <- .begin_dibble_result(to, "as_dibble()", "unknown")
    .finish_dibble_result(context, result,
        grouping = function(value) {
            value <- .restore_group_metadata(value, template)
            if (identical(grouping, "grouped_df")) {
                groups <- attr(value, "groups", exact = TRUE)
                if (!is.null(groups) && !nrow(groups)) {
                    attr(groups, "row.names") <- integer()
                    attr(value, "groups") <- groups
                }
            }
            value
        })
}

#' @export
dplyr_reconstruct.dibble <- function(data, template) {
    .reconstruct_dibble(data, template)
}

# dplyr's grouped and rowwise row slicing, which `semi_join()`,
# `anti_join()`, and the `rows_*()` verbs use, builds its result without
# passing through `dplyr_reconstruct()`, so the dibble closes here.
#' @export
dplyr_row_slice.dibble <- function(data, i, ..., preserve = FALSE) {
    .as_mutation_data(data, allow_grouped = TRUE)
    locations <- vctrs::vec_as_location(i, n = nrow(data), missing = "propagate", arg = "i")
    context <- .begin_dibble_result(data, "dplyr_row_slice()", "rows")
    row_names <- .row_slice_names(context, locations)
    .dibble_take_rows(context, locations, data, "slice", preserve, row_names)

}

#' @export
select.dibble <- function(.data, ...) {
    context <- .begin_dibble_result(.data, "select()", "columns")
    locations <- tidyselect::eval_select(rlang::expr(c(...)), .data)
    locations <- .dibble_ensure_group_columns(context, locations)
    .dibble_select_columns(context, locations)
}

.reference_delegate <- function(data, call, generic, environment) {
    call[[1L]] <- generic
    call[[2L]] <- .reference_snapshot(data)
    eval(call, environment)
}

# Base and dplyr methods share one boundary: the dibble is materialized
# to a shallow, complete data-frame snapshot before the ordinary
# implementation runs. The result follows copy-on-modify and is closed
# back into a dibble, so a dataset operation on a dibble yields a dibble.
#' @export
with.dibble <- function(data, expr, ...) {
    .reference_delegate(data, sys.call(), base::with, parent.frame())
}

#' @export
within.dibble <- function(data, expr, ...) {
    .typed_reference_verb(
        data, sys.call(), base::within, parent.frame(), "`within()`"
    )
}

#' @export
subset.dibble <- function(x, ...) {
    .close_dibble(x, .reference_delegate(x, sys.call(), base::subset, parent.frame()))
}

#' @export
transform.dibble <- function(`_data`, ...) {
    .typed_reference_verb(
        `_data`, sys.call(), base::transform, parent.frame(), "`transform()`"
    )
}

#' @export
arrange.dibble <- function(.data, ..., .by_group = FALSE, .locale = NULL) {
    .dibble_arrange(
        .data, rlang::enquos(...), .by_group, .locale)
}

#' @export
filter.dibble <- function(
    .data, ..., .by = NULL, .preserve = FALSE
) {
    .dibble_filter(.data,
        rlang::enquos(..., .ignore_empty = "all"), rlang::enquo(.by), .preserve)
}

#' @export
filter_out.dibble <- function(.data, ..., .by = NULL, .preserve = FALSE) {
    .dibble_filter(.data,
        rlang::enquos(..., .ignore_empty = "all"), rlang::enquo(.by), .preserve,
        invert = TRUE)
}

#' @export
slice.dibble <- function(.data, ..., .by = NULL, .preserve = FALSE) {
    .dibble_slice(
        .data, rlang::enquos(...), rlang::enquo(.by), .preserve)
}

#' @export
slice_head.dibble <- function(.data, ..., n, prop, by = NULL) {
    rlang::check_dots_empty()
    .dibble_slice_helper(.data, rlang::enquo(by), .dibble_slice_size(n, prop), "head")
}

#' @export
slice_tail.dibble <- function(.data, ..., n, prop, by = NULL) {
    rlang::check_dots_empty()
    .dibble_slice_helper(.data, rlang::enquo(by), .dibble_slice_size(n, prop), "tail")
}

#' @export
slice_min.dibble <- function(.data, order_by, ..., n, prop, by = NULL,
                                       with_ties = TRUE, na_rm = FALSE) {
    rlang::check_dots_empty()
    .dibble_slice_helper(.data, rlang::enquo(by), .dibble_slice_size(n, prop), "min",
        order_by = rlang::enquo(order_by), with_ties = with_ties, na_rm = na_rm)
}

#' @export
slice_max.dibble <- function(.data, order_by, ..., n, prop, by = NULL,
                                       with_ties = TRUE, na_rm = FALSE) {
    rlang::check_dots_empty()
    .dibble_slice_helper(.data, rlang::enquo(by), .dibble_slice_size(n, prop), "max",
        order_by = rlang::enquo(order_by), with_ties = with_ties, na_rm = na_rm)
}

#' @export
slice_sample.dibble <- function(.data, ..., n, prop, by = NULL,
                                          weight_by = NULL, replace = FALSE) {
    rlang::check_dots_empty()
    .dibble_slice_helper(.data, rlang::enquo(by), .dibble_slice_size(n, prop, replace),
        "sample", weight_by = rlang::enquo(weight_by), replace = replace)
}

#' @export
relocate.dibble <- function(
    .data, ..., .before = NULL, .after = NULL
) {
    context <- .begin_dibble_result(.data, "relocate()", "columns")
    locations <- .dibble_relocate_locations(
        .data, rlang::expr(c(...)), rlang::enquo(.before),
        rlang::enquo(.after), environment()
    )
    .dibble_select_columns(context, locations)
}

#' @export
rename.dibble <- function(.data, ...) {
    context <- .begin_dibble_result(.data, "rename()", "columns")
    changes <- tidyselect::eval_rename(rlang::expr(c(...)), .data)
    names <- names(context$columns)
    names[changes] <- names(changes)
    .dibble_select_columns(context, stats::setNames(seq_along(names), names))
}

#' @export
mutate.dibble <- function(
    .data, ..., .by = NULL, .keep = c("all", "used", "unused", "none"),
    .before = NULL, .after = NULL
) {
    .dibble_mutate(
        .data, rlang::enquos(..., .ignore_empty = "all"), rlang::enquo(.by),
        .keep, rlang::enquo(.before), rlang::enquo(.after))
}

#' @export
transmute.dibble <- function(.data, ...) {
    dots <- rlang::enquos(..., .ignore_empty = "all")
    unsupported <- intersect(names(dots), c(".keep", ".before", ".after"))
    if (length(unsupported)) rlang::abort(paste0(
        "The `", unsupported[[1L]], "` argument is not supported."))
    .dibble_mutate(.data, dots, transmute = TRUE)
}

# The container mapping from a bare R vector to Stata storage, shared by
# `dibble()`, the dplyr verbs, the replacement operators, and the
# promotion ladder; `?dta-storage-defaults` states it for users. It
# follows the R type: `float` cannot hold every R double or every R
# integer, so the mapping is lossless. Dates and datetimes are decided by
# the caller, which knows their class. `gen()` and a new column through
# `:=` are the exception, in `.generate_storage()`.
.bare_dta_storage <- function(values) {
    switch(typeof(vctrs::vec_data(values)),
        logical = "byte",
        integer = "long",
        "double"
    )
}

# Stata's `generate` stores an untyped numeric result as `float`, or as
# `double` after `set type double`. `gen()` and a new column through `:=`
# translate that command, so a bare double result takes this storage,
# read from `options(dtatools.generate_type = )`, rather than the
# container mapping (ADR 0022). Bare integers stay `long`: they come from
# R, not from a translated Stata line, and `float` loses them above 2^24.
.generate_storage <- function() {
    storage <- getOption("dtatools.generate_type", "float")
    if (!is.character(storage) || length(storage) != 1L ||
        is.na(storage) || !(storage %in% c("float", "double"))) {
        stop(
            paste0(
                "`dtatools.generate_type` must be \"float\" or ",
                "\"double\"; got ", paste(deparse(storage), collapse = " ")
            ),
            call. = FALSE
        )
    }
    storage
}

# A dataset operation on a dibble returns a dibble; the copying helpers
# that accept every container, such as the label replacement operators,
# pass their plain result through. A non-data-frame result, such as
# `with()`'s, is returned as is.
.close_dibble <- function(data, result, caller = "as_dibble()",
                          sources = NULL) {
    if (!is_dibble(data) || !is.data.frame(result) || is_dibble(result)) {
        return(result)
    }
    context <- .begin_dibble_result(data, caller, "unknown")
    .finish_dibble_result(context, result, sources)
}

# A column the operation left alone, as `select()`, `relocate()`,
# `mutate()` of another column, or `cbind()` do, is the same vector in
# the result and in one of the `sources`, and a by-reference `:=` or
# `repl()` through the dibble would reach that frame. Each such column
# becomes a copy-on-write view: a compact column stays compact behind a
# metadata proxy whose first write on either side detaches, and a plain
# vector is copied. Columns the operation rebuilt are already the
# result's own. `sources = NULL`, the default, isolates every column:
# a data-masked verb such as `mutate(d, copied = other$flag)` can bring
# in a vector from any frame, `cbind(d, x = other$x)` takes bare vectors,
# and the vctrs and dplyr hooks see only the first input of a
# `bind_cols()` or join, so the inputs a closure can name are rarely the
# only ones. A caller that does know every vector its result could share
# passes them, frames or vectors, so untouched columns are left as they
# are.
.isolate_shared_columns <- function(result, sources) {
    isolate_all <- is.null(sources)
    source_addresses <- if (!isolate_all) {
        unlist(lapply(sources, function(source) {
            if (is.data.frame(source)) {
                vapply(
                    .data_columns(source), rlang::obj_address, character(1)
                )
            } else {
                rlang::obj_address(source)
            }
        }))
    }
    result <- .metadata_copy(result)
    detached <- utils::hashtab(type = "address")
    absent_capture <- new.env(parent = emptyenv())
    for (index in seq_len(length(result))) {
        column <- .subset2(result, index)
        address <- rlang::obj_address(column)
        if (isolate_all || address %in% source_addresses) {
            captured <- utils::gethash(detached, column, nomatch = absent_capture)
            if (identical(captured, absent_capture)) {
                captured <- .metadata_copy(column)
                utils::sethash(detached, column, captured)
            }
            .Call(C_dtatools_set_data_column, result, as.integer(index), captured)
        }
    }
    result
}

# `transform()`, `within()`, `group_modify()`, and the replacement
# operators on a dibble: the ordinary implementation runs on the
# snapshot, then changed columns are typed and the result is closed back
# into a dibble.
.typed_reference_verb <- function(data, call, generic, environment,
                                  caller) {
    before <- .data_columns(data)
    result <- .reference_delegate(data, call, generic, environment)
    .close_dibble(
        data, .retype_changed_columns(result, before, caller), caller
    )
}

# The data-masking verbs type each `...` expression as its result enters
# the data mask, so a later expression, the row comparison of
# `distinct()`, or the grouping of `group_by()` and `nest_by()` sees the
# Stata column the result will hold. A bare double `y = c(NA, 1)` is a
# Stata `double` when `z = y > 0` reads it, so `z` is `TRUE` where Stata's
# missing order says so, and `NA` and `""` in a computed string key form
# one group. Existing-column symbols, `.data` references, and `NULL` are
# left alone: they select or remove columns rather than compute them.
# `if_any()` and `if_all()` return logicals and keep dplyr's expansion.
.mask_expression_typable <- function(quosure, before) {
    if (rlang::quo_is_missing(quosure) || rlang::quo_is_null(quosure)) {
        return(FALSE)
    }
    if (rlang::quo_is_symbol(quosure) &&
        rlang::as_name(quosure) %in% names(before)) return(FALSE)
    expression <- rlang::quo_get_expr(quosure)
    if (!is.call(expression)) return(TRUE)
    if (rlang::is_call(expression, c("$", "[["), n = 2L) &&
        identical(expression[[2L]], quote(.data))) {
        return(FALSE)
    }
    !rlang::is_call(
        expression, c("if_any", "if_all"), ns = c("", "dplyr")
    )
}

# dplyr names an unnamed column and its condition bullets by
# `rlang::as_label()` of the expression with infix folding turned off.
.mask_expression_label <- function(quosure) {
    rlang::with_options(
        "rlang:::use_as_label_infix" = FALSE,
        rlang::as_label(rlang::quo_get_expr(quosure))
    )
}

.typed_reference_replacement <- function(data, result, caller) {
    before <- .data_columns(data)
    .close_dibble(
        data, .retype_changed_columns(result, before, caller), caller
    )
}

#' @export
group_by.dibble <- function(
    .data, ..., .add = FALSE,
    .drop = .group_drop_default(.data)
) {
    .dibble_group_by(
        .data, rlang::enquos(..., .ignore_empty = "all"), .add, .drop)
}

#' @export
summarise.dibble <- function(
    .data, ..., .by = NULL, .groups = NULL
) {
    .dibble_summary(.data,
        rlang::enquos(..., .ignore_empty = "all"), rlang::enquo(.by), .groups,
        caller_env = parent.frame())
}

#' @export
distinct.dibble <- function(.data, ..., .keep_all = FALSE) {
    .dibble_distinct(.data,
        rlang::enquos(..., .ignore_empty = "all"), .keep_all)
}

#' @export
reframe.dibble <- function(.data, ..., .by = NULL) {
    .dibble_summary(.data,
        rlang::enquos(..., .ignore_empty = "all"), rlang::enquo(.by), reframe = TRUE)
}

#' @export
group_modify.dibble <- function(.data, .f, ..., .keep = FALSE) {
    .dibble_group_modify(.data, .f, ..., .keep = .keep)
}

#' @export
nest_by.dibble <- function(.data, ..., .key = "data",
                                      .keep = FALSE) {
    .dibble_nest(.data,
        rlang::enquos(..., .ignore_empty = "all"), .key, .keep,
        rowwise = TRUE, dots_supplied = !missing(...))
}

#' @export
group_nest.dibble <- function(.tbl, ..., .key = "data",
                                         keep = FALSE) {
    .dibble_nest(.tbl,
        rlang::enquos(..., .ignore_empty = "all"), .key, keep)
}

#' @export
ungroup.dibble <- function(x, ...) {
    context <- .begin_dibble_result(x, "ungroup()", "columns")
    keys <- character()
    if (inherits(x, "grouped_df") && !missing(...)) {
        removed <- names(tidyselect::eval_select(rlang::expr(c(...)), x, allow_rename = FALSE))
        keys <- setdiff(.group_vars(x), removed)
    } else rlang::check_dots_empty()
    .dibble_group_result(x, context, context$columns, keys, .group_drop_default(x))
}

#' @export
rowwise.dibble <- function(data, ...) {
    context <- .begin_dibble_result(data, "rowwise()", "columns")
    if (inherits(data, "grouped_df")) {
        if (!missing(...)) rlang::abort(c("Can't re-group when creating rowwise data.",
            i = "Either first `ungroup()` or call `rowwise()` without arguments."))
        keys <- .group_vars(data)
    } else {
        locations <- tidyselect::eval_select(rlang::expr(c(...)), data)
        keys <- names(context$columns)[unname(locations)]
    }
    .dibble_group_result(data, context, context$columns, keys, rowwise = TRUE)
}
