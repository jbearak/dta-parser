#' Generate and replace variables by reference
#'
#' `gen()` and `replace_values()` modify a data frame or tibble by reference.
#' `repl()` is a direct alias for `replace_values()`. The return value is the
#' updated dataset, invisibly. Within reserved capacity, aliases observe
#' generation and replacement. Preparation or reallocation can separate
#' aliases; assign the returned table when calling through a function. This includes column-only subsets that share their column
#' payload. Row subsets have new payloads and remain independent. Use
#' `copy_data()` when isolation is required. Generic ALTREP columns created by
#' base R or another package are detached to ordinary vectors before
#' replacement because their private caches cannot be invalidated safely.
#' Aliases to the same dataset object observe the installed vector. On a
#' [dibble], the replacement operators `$<-`, `[[<-`, `[<-`, `names<-`,
#' `dimnames<-`, and `row.names<-`, and so every setter used in
#' replacement form such as `var_label(data$x) <-`, write by reference as
#' well. A standalone alias to the former generic ALTREP column, including
#' one held by a previously created subset, remains unchanged.
#' Every generated column is stored in the physical column list, so direct
#' consumers such as `unclass()`, `dplyr::bind_rows()`, `purrr::map()`, and
#' `write.csv()` see the complete dataset. Constructors and readers reserve
#' 5,000 spare column-pointer slots by default, controlled by
#' `options(dtatools.alloccol = 5000L)`. When capacity is exhausted or a
#' table needs preparation, the operation warns, shallow-copies the table,
#' and rebinds a supported target. Aliases retain the old complete table.
#' See [reserve_columns()] for supported targets, function parameters, and
#' the required preparation after base R serialization.
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
#' ungrouped call, so storage validation, compact patching, transactions,
#' and data.table handling are unchanged. Rows a group's `where` does not
#' select are left alone by `replace_values()` and hold missing after
#' `gen()`, which still appends the new column once.
#'
#' This is Stata's order of operations, not data.table's. data.table's
#' `dt[i, j, by]` applies `i` first and groups only the surviving rows,
#' so under a non-empty `i` its `.N` counts selected rows and its groups
#' omit any group `i` empties. Here `.N` counts the group's rows whatever
#' `where` selects, and `where = .n == .N` marks each group's last row.
#' `.SD`, `.GRP`, and `.BY` are not provided; summaries stay with dplyr.
#'
#' `by` groups the dataset in its current row order and never sorts.
#' `bysort` first sorts the dataset by reference on every listed column,
#' in Stata's total order for `dta_*()` columns (finite values, then `.`,
#' then `.a` through `.z`), and then groups by those same columns, so the
#' rows within each group are the sorted rows and `.n` follows the sort.
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
#' `gen()` appends one variable and does not implement Stata's `before()` or
#' `after()` placement. The new column takes the storage in
#' [dta-storage-defaults]: a declared `dta_*()` result keeps its storage,
#' bare integer results are `long`, bare double results take Stata's
#' `generate` default of `float`, or `double` under
#' `options(dtatools.generate_type = "double")`, the equivalent of Stata's
#' `set type double`; logical results stay logical, `Date` and `POSIXct`
#' results keep their class with a Stata date or datetime declaration, and
#' character results
#' keep a valid declared `stata.string.storage` or take the smallest
#' `str1` through `str2045` width that fits, or `strL` above 2,045 UTF-8
#' bytes. Standard `haven_labelled` results preserve their label metadata.
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
#' `replace_values()` promotes, as Stata's `replace` does: a target whose
#' declared storage cannot hold a value is widened to the narrowest storage
#' that does, and the change is reported the way Stata reports it:
#' \code{variable `x` was byte now int}. The ladder is the one described
#' under [dta-storage-defaults], which keeps every value exact and so
#' differs from Stata's in two cases; an assignment that selects no rows
#' promotes nothing, as Stata's `(0 real changes made)` does not. Pass
#' `promote = FALSE` to hold the column to its declared storage and raise
#' an error instead, which was the behaviour before promotion was added.
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
#' @param data A data frame or tibble to mutate. A grouped tibble's groups
#'   become the assignment groups. Rowwise tibbles are rejected;
#'   `copy_data()` accepts them.
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
#' @param promote Whether `replace_values()` widens a target whose declared
#'   storage cannot represent a value, as Stata's `replace` does, reporting
#'   the change. `FALSE` holds the column to its declared storage and
#'   errors on a value that does not fit. Ignored by `gen()`, which creates
#'   the column and so has no prior storage to widen.
#' @return `gen()` and `replace_values()` return `data` invisibly.
#'   `copy_data()` returns an independent data frame or tibble.
#' @references
#' StataCorp, \href{https://www.stata.com/manuals/dgenerate.pdf}{generate manual}.
#' @seealso [dibble-bracket] for `data[i, y := value]` on a [dibble], which
#'   creates or overwrites in one call and takes the same `by`, `bysort`,
#'   and grouped input.
#' @examples
#' survey <- data.frame(income = c(10, 20), eligible = c(TRUE, FALSE))
#' gen(survey, adjusted = income + 5)
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
#' panel <- data.frame(id = c(2, 1, 2, 1), t = c(1, 1, 2, 2), x = 1:4)
#' gen(panel, rows = .N, by = id)               # each group's row count
#' gen(panel, last = .n == .N, by = id)         # each group's last row
#' gen(panel, above = x - mean(x), by = id)     # centred within group
#' repl(panel, x = 0, where = .n == 1, bysort = c(id, t))  # sorts first
#' @export
replace_values <- function(data, ..., where = NULL, by = NULL,
                           bysort = NULL, promote = TRUE) {
    target_expr <- substitute(data)
    binding <- .capture_mutation_binding(target_expr, parent.frame())
    if (!is.null(binding)) data <- binding$data

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
        promote = .validate_promote(promote), report_promotion = TRUE
    )
    .return_mutation(data, result, if (is.null(binding)) target_expr else binding, parent.frame())
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
gen <- function(data, ..., where = NULL, by = NULL, bysort = NULL) {
    target_expr <- substitute(data)
    binding <- .capture_mutation_binding(target_expr, parent.frame())
    if (!is.null(binding)) data <- binding$data

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
        bysort = if (missing(bysort)) NULL else rlang::enquo(bysort)
    )
    .return_mutation(data, result, if (is.null(binding)) target_expr else binding, parent.frame())
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

# The `dtatools_ref_data` class is what makes the state authoritative,
# because the mark sets both together. An in-place converter that rewrites
# the class alone, as `data.table::setDT()` does, leaves the attribute on
# an object the state no longer describes; honouring it there would have
# the mutators read a column list that is no longer the object's own.
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

.reference_names <- function(data) {
    state <- .reference_state(data)
    physical <- attr(data, "names", exact = TRUE)
    if (is.null(state)) return(physical)
    if (isTRUE(state$physical_overlay)) physical <- state$physical_names
    if (state$generated_count == 0L) return(physical)
    result <- c(physical, character(state$generated_count))
    node <- state$generated_head
    for (index in seq_len(state$generated_count)) {
        result[[state$physical_count + index]] <- node$name
        node <- node$following
    }
    result
}

.column_access <- function(data) {
    state <- .reference_state(data)
    list(
        data = data,
        state = state,
        names = if (is.null(state)) {
            attr(data, "names", exact = TRUE)
        } else {
            .reference_names(data)
        }
    )
}

.data_column_at <- function(access, index) {
    if (is.null(access$state) ||
        (!isTRUE(access$state$physical_overlay) &&
         index <= access$state$physical_count)) {
        return(.subset2(access$data, index))
    }
    access$state$columns[[access$names[[index]]]]
}

.set_data_column_at <- function(access, index, column) {
    if (!is.null(access$state)) {
        access$state$columns[[access$names[[index]]]] <- column
        if (isTRUE(access$state$physical_overlay) ||
            index > access$state$physical_count) {
            return(invisible(NULL))
        }
    }
    .Call(
        C_dtatools_set_data_column, access$data, as.integer(index), column
    )
    invisible(NULL)
}

.native_data_column_location <- function(access, index) {
    if (is.null(access$state) ||
        (!isTRUE(access$state$physical_overlay) &&
         index <= access$state$physical_count)) {
        return(index)
    }
    length(attr(access$data, "names", exact = TRUE)) + 1L
}

.data_columns <- function(data) {
    state <- .reference_state(data)
    if (is.null(state)) {
        physical <- .plain_data_columns(data)
        names(physical) <- attr(data, "names", exact = TRUE)
        return(physical)
    }
    columns <- vector("list", state$physical_count + state$generated_count)
    if (isTRUE(state$physical_overlay)) {
        physical_names <- state$physical_names
        for (index in seq_len(state$physical_count)) {
            columns[[index]] <- state$columns[[physical_names[[index]]]]
        }
    } else {
        physical_names <- attr(data, "names", exact = TRUE)
        columns[seq_len(state$physical_count)] <- .plain_data_columns(data)
    }
    names <- c(physical_names, character(state$generated_count))
    node <- state$generated_head
    for (index in seq_len(state$generated_count)) {
        location <- state$physical_count + index
        names[[location]] <- node$name
        columns[[location]] <- state$columns[[node$name]]
        node <- node$following
    }
    names(columns) <- names
    columns
}

.new_reference_state <- function(data, dibble = FALSE) {
    state <- new.env(parent = emptyenv())
    physical <- .plain_data_columns(data)
    physical_names <- attr(data, "names", exact = TRUE)
    columns <- new.env(hash = TRUE, parent = emptyenv())
    locations <- new.env(hash = TRUE, parent = emptyenv())
    for (index in seq_along(physical_names)) {
        columns[[physical_names[[index]]]] <- physical[[index]]
        locations[[physical_names[[index]]]] <- index
    }
    state$columns <- columns
    state$locations <- locations
    state$physical_names <- physical_names
    state$physical_overlay <- FALSE
    state$physical_count <- length(physical)
    state$generated_count <- 0L
    state$generated_head <- NULL
    state$generated_tail <- NULL
    state$nrow <- base::nrow(data)
    state$classes <- class(data)
    state$dibble <- dibble
    state
}

.new_structural_reference_state <- function(columns, row_count, classes,
                                            dibble = FALSE) {
    state <- new.env(parent = emptyenv())
    column_store <- new.env(hash = TRUE, parent = emptyenv())
    column_names <- names(columns)
    for (index in seq_along(column_names)) {
        column_store[[column_names[[index]]]] <- columns[[index]]
    }
    state$columns <- column_store
    state$locations <- NULL
    state$physical_names <- column_names
    state$physical_overlay <- TRUE
    state$physical_count <- length(columns)
    state$generated_count <- 0L
    state$generated_head <- NULL
    state$generated_tail <- NULL
    state$nrow <- row_count
    state$classes <- classes
    state$dibble <- dibble
    state
}

.append_generated_column <- function(state, name, column) {
    node <- new.env(parent = emptyenv())
    node$name <- name
    node$following <- NULL
    if (state$generated_count == 0L) {
        state$generated_head <- node
    } else {
        state$generated_tail$following <- node
    }
    state$generated_tail <- node
    state$generated_count <- state$generated_count + 1L
    state$columns[[name]] <- column
    if (is.environment(state$locations)) {
        state$locations[[name]] <- state$physical_count + state$generated_count
    }
    invisible(NULL)
}

# `gen()` on a dibble with spare column capacity appends the new column
# to the physical list itself, so every reader of that list, vctrs'
# binders included, sees the complete dataset. The state records it as
# one more physical column.
.append_physical_column <- function(state, name, column) {
    state$columns[[name]] <- column
    if (is.environment(state$locations)) {
        state$locations[[name]] <- state$physical_count + 1L
    }
    state$physical_count <- state$physical_count + 1L
    state$physical_names <- c(state$physical_names, name)
    invisible(NULL)
}

# Whether `gen()` can grow `data`'s physical column list in place: a
# dibble built with spare capacity whose columns are all physical. Once
# a generated column lives in the state, later ones follow it there so
# the recorded locations stay in order.
.can_append_physical_column <- function(data, state) {
    !isTRUE(state$physical_overlay) && state$generated_count == 0L &&
        !.ordinary_data_table(data)
}

.reserve_column_capacity <- function(x, n = getOption("dtatools.alloccol", 5000L)) {
    n <- .validate_alloccol(n, length(x))
    .Call(C_dtatools_reserve_column_capacity, x, as.double(length(x)) + n)
}

# The state records the object it marks. R shallow-duplicates a shared
# object before dispatching a replacement operator, so the method's `x`
# can be a copy; the recorded object is the one every binding holds, and
# by-reference replacement installs into it and returns it.
.mark_reference_data <- function(data, state) {
    classes <- unique(c("dtatools_ref_data", state$classes))
    state$object <- data
    .Call(C_dtatools_mark_reference_data, data, state, classes)
}

.reference_snapshot <- function(data) {
    state <- .reference_state(data)
    if (is.null(state)) return(data)
    if (!isTRUE(state$physical_overlay) && state$generated_count == 0L) {
        # A fresh dibble: every column is physical, so the snapshot is the
        # object minus its mark. Dropping the attribute shallow-copies the
        # list, which is what every `[` and dplyr call on a read result pays.
        attr(data, ".dtatools_ref_state") <- NULL
        class(data) <- state$classes
        return(data)
    }
    result <- .data_columns(data)
    source_attributes <- attributes(data)
    source_attributes$.dtatools_ref_state <- NULL
    source_attributes$class <- state$classes
    source_attributes$names <- names(result)
    automatic_rows <- .row_names_info(data, 1L) < 0L
    attributes(result) <- source_attributes
    if (automatic_rows) {
        attr(result, "row.names") <- .set_row_names(state$nrow)
    }
    result
}

# `gen()` and `replace_values()` accept a grouped tibble, whose dplyr
# groups become the assignment groups. The column-structure verbs still
# reject one, and a rowwise tibble is rejected everywhere but in
# `copy_data()`, because a row is not a group.
.as_mutation_data <- function(data, allow_grouped = FALSE,
                              allow_rowwise = allow_grouped) {
    if (!is.data.frame(data)) {
        stop("`data` must be a data frame or tibble", call. = FALSE)
    }
    if ((!allow_grouped && inherits(data, "grouped_df")) ||
        (!allow_rowwise && inherits(data, "rowwise_df"))) {
        stop("`data` must be an ungrouped data frame or tibble", call. = FALSE)
    }
    state <- .reference_state(data)
    names <- if (is.null(state)) {
        names(data)
    } else if (is.environment(state$locations)) {
        NULL
    } else {
        .reference_names(data)
    }
    if (is.null(state)) {
        if (is.null(names) || anyNA(names) || any(names == "") ||
            anyDuplicated(names)) {
            stop("`data` must have unique, non-missing column names",
                 call. = FALSE)
        }
    }
    row_count <- if (is.null(state)) nrow(data) else state$nrow
    if (is.null(state)) {
        columns <- .data_columns(data)
        sizes <- vapply(columns, NROW, numeric(1))
        if (any(sizes != row_count)) {
            stop("`data` has columns with inconsistent row counts",
                 call. = FALSE)
        }
    } else {
        columns <- state$columns
    }
    list(
        columns = columns, names = names, nrow = row_count, state = state
    )
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
    location <- if (is.null(data$state)) {
        match(name, data$names)
    } else if (is.environment(data$state$locations) &&
        exists(name, envir = data$state$locations, inherits = FALSE)) {
        data$state$locations[[name]]
    } else {
        match(name, data$names)
    }
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

.eval_in_mutation_data <- function(expression, columns, environment = NULL,
                                   extras = NULL, shadow = TRUE) {
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
    if (!inherits(value, "dta_numeric") || length(value) != row_count ||
        !is.null(dim(value))) {
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
    .dta_compare(plan$op, plan$original_left, plan$original_right)
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
# precedence rule. Each group's selection and values are gathered into
# one row vector and one value vector and handed to the ungrouped write
# path, so storage validation, compact patching, and transactions are
# shared rather than duplicated.
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
    unique(names)
}

# Resolves the assignment groups as a list of integer row vectors plus
# the key data frame used to name a group in an error. Returns `NULL`
# when the call is ungrouped or the dataset is empty, and otherwise the
# `original` column view to evaluate against, which `bysort` refreshes
# after reordering the dataset.
.mutation_groups <- function(data, original, by, bysort, grouped_input) {
    if (!is.null(by) && rlang::quo_is_null(by)) by <- NULL
    if (!is.null(bysort) && rlang::quo_is_null(bysort)) bysort <- NULL
    if (!is.null(by) && !is.null(bysort)) {
        stop("supply either `by` or `bysort`, not both", call. = FALSE)
    }
    if (grouped_input) {
        if (!is.null(by) || !is.null(bysort)) {
            stop(.MUTATION_GROUPED_MESSAGE, call. = FALSE)
        }
        if (original$nrow == 0L) return(NULL)
        groups <- attr(data, "groups", exact = TRUE)
        if (!is.data.frame(groups) || !".rows" %in% names(groups)) {
            stop("`data` has grouped-tibble metadata without groups",
                 call. = FALSE)
        }
        rows <- lapply(seq_len(nrow(groups)), function(index) {
            as.integer(groups$.rows[[index]])
        })
        keys <- groups[setdiff(names(groups), ".rows")]
        return(list(rows = rows, keys = keys, original = original))
    }
    if (is.null(by) && is.null(bysort)) return(NULL)
    argument <- if (is.null(by)) "bysort" else "by"
    names <- .mutation_group_names(
        if (is.null(by)) bysort else by, original$columns, argument
    )
    if (original$nrow == 0L) return(NULL)
    key_columns <- function() {
        keys <- lapply(names, .mutation_column, columns = original$columns)
        names(keys) <- names
        vctrs::new_data_frame(keys, n = original$nrow)
    }
    if (!is.null(bysort)) {
        # `vec_order()` is stable and, through `vec_proxy_order()`, sorts
        # Stata numeric columns in Stata's total order with system and
        # extended missing after every finite value.
        order <- vctrs::vec_order(key_columns())
        if (!identical(order, seq_len(original$nrow))) {
            reorder_dta_rows(data, order)
            # The sort permuted every column by reference; a plain data
            # frame's column list was snapshotted before it.
            original <- .as_mutation_data(data, allow_grouped = TRUE)
        }
    }
    located <- vctrs::vec_group_loc(key_columns())
    list(
        rows = lapply(located$loc, as.integer),
        keys = located$key,
        original = original
    )
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
    .dta_merge_slice(column, rows, fill_string_missing = FALSE)
}

# A column view over one group at a time. Every column is an active
# binding that slices the full column to the current group's rows on
# first use and caches the slice until the group changes, so an
# expression pays for the columns it reads and nothing else, and a
# runtime name through `.data[[name]]` or `.(name)` still resolves.
.mutation_group_view <- function(columns) {
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
                              selected = NULL, drop_unselected = FALSE) {
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
.regroup_after_replacement <- function(data, state) {
    snapshot <- if (is.null(state)) data else .reference_snapshot(data)
    # The snapshot reads attributes off `data`, so rewriting the attribute
    # on the object is what every binding and later snapshot observes.
    regrouped <- dplyr::group_by(
        dplyr::ungroup(snapshot),
        dplyr::across(dplyr::all_of(dplyr::group_vars(data))),
        .drop = dplyr::group_by_drop_default(data)
    )
    .Call(
        C_dtatools_set_attribute, data, "groups",
        attr(regrouped, "groups", exact = TRUE)
    )
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
    if (is.factor(target) || !is.null(dim(target)) ||
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
         .is_materialized_numeric_altrep(target)) &&
        (native_numeric || native_temporal) &&
        !is.factor(values) && is.null(dim(values))) {
        # The native patcher validates and encodes these values directly for
        # the target's declared storage. Going through vec_cast() would build
        # a replacement compact column and, for ordinary input, a full double
        # temporary before decoding it again.
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
        !is.object(values) && anyNA(values)) {
        values[is.na(values)] <- ""
    }
    .validate_numeric_values(values)
    # Build Stata prototypes from metadata rather than proxying the target.
    # A real metadata copy must revoke exclusive patch ownership; this internal
    # cast must not.
    prototype <- if (inherits(target, "dta_temporal")) {
        .dta_temporal_ptype(.declared_dta_storage(target), target)
    } else if (inherits(target, "dta_numeric")) {
        .dta_ptype(.declared_dta_storage(target), target)
    } else {
        target[integer()]
    }
    result <- vctrs::vec_cast(values, prototype)
    .validate_numeric_values(result)
    result
}

# Selects the rows of one bracket call, `data[i, j, by]`, before any of
# its assignments writes: `i` is evaluated once, with the shadow check
# and `.n`/`.N` of `where`, and the groups it was evaluated under are
# kept so each assignment reuses them. The result is `.mutate_data()`'s
# `selection`. `bysort` sorts the dataset here, once, as the grouped
# `gen()` path does.
.mutation_selection <- function(data, where, by, bysort) {
    .reject_data_table_subclass(data)
    grouped_input <- inherits(data, "grouped_df")
    original <- .as_mutation_data(
        data, allow_grouped = TRUE, allow_rowwise = FALSE
    )
    groups <- if (grouped_input || !is.null(by) || !is.null(bysort)) {
        .mutation_groups(data, original, by, bysort, grouped_input)
    } else {
        NULL
    }
    if (!is.null(groups)) original <- groups$original
    if (!rlang::quo_is_missing(where) &&
        !rlang::is_formula(rlang::quo_get_expr(where))) {
        .check_shadowed_symbols(
            rlang::quo_get_expr(where), original$columns,
            rlang::quo_get_env(where)
        )
    }
    if (!is.null(groups)) {
        return(list(
            groups = groups,
            group_rows = .grouped_selection(where, original$columns, groups)
        ))
    }
    selected <- .eval_mutation_expression(
        where, original$columns, "where",
        .row_counter_extras(where, NULL, original$nrow),
        row_count = original$nrow
    )
    list(groups = NULL, rows = .mutation_rows(selected, original$nrow))
}

# `selection` is a `.mutation_selection()` result. When given, `where` is
# not evaluated again and the groups it carries stand in for `by` and
# `bysort`, so every assignment in one `data[i, j]` writes to the rows
# `i` chose before the first of them wrote. `where` still arrives so
# `values` can be given `.n` and `.N` on the same terms.
.mutate_data <- function(data, variable, values, where, generate,
                         by = NULL, bysort = NULL, selection = NULL,
                         promote = FALSE, report_promotion = FALSE) {
    .reject_data_table_subclass(data)
    grouped_input <- inherits(data, "grouped_df")
    original <- .as_mutation_data(
        data, allow_grouped = TRUE, allow_rowwise = FALSE
    )
    target <- .mutation_name(variable, generate, original)
    if (.has_column_overlay(data)) {
        data <- .prepare_column_operation(data, length(.reference_names(data)))
        original <- .as_mutation_data(data, allow_grouped = TRUE)
    }
    groups <- if (!is.null(selection)) {
        selection$groups
    } else if (grouped_input || !is.null(by) || !is.null(bysort)) {
        .mutation_groups(data, original, by, bysort, grouped_input)
    } else {
        NULL
    }
    if (is.null(selection) && !is.null(groups)) original <- groups$original
    state <- .reference_state(data)
    access <- NULL
    column <- NULL

    # A formula body is exempt: `~` asks for the data mask outright.
    if (is.null(selection) && !rlang::quo_is_missing(where) &&
        !rlang::is_formula(rlang::quo_get_expr(where))) {
        .check_shadowed_symbols(
            rlang::quo_get_expr(where), original$columns,
            rlang::quo_get_env(where)
        )
    }
    # The fused comparison patch reads the whole target column, so it
    # cannot serve a per-group selection, and there is nothing to fuse
    # once the rows were selected up front.
    fused <- if (generate || !is.null(groups) || !is.null(selection)) {
        NULL
    } else {
        .fused_comparison_plan(where, original$columns, original$nrow)
    }
    if (!is.null(groups)) {
        gathered <- .grouped_mutation(
            where, values, original$columns, groups, original$nrow,
            selected = selection$group_rows, drop_unselected = !generate
        )
        selected <- gathered$rows
        evaluated <- gathered$values
    } else if (!is.null(selection)) {
        evaluated <- .eval_mutation_expression(
            values, original$columns, "values",
            .mutation_row_counters(where, values, original$nrow),
            row_count = original$nrow
        )
        selected <- selection$rows
    } else if (is.null(fused)) {
        extras <- .mutation_row_counters(where, values, original$nrow)
        selected <- .eval_mutation_expression(
            where, original$columns, "where", extras,
            row_count = original$nrow
        )
        evaluated <- .eval_mutation_expression(
            values, original$columns, "values", extras,
            row_count = original$nrow
        )
    } else {
        evaluated <- .eval_mutation_expression(
            values, original$columns, "values",
            .mutation_row_counters(where, values, original$nrow),
            row_count = original$nrow
        )
        access <- .column_access(data)
        column <- .data_column_at(access, target$location)
        replacement_plan <- if (
            .is_unmaterialized_numeric_altrep(column)
        ) {
            .fused_replacement_plan(evaluated, column, original$nrow)
        } else NULL
        if (!is.null(replacement_plan)) {
            patch <- function() .Call(
                C_dtatools_fused_compare_patch,
                column, fused$op_code, fused$left, fused$right,
                fused$scalar, replacement_plan$values,
                replacement_plan$scalar, .mutation_threads()
            )
            patched <- if (.ordinary_data_table(data)) {
                .data_table_fused_replace_commit(data, target$name, patch)
            } else {
                patch()
            }
            if (isTRUE(patched)) return(invisible(data))
        }
        selected <- .fused_comparison_value(fused)
    }
    rows <- .mutation_rows(selected, original$nrow)
    value_mode <- .mutation_value_mode(evaluated, rows, original$nrow)
    values <- evaluated

    if (generate) {
        column <- .generated_column(
            values, rows, original$nrow, generate = TRUE
        )
        data <- .prepare_column_operation(data, length(data) + 1L)
        state <- .reference_state(data)
        if (.ordinary_data_table(data)) {
            data.table::set(data, j = target$name, value = column)
            return(invisible(data))
        }
        if (is.null(state)) state <- .new_reference_state(data)
    } else {
        if (is.null(access)) access <- .column_access(data)
        if (is.null(column)) {
            column <- .data_column_at(access, target$location)
        }
        # An assignment that selects no rows changes nothing and returns
        # here: it neither declares storage nor promotes. Stata's
        # `replace` behaves the same way, reporting `(0 real changes
        # made)` and leaving the storage alone, so `repl()` takes this
        # path as `:=` does.
        if (promote &&
            .mutation_selected_count(rows, original$nrow) == 0L) {
            return(invisible(data))
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
            commit <- function() {
                .set_data_column_at(access, target$location, promoted)
            }
            if (.ordinary_data_table(data)) {
                .data_table_replace_commit(data, target$name, commit)
            } else {
                commit()
            }
            if (grouped_input) .regroup_after_replacement(data, state)
            return(invisible(data))
        }
        replacement <- .cast_replacement(
            values, column, rows, value_mode
        )
        # No selected group supplied a value. vctrs accepts NULL here, but
        # the native patcher requires a vector even for an empty selection.
        if (is.null(replacement) &&
            .mutation_selected_count(rows, original$nrow) == 0L) {
            return(invisible(data))
        }
    }

    if (!generate) {
        patch <- function() .Call(
            C_dtatools_patch_data_column, data,
            as.integer(.native_data_column_location(access, target$location)),
            column, rows, replacement
        )
        # The native patcher still validates strict scalar replacements for
        # an empty selection; do not invalidate lookup state without a write.
        column <- if (.ordinary_data_table(data) &&
                      .mutation_selected_count(rows, original$nrow) > 0L) {
            .data_table_replace_commit(data, target$name, patch)
        } else {
            patch()
        }
        if (!is.null(state)) state$columns[[target$name]] <- column
        # Rebuild after every grouped replacement, not only one that names
        # a grouping column: a target can share its vector with a key
        # under the package's alias semantics, so the key may have changed
        # without being named.
        if (grouped_input) .regroup_after_replacement(data, state)
    }
    if (generate) suspendInterrupts({
        appended <- .can_append_physical_column(data, state) &&
            .Call(C_dtatools_append_data_column, data, target$name, column)
        if (appended) {
            .append_physical_column(state, target$name, column)
        } else {
            stop("internal error: prepared table cannot append a column")
        }
        if (is.null(.reference_state(data))) .mark_reference_data(data, state)
    })
    invisible(data)
}

.data_table_fused_replace_commit <- function(data, target, patch) {
    key_columns <- data.table::key(data)
    index_columns <- data.table::indices(data, vectors = TRUE)
    affected_indexes <- vapply(
        index_columns, function(columns) target %in% columns, logical(1)
    )
    suspendInterrupts({
        result <- patch()
        if (is.null(result)) return(NULL)
        key_changed <- target %in% key_columns
        if (key_changed) data.table::setkeyv(data, NULL)
        if (key_changed || any(affected_indexes)) {
            retained <- index_columns[!affected_indexes]
            data.table::setindexv(data, NULL)
            for (columns in retained) data.table::setindexv(data, columns)
        }
        result
    })
}

.data_table_replace_commit <- function(data, target, patch) {
    key_columns <- data.table::key(data)
    index_columns <- data.table::indices(data, vectors = TRUE)
    affected_indexes <- vapply(
        index_columns, function(columns) target %in% columns, logical(1)
    )
    suspendInterrupts({
        result <- patch()
        key_changed <- target %in% key_columns
        if (key_changed) data.table::setkeyv(data, NULL)
        if (key_changed || any(affected_indexes)) {
            retained <- index_columns[!affected_indexes]
            data.table::setindexv(data, NULL)
            for (columns in retained) data.table::setindexv(data, columns)
        }
        result
    })
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
    declared <- attr(values, "stata.string.storage", exact = TRUE)
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

# `generate` marks `gen()` and a new column through `:=`, the two Stata
# commands, whose bare double result takes Stata's `generate` default
# rather than the container mapping; see `.generate_storage()`.
.generated_column <- function(values, rows, row_count, caller = "gen()",
                              generate = FALSE) {
    message <- sprintf(
        "`%s` values must be numeric, logical, character, or a factor",
        caller
    )
    if (!is.null(dim(values))) stop(message, call. = FALSE)
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
        return(.generated_numeric(
            values, rows, row_count, caller, generate
        ))
    }
    stop(message, call. = FALSE)
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
    result
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
    .reject_data_table_subclass(data)
    data_table <- .ordinary_data_table(data)
    snapshot <- .reference_snapshot(data)
    source <- .as_mutation_data(snapshot, allow_grouped = TRUE)
    snapshot_columns <- source$columns
    snapshot_attributes <- attributes(snapshot)
    if (data_table) snapshot_attributes$.internal.selfref <- NULL
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
    if (data_table) data.table::setalloccol(columns)
    columns
}

# Reads one visible column without building a snapshot of the whole
# table. Physical columns of an ordinary overlay still live in the
# object itself, so they are read from there; generated columns and
# every column of a structural overlay come from the store. Returns the
# column wrapped in a list, or NULL when the name is not an exact match,
# which sends the caller back to the general snapshot path.
.reference_column <- function(data, name) {
    state <- .reference_state(data)
    if (is.null(state)) return(NULL)
    if (!isTRUE(state$physical_overlay)) {
        # Physical columns are read straight off the object; `.subset2()`
        # matches names exactly and returns NULL for a generated or absent
        # column, which the store lookup below then resolves.
        value <- .subset2(data, name)
        if (!is.null(value)) return(list(value))
    }
    if (exists(name, envir = state$columns, inherits = FALSE)) {
        return(list(state$columns[[name]]))
    }
    NULL
}

#' @export
`$.dtatools_ref_data` <- function(x, name) {
    found <- .reference_column(x, as.character(name))
    if (!is.null(found)) return(found[[1L]])
    call <- sys.call()
    call[[1L]] <- quote(`$`)
    call[[2L]] <- .reference_snapshot(x)
    eval(call, parent.frame())
}

#' @export
`[[.dtatools_ref_data` <- function(x, i, ..., exact = TRUE) {
    if (...length() == 0L && isTRUE(exact) && length(i) == 1L) {
        name <- if (is.character(i)) {
            i
        } else if (is.numeric(i) && !is.na(i)) {
            names <- .reference_names(x)
            if (i >= 1 && i <= length(names)) names[[i]] else NULL
        } else {
            NULL
        }
        if (!is.null(name)) {
            found <- .reference_column(x, name)
            if (!is.null(found)) return(found[[1L]])
        }
    }
    .reference_snapshot(x)[[i, ..., exact = exact]]
}

# `[.dtatools_ref_data` is defined in dibble.R beside its documentation:
# it is the bracket mutation entry as well as the snapshot delegate.

#' @export
names.dtatools_ref_data <- function(x) {
    .reference_names(x)
}

#' @export
length.dtatools_ref_data <- function(x) {
    state <- .reference_state(x)
    state$physical_count + state$generated_count
}

#' @export
dim.dtatools_ref_data <- function(x) {
    state <- .reference_state(x)
    c(state$nrow, state$physical_count + state$generated_count)
}

#' @export
dimnames.dtatools_ref_data <- function(x) {
    list(row.names(.reference_snapshot(x)), names(x))
}

#' @export
as.data.frame.dtatools_ref_data <- function(x, ...) {
    as.data.frame(.reference_snapshot(x), ...)
}

#' @export
as.matrix.dtatools_ref_data <- function(x, ...) {
    as.matrix(.reference_snapshot(x), ...)
}

#' @export
as.list.dtatools_ref_data <- function(x, ...) {
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

#' @export
print.dtatools_ref_data <- function(x, ...) {
    if (.skip_bracket_autoprint(x, sys.nframe(), sys.call(1L))) {
        return(invisible(x))
    }
    print(.reference_snapshot(x), ...)
    invisible(x)
}

# The replacement operators on a dibble write by reference, as `gen()`,
# `repl()`, and `:=` do. The ordinary tibble replacement runs on the
# snapshot, the changed columns are typed and promoted as `mutate()` types
# them, and the result's columns are installed into the dibble's own
# reference state, so the object every binding holds is the one that
# changed and R's rebinding in the calling frame is a no-op. That is what
# makes R's replacement-function forms by reference too: `val_labels(d$x)
# <- v` is ``d <- `$<-`(d, "x", `val_labels<-`(d$x, v))``, so a metadata
# setter used on a dibble's column inside a function reaches the caller's
# dataset and every alias of it (ADR 0023). A reference frame that is not
# a dibble gets the ordinary copy.
#' @export
`$<-.dtatools_ref_data` <- function(x, name, value) {
    result <- .reference_snapshot(x)
    result[[name]] <- value
    .install_replacement(x, result, value, "`$<-`")
}

#' @export
`[[<-.dtatools_ref_data` <- function(x, i, ..., value) {
    result <- .reference_snapshot(x)
    result[[i, ...]] <- value
    .install_replacement(x, result, value, "`[[<-`")
}

#' @export
`[<-.dtatools_ref_data` <- function(x, i, j, ..., value) {
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
    result <- if (is_dibble(x)) {
        .bracket_replace_promoting(snapshot, call, parent.frame())
    } else {
        eval(call, parent.frame())
    }
    .install_replacement(x, result, value, "`[<-`")
}

# Installs a replacement's result into the dibble itself. R
# shallow-duplicates a shared object before it dispatches a replacement,
# so `x` may be a copy of the object the caller's other bindings hold;
# the reference state names that object, and the result's columns are
# installed into it as `keep_vars()` installs a selection: into its
# physical list when capacity allows, or into a shallow rebuilt table.
# The installed object is returned for R's replacement assignment; other
# aliases keep the old complete table when rebuilding was necessary. Columns the replacement left
# alone are recognized by address and untouched; a changed column is
# typed by promotion from its prior storage, or as a new column; and one
# that is still the very vector the caller passed as `value` is wrapped
# copy-on-write, so a later `:=` through this dibble cannot reach the
# frame the vector came from.
.install_replacement <- function(x, result, value, caller) {
    if (!is_dibble(x)) return(result)
    if (!is.data.frame(result)) return(result)
    state <- .reference_state(x)
    if (nrow(result) != state$nrow) {
        stop(sprintf("%s cannot change a dibble's row count", caller),
             call. = FALSE)
    }
    names <- names(result)
    if (is.null(names) || anyNA(names) || any(names == "") ||
        anyDuplicated(names) > 0L) {
        stop(
            sprintf("%s needs unique, non-missing column names", caller),
            call. = FALSE
        )
    }
    target <- state$object
    if (is.null(target)) target <- x
    before <- .data_columns(target)
    typed <- .retype_changed_columns(result, before, caller)
    columns <- .data_columns(typed)
    shared <- .value_addresses(value)
    if (length(shared)) {
        for (index in seq_along(columns)) {
            if (rlang::obj_address(columns[[index]]) %in% shared) {
                columns[[index]] <- .metadata_copy(columns[[index]])
            }
        }
    }
    original <- .as_mutation_data(target, allow_grouped = TRUE)
    target <- .install_column_selection(target, original, columns)
    .sync_replacement_attributes(target, result)
    invisible(target)
}

.value_addresses <- function(value) {
    if (is.null(value)) return(character())
    if (is.data.frame(value) || (is.list(value) && !is.object(value))) {
        return(vapply(
            .plain_data_columns(value), rlang::obj_address, character(1)
        ))
    }
    rlang::obj_address(value)
}

# A replacement on a grouped snapshot goes through dplyr's `[<-` and
# `$<-` methods, which recompute or drop the groups, and `row.names<-` or
# `dimnames<-` may have changed the row names; the dibble takes the
# result's grouping, row names, and classes as its own.
.sync_replacement_attributes <- function(x, result) {
    state <- .reference_state(x)
    .Call(
        C_dtatools_set_attribute, x, "groups",
        attr(result, "groups", exact = TRUE)
    )
    .Call(
        C_dtatools_set_attribute, x, "row.names",
        attr(result, "row.names", exact = TRUE)
    )
    classes <- class(result)
    if (!identical(classes, state$classes)) {
        state$classes <- classes
        .Call(
            C_dtatools_set_attribute, x, "class",
            unique(c("dtatools_ref_data", classes))
        )
    }
    invisible(NULL)
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
            !is.null(attr(column, "stata.string.storage", exact = TRUE))) {
            text <- as.character(column)
            text[is.na(text)] <- ""
            text
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

# `names(d)[1] <- "k"` renames by reference, as `rename_vars()` does.
#' @export
`names<-.dtatools_ref_data` <- function(x, value) {
    result <- .reference_snapshot(x)
    names(result) <- value
    .install_replacement(x, result, NULL, "`names<-`")
}

#' @export
`dimnames<-.dtatools_ref_data` <- function(x, value) {
    result <- .reference_snapshot(x)
    dimnames(result) <- value
    .install_replacement(x, result, NULL, "`dimnames<-`")
}

#' @export
`row.names<-.dtatools_ref_data` <- function(x, value) {
    result <- .reference_snapshot(x)
    row.names(result) <- value
    .install_replacement(x, result, NULL, "`row.names<-`")
}

#' @export
as_tibble.dtatools_ref_data <- function(x, ...) {
    tibble::as_tibble(.reference_snapshot(x), ...)
}

#' @export
vec_proxy.dtatools_ref_data <- function(x, ...) {
    vctrs::vec_proxy(.reference_snapshot(x), ...)
}

#' @export
#' @export
vec_restore.dtatools_ref_data <- function(x, to, ...) {
    .close_dibble(to, vctrs::vec_restore(x, .reference_snapshot(to), ...))
}

#' @export
dplyr_reconstruct.dtatools_ref_data <- function(data, template) {
    .close_dibble(
        template,
        dplyr::dplyr_reconstruct(data, .reference_snapshot(template))
    )
}

# dplyr's grouped and rowwise row slicing, which `semi_join()`,
# `anti_join()`, and the `rows_*()` verbs use, builds its result without
# passing through `dplyr_reconstruct()`, so the dibble closes here.
#' @export
dplyr_row_slice.dtatools_ref_data <- function(data, i, ...) {
    .close_dibble(
        data, dplyr::dplyr_row_slice(.reference_snapshot(data), i, ...)
    )
}

# Likewise for column modification on a grouped dibble, which
# `rows_update()` and `rows_patch()` use: changed columns are typed as
# `mutate()` types them.
#' @export
dplyr_col_modify.dtatools_ref_data <- function(data, cols) {
    .typed_reference_replacement(
        data, dplyr::dplyr_col_modify(.reference_snapshot(data), cols),
        "`dplyr_col_modify()`"
    )
}

#' @export
select.dtatools_ref_data <- function(.data, ...) {
    .close_dibble(.data, dplyr::select(.reference_snapshot(.data), ...))
}

.reference_delegate <- function(data, call, generic, environment) {
    call[[1L]] <- generic
    call[[2L]] <- .reference_snapshot(data)
    eval(call, environment)
}

# Base and dplyr methods share one boundary: reference state is
# materialized to a shallow, complete data-frame snapshot before the
# ordinary implementation runs. The result follows copy-on-modify. A
# dibble input closes the result back into a dibble, so a dataset
# operation on a dibble yields a dibble; any other reference frame gets
# the ordinary result.
.closed_reference_verb <- function(data, call, generic, environment) {
    .close_dibble(data, .reference_delegate(data, call, generic, environment))
}

#' @export
with.dtatools_ref_data <- function(data, expr, ...) {
    .reference_delegate(data, sys.call(), base::with, parent.frame())
}

#' @export
within.dtatools_ref_data <- function(data, expr, ...) {
    .typed_reference_verb(
        data, sys.call(), base::within, parent.frame(), "`within()`"
    )
}

#' @export
subset.dtatools_ref_data <- function(x, ...) {
    .closed_reference_verb(x, sys.call(), base::subset, parent.frame())
}

#' @export
transform.dtatools_ref_data <- function(`_data`, ...) {
    .typed_reference_verb(
        `_data`, sys.call(), base::transform, parent.frame(), "`transform()`"
    )
}

#' @export
rbind.dtatools_ref_data <- function(..., deparse.level = 1) {
    inputs <- list(...)
    values <- lapply(inputs, .reference_snapshot)
    .close_dibble(inputs[[1L]], do.call(
        base::rbind, c(values, list(deparse.level = deparse.level))
    ))
}

#' @export
cbind.dtatools_ref_data <- function(..., deparse.level = 1) {
    inputs <- list(...)
    values <- lapply(inputs, .reference_snapshot)
    .close_dibble(inputs[[1L]], do.call(
        base::cbind, c(values, list(deparse.level = deparse.level))
    ))
}

#' @export
arrange.dtatools_ref_data <- function(.data, ..., .by_group = FALSE) {
    .closed_reference_verb(.data, sys.call(), dplyr::arrange, parent.frame())
}

#' @export
filter.dtatools_ref_data <- function(
    .data, ..., .by = NULL, .preserve = FALSE
) {
    .closed_reference_verb(.data, sys.call(), dplyr::filter, parent.frame())
}

#' @export
slice.dtatools_ref_data <- function(.data, ..., .by = NULL, .preserve = FALSE) {
    .closed_reference_verb(.data, sys.call(), dplyr::slice, parent.frame())
}

#' @export
relocate.dtatools_ref_data <- function(
    .data, ..., .before = NULL, .after = NULL
) {
    .closed_reference_verb(.data, sys.call(), dplyr::relocate, parent.frame())
}

#' @export
rename.dtatools_ref_data <- function(.data, ...) {
    .closed_reference_verb(.data, sys.call(), dplyr::rename, parent.frame())
}

#' @export
mutate.dtatools_ref_data <- function(
    .data, ..., .by = NULL, .keep = c("all", "used", "unused", "none"),
    .before = NULL, .after = NULL
) {
    .typed_mask_verb(
        .data, "mutate", rlang::enquos(..., .ignore_empty = "all"),
        list(
            .by = rlang::enquo(.by), .keep = .keep,
            .before = rlang::enquo(.before), .after = rlang::enquo(.after)
        ),
        "mutate()"
    )
}

#' @export
transmute.dtatools_ref_data <- function(.data, ...) {
    .typed_mask_verb(
        .data, "transmute", rlang::enquos(..., .ignore_empty = "all"),
        list(), "transmute()"
    )
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

# A column a dibble holds as is: one carrying Stata storage; a factor,
# which `save_dta()` writes as a value-labelled `long`; or a bare logical.
# Stata has no boolean type, and typing a flag as `byte` would break
# `filter(data, flag)`, `which(flag)`, and `where = flag`, so logicals
# stay logical and become `byte` only when written. A `gen()` string
# carries its declaration as an attribute without the `dta_string`
# class, so the attribute is the test for strings.
.dta_typed_column <- function(column) {
    inherits(column, c("dta_numeric", "dta_temporal", "factor")) ||
        (typeof(column) == "logical" && !is.object(column)) ||
        (is.character(column) && .string_declaration_holds(column))
}

# Whether a character column's `stata.string.storage` declaration is
# valid for its values: well formed, wide enough, and with no `NA`, which
# Stata strings spell `""`. A join or `rbind()` can carry a declaration
# onto values it no longer describes, and such a column is retyped rather
# than trusted. That includes a `dta_string` vector: `full_join()` and
# `bind_rows()` pad one with `NA` while vctrs keeps its class, so the
# class is no proof. A compact dictionary string has no `NA` by
# construction and its width is read from the dictionary, so it is
# checked without being materialized.
.string_declaration_holds <- function(column) {
    declared <- attr(column, "stata.string.storage", exact = TRUE)
    if (is.null(declared)) return(FALSE)
    valid <- is.character(declared) && length(declared) == 1L &&
        !is.na(declared) && (identical(declared, "strL") || grepl(
            "^str([1-9]|[1-9][0-9]{1,2}|1[0-9]{3}|20[0-3][0-9]|204[0-5])$",
            declared
        ))
    if (!valid) return(FALSE)
    if (.is_unmaterialized_dictstring(column)) {
        return(.dta_string_storage_width(declared) >=
            max(1L, .dictstring_max_width(column)))
    }
    if (anyNA(column)) return(FALSE)
    .dta_string_storage_width(declared) >=
        .dta_string_required_width(column)
}

# A column no Stata storage can hold: raw, list, complex, a matrix, a
# classed character other than a Stata string, or a classed numeric such
# as `difftime` or `integer64` whose values are not Stata's. A dibble
# carries it unchanged, and `save_dta()` refuses it with its own message.
# `gen()` is stricter and rejects such a result, because it is the Stata
# command. A `dta_string` whose declaration no longer holds is typable:
# it is retyped from its values.
.dta_untypable_column <- function(column) {
    if (!is.null(dim(column))) return(TRUE)
    if (typeof(column) == "character") {
        return(is.object(column) && !inherits(column, "dta_string"))
    }
    if (!(typeof(column) %in% c("logical", "integer", "double"))) {
        return(TRUE)
    }
    !.generated_numeric_class_supported(column)
}

# The Stata-typed form of one column entering a dibble. A typed column is
# returned as is. A compact Arrow string is declared through a metadata
# proxy with the width read from its dictionary, so it stays compact and
# the source vector is untouched. Anything else takes `gen()`'s storage
# for its values. `caller` names the entry point in errors.
.typed_column <- function(column, row_count, caller) {
    if (.dta_typed_column(column)) return(column)
    if (.is_unmaterialized_dictstring(column)) {
        storage <- .normalize_dta_string_storage(
            NULL, .dictstring_max_width(column)
        )
        proxy <- .metadata_copy(column)
        attr(proxy, "stata.string.storage") <- storage
        class(proxy) <- c("dta_string", "vctrs_vctr", "character")
        return(proxy)
    }
    if (is.character(column) &&
        !is.null(attr(column, "stata.string.storage", exact = TRUE))) {
        # A stale declaration: `NA` becomes `""`, the width is redone from
        # the values, and the variable's other metadata comes along.
        text <- as.character(column)
        text[is.na(text)] <- ""
        kept <- attributes(column)
        kept[c("names", "class", "stata.string.storage")] <- NULL
        if (length(kept)) attributes(text) <- c(attributes(text), kept)
        column <- text
    }
    .generated_column(column, NULL, row_count, caller)
}

# Types every untyped column of a data frame so that a dibble's columns
# all carry Stata storage. Typed columns are left as the same vectors, so
# compact columns from a reader stay compact.
.type_dibble_columns <- function(data, caller = "as_dibble()") {
    row_count <- nrow(data)
    column_names <- names(data)
    for (index in seq_along(column_names)) {
        column <- .subset2(data, index)
        typed <- .typed_column_named(
            column, row_count, caller, column_names[[index]]
        )
        if (!identical(rlang::obj_address(typed), rlang::obj_address(column))) {
            data[[index]] <- typed
        }
    }
    data
}

# The same for a column entering a dibble from construction or a verb,
# where a column no Stata storage can hold passes through unchanged.
.typed_column_named <- function(column, row_count, caller, name) {
    if (.dta_typed_column(column) ||
        .is_unmaterialized_dictstring(column) ||
        !.dta_untypable_column(column)) {
        return(.typed_column(column, row_count, caller))
    }
    column
}

# The Stata storage a column declares, numeric or string, or `NULL` when
# it declares none.
.promotion_storage_label <- function(column) {
    if (typeof(column) == "character") {
        attr(column, "stata.string.storage", exact = TRUE)
    } else {
        .declared_dta_storage(column)
    }
}

# Stata's `replace` announces a widening as `variable x was byte now
# int`, and `repl()` translates that command, so it says the same. Only a
# real change of declared storage is reported; a column that keeps its
# storage says nothing, as Stata does.
.report_storage_promotion <- function(name, prior, promoted) {
    was <- .promotion_storage_label(prior)
    now <- .promotion_storage_label(promoted)
    if (is.null(was) || is.null(now) || identical(was, now)) {
        return(invisible(NULL))
    }
    message(sprintf("variable `%s` was %s now %s", name, was, now))
    invisible(NULL)
}

# Column `values` that replaced `prior` in a dibble. A prior column with
# declared storage keeps it when the new values fit, as Stata's `replace`
# does. When they do not, the column takes the narrowest storage that
# holds every new value exactly, without ever narrowing the integers the
# column can hold. `conformance/stata/replace-promotion.do` records what
# Stata does, and the two agree except on precision: a `float` given a
# value needing binary64 keeps `float` in Stata, which rounds it, and
# goes to `double` here, which does not. Prior variable metadata is
# restored on the result. Other
# combinations, including a change of kind between numeric and string,
# take the storage a fresh column would. `declared` names storage the
# caller has already settled on, such as a `:=` right-hand side's, and
# stands in for the prior column's.
.promoted_column <- function(values, prior, row_count, caller,
                             declared = NULL) {
    # A bare logical replacing a Stata numeric is a fitting replacement,
    # as `replace x = x > 1` is in Stata, so it keeps the column's
    # storage rather than turning the column logical.
    logical_over_numeric <- typeof(values) == "logical" &&
        !is.object(values) && inherits(prior, "dta_numeric") &&
        !inherits(prior, "dta_temporal")
    # An explicit `dta_*()` or arithmetic result already carries the
    # storage the user asked for; a column no storage holds passes through.
    if (!logical_over_numeric &&
        (.dta_typed_column(values) || .dta_untypable_column(values))) {
        return(values)
    }
    if (is.character(values) &&
        !is.null(attr(values, "stata.string.storage", exact = TRUE))) {
        # A stale declaration is redone from the values.
        attr(values, "stata.string.storage") <- NULL
    }
    if (!.promotable_pair(values, prior)) {
        return(.typed_column(values, row_count, caller))
    }
    if (typeof(prior) == "character") {
        text <- as.character(values)
        text[is.na(text)] <- ""
        if (is.null(declared)) {
            declared <- attr(prior, "stata.string.storage", exact = TRUE)
        }
        required <- .dta_string_required_width(text)
        storage <- if (.dta_string_storage_width(declared) >= required) {
            declared
        } else {
            .normalize_dta_string_storage(NULL, required)
        }
        return(.new_dta_string(enc2utf8(text), storage, prior))
    }
    doubles <- as.double(values)
    if (is.null(declared)) declared <- .declared_dta_storage(prior)
    # Promotion only widens: the search starts at the declared storage,
    # so a `dta_float()` value beside a retained integer float cannot
    # hold goes to `double` rather than back to `long`.
    storage <- if (.dta_storage_holds(doubles, declared)) {
        declared
    } else {
        .narrowest_dta_storage(doubles, from = declared)
    }
    .restore_dta_metadata(
        .construct_dta_numeric(doubles, NULL, storage), prior, storage
    )
}

# Whether replacement `values` for the selected `rows` fit `target`'s
# declared storage. Pairs the promotion rule does not cover report `TRUE`
# so the strict replacement path handles or refuses them as before.
.replacement_fits <- function(values, target, rows, value_mode) {
    if (!.promotable_pair(values, target)) return(TRUE)
    # The dictionary's widest entry answers the question for a compact
    # Arrow string without populating its shared cache, which the
    # `as.character()` below would. Only a dictionary too wide for the
    # target has to look at the values themselves.
    if (typeof(target) == "character" &&
        .is_unmaterialized_dictstring(values)) {
        declared <- attr(target, "stata.string.storage", exact = TRUE)
        if (.dta_string_storage_width(declared) >=
            max(1L, .dictstring_max_width(values))) {
            return(TRUE)
        }
    }
    if (identical(value_mode, "row") && !is.null(rows)) {
        slice_rows <- if (inherits(rows, "dta_numeric")) {
            .dta_data(rows)
        } else {
            rows
        }
        values <- vctrs::vec_slice(values, slice_rows)
    }
    if (typeof(target) == "character") {
        text <- as.character(values)
        text[is.na(text)] <- ""
        declared <- attr(target, "stata.string.storage", exact = TRUE)
        return(.dta_string_storage_width(declared) >=
            .dta_string_required_width(text))
    }
    .dta_storage_holds(
        as.double(vctrs::vec_data(values)), .declared_dta_storage(target)
    )
}

# The whole column after `values` replace the selected `rows` of
# `target`, typed by promotion from `target`'s storage, or from
# `declared` when the right-hand side settled a wider one.
.promoted_replacement <- function(values, target, rows, value_mode,
                                  row_count, declared = NULL) {
    current <- if (typeof(target) == "character") {
        text <- as.character(target)
        text[is.na(text)] <- ""
        text
    } else {
        as.double(.dta_snapshot(target))
    }
    replacement <- if (typeof(target) == "character") {
        text <- as.character(values)
        text[is.na(text)] <- ""
        text
    } else {
        as.double(vctrs::vec_data(values))
    }
    positions <- if (is.null(rows)) {
        seq_len(row_count)
    } else if (inherits(rows, "dta_numeric")) {
        .dta_data(rows)
    } else {
        rows
    }
    current[positions] <- if (identical(value_mode, "row")) {
        replacement[positions]
    } else {
        replacement
    }
    .promoted_column(current, target, row_count, "`:=`", declared)
}

# The storage a `:=` right-hand side declares, through a `dta_*()` call
# or Stata-typed arithmetic, when it is wider than `target`'s: the value
# the user typed names the storage they want, and a column that holds
# both must be at least that wide. `NULL` when the right-hand side is
# bare, declares the target's storage or narrower, or is not of the
# target's kind, so the ordinary fit check decides.
.wider_declared_storage <- function(values, target) {
    if (!.promotable_pair(values, target)) return(NULL)
    if (typeof(target) == "character") {
        declared <- attr(values, "stata.string.storage", exact = TRUE)
        current <- attr(target, "stata.string.storage", exact = TRUE)
        if (is.null(declared) || !is.character(declared) ||
            length(declared) != 1L || is.na(declared)) {
            return(NULL)
        }
        wider <- .dta_string_storage_width(declared) >
            .dta_string_storage_width(current)
        return(if (wider) declared else NULL)
    }
    if (!inherits(values, "dta_numeric")) return(NULL)
    declared <- match(.declared_dta_storage(values), .dta_storage)
    current <- match(.declared_dta_storage(target), .dta_storage)
    if (is.na(declared) || is.na(current) || declared <= current) {
        return(NULL)
    }
    .dta_storage[[declared]]
}

# `prior` has declared storage of the same kind as `values`: numeric for
# numeric, string for string. Temporal and factor columns are not
# promoted; they are retyped from their new values.
.promotable_pair <- function(values, prior) {
    if (is.factor(values) || !is.null(dim(values))) return(FALSE)
    if (is.character(prior) &&
        !is.null(attr(prior, "stata.string.storage", exact = TRUE))) {
        return(is.character(values))
    }
    if (!inherits(prior, "dta_numeric") ||
        inherits(prior, "dta_temporal")) return(FALSE)
    typeof(values) %in% c("logical", "integer", "double") &&
        (!is.object(values) || inherits(values, "dta_numeric"))
}

.dta_storage_holds <- function(doubles, storage) {
    codes <- .tab_missing_codes(doubles)
    observed <- is.na(codes)
    if (any(!is.na(codes) & codes == 256L)) return(FALSE)
    if (any(.invalid_dta_observed(doubles, observed, storage))) {
        return(FALSE)
    }
    if (!identical(storage, "float") || !any(observed)) return(TRUE)
    candidate <- doubles[observed]
    rounded <- as.double(.construct_dta_numeric(candidate, NULL, "float"))
    all(rounded == candidate)
}

.narrowest_dta_storage <- function(doubles, from = "byte") {
    start <- match(from, .dta_storage)
    if (is.na(start)) start <- 1L
    ladder <- .dta_storage[start:length(.dta_storage)]
    # `float` carries 24 bits of integer precision and `long` carries 31,
    # so `long` to `float` narrows the integers the column can hold even
    # when the values in hand happen to be float-exact, and it leaves a
    # column that silently rounds the next long-range integer written to
    # it. Stata's `replace` sends an overflowing `long` to `double` for
    # the same reason, and the arithmetic lattice in `.dta_promote()`
    # already pairs `long` with `float` as `double`. `byte` and `int` are
    # unaffected: their whole ranges are float-exact.
    if (identical(from, "long")) ladder <- setdiff(ladder, "float")
    for (storage in ladder) {
        if (.dta_storage_holds(doubles, storage)) return(storage)
    }
    "double"
}

# After an operation on a dibble's snapshot, every column that is not the
# same vector as before is typed: a new column as `gen()` would type it, a
# replaced column by promotion from its prior storage. Columns the
# operation left alone are recognized by address and untouched.
.retype_changed_columns <- function(result, before, caller) {
    result_names <- names(result)
    row_count <- nrow(result)
    for (index in seq_along(result_names)) {
        column <- .subset2(result, index)
        prior <- before[[result_names[[index]]]]
        if (!is.null(prior) &&
            identical(rlang::obj_address(prior), rlang::obj_address(column))) {
            next
        }
        typed <- if (is.null(prior)) {
            .typed_column_named(
                column, row_count, caller, result_names[[index]]
            )
        } else {
            .promoted_column(column, prior, row_count, caller)
        }
        if (!identical(rlang::obj_address(typed), rlang::obj_address(column))) {
            result[[index]] <- typed
        }
    }
    result
}

# A dataset operation on a dibble returns a dibble; on any other
# reference frame it returns what the ordinary implementation did. A
# non-data-frame result, such as `with()`'s, is returned as is.
.close_dibble <- function(data, result, caller = "as_dibble()",
                          sources = NULL) {
    if (!is_dibble(data) || !is.data.frame(result) || is_dibble(result)) {
        return(result)
    }
    .as_dibble(.isolate_shared_columns(result, sources), caller)
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
    for (index in seq_len(length(result))) {
        column <- .subset2(result, index)
        if (isolate_all || rlang::obj_address(column) %in% source_addresses) {
            result[[index]] <- .metadata_copy(column)
        }
    }
    result
}

# `transform()`, `within()`, `group_modify()`, and the replacement
# operators on a dibble: the ordinary implementation runs on the
# snapshot, then changed columns are typed and the result is closed back
# into a dibble. Other reference frames get the plain result.
.typed_reference_verb <- function(data, call, generic, environment,
                                  caller) {
    if (!is_dibble(data)) {
        return(.reference_delegate(data, call, generic, environment))
    }
    before <- .data_columns(data)
    result <- .reference_delegate(data, call, generic, environment)
    .close_dibble(
        data, .retype_changed_columns(result, before, caller), caller
    )
}

# The data-masking verbs: each `...` expression is typed as its result
# enters the data mask, so a later expression, the row comparison of
# `distinct()`, or the grouping of `group_by()` and `nest_by()` sees the
# Stata column the result will hold. A bare double `y = c(NA, 1)` is a
# Stata `double` when `z = y > 0` reads it, so `z` is `TRUE` where Stata's
# missing order says so, and `NA` and `""` in a computed string key form
# one group.
#
# The hook is a `(` call around each expression, evaluated in an
# environment where `(` is the typer; `(` is the one call head R's
# deparser does not show as a function, so `mutate(d, x + 1)` still names
# its column `x + 1` through the one-column frame below, and dplyr's
# "In argument" bullets are relabelled. Existing-column symbols, `.data`
# references, and `NULL` are left alone: they select or remove columns
# rather than compute them. Caller-backed symbols and `across()` results
# are typed before later expressions use them. An unnamed vector is returned
# as a one-column frame under its original expression name, so dplyr sees
# collisions and overwrites during mask evaluation, before closing the result.
# `if_any()` and `if_all()` return logicals and keep dplyr's expansion.
.typed_mask_verb <- function(data, generic, dots, arguments, caller) {
    # The call is evaluated where `generic` names the dplyr function, so
    # dplyr reports errors as "Error in `mutate()`" rather than against
    # an inlined function object.
    environment <- new.env(parent = baseenv())
    environment[[generic]] <- getExportedValue("dplyr", generic)
    if (!is_dibble(data)) {
        call <- rlang::call2(generic, .reference_snapshot(data), !!!dots,
                             !!!arguments)
        return(eval(call, environment))
    }
    before <- .data_columns(data)
    wrapped <- .wrap_mask_expressions(dots, before, caller)
    call <- rlang::call2(
        generic, .reference_snapshot(data), !!!wrapped$dots, !!!arguments
    )
    result <- .relabel_mask_conditions(
        eval(call, environment), wrapped$labels
    )
    .close_dibble(
        data, .retype_changed_columns(result, before, caller), caller
    )
}

.wrap_mask_expressions <- function(dots, before, caller) {
    names <- rlang::names2(dots)
    labels <- character()
    for (index in seq_along(dots)) {
        quosure <- dots[[index]]
        if (!.mask_expression_typable(quosure, before)) next
        name <- names[[index]]
        typer <- .mask_value_typer(
            before, caller, if (nzchar(name)) name else NULL,
            .mask_expression_label(quosure)
        )
        environment <- new.env(parent = rlang::quo_get_env(quosure))
        environment[["("]] <- typer
        wrapped <- rlang::new_quosure(
            rlang::call2("(", quosure), environment
        )
        inner <- .mask_expression_label(quosure)
        outer <- .mask_expression_label(wrapped)
        if (nzchar(name)) {
            labels[[paste0(name, " = ", outer)]] <- paste0(name, " = ", inner)
        } else {
            labels[[outer]] <- inner
        }
        dots[[index]] <- wrapped
    }
    list(dots = dots, labels = labels)
}

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

# Types one result as it enters the mask. A named expression that
# overwrites a column promotes from that column; an unnamed data frame
# result is unpacked by dplyr, so each of its columns is typed against
# the column of the same name.
.mask_value_typer <- function(before, caller, name, label) {
    force(name)
    force(label)
    function(value) {
        if (is.null(value)) return(NULL)
        # rlang's mask top holds the live column bindings, including earlier
        # clauses. Read only the target; caller bindings must not supply it.
        mask <- rlang::env_get(parent.frame(), ".top_env", default = NULL)
        prior <- function(target) {
            if (is.environment(mask)) {
                rlang::env_get(mask, target, default = NULL)
            } else {
                before[[target]]
            }
        }
        if (is.data.frame(value)) {
            if (!is.null(name)) return(value)
            columns <- names(value)
            for (index in seq_along(columns)) {
                value[[index]] <- .typed_mask_value(
                    .subset2(value, index), prior(columns[[index]]),
                    caller
                )
            }
            return(value)
        }
        target <- if (is.null(name)) label else name
        result <- .typed_mask_value(value, prior(target), caller)
        if (!is.null(name)) return(result)
        vctrs::new_data_frame(
            stats::setNames(list(result), target), n = vctrs::vec_size(result)
        )
    }
}

.typed_mask_value <- function(value, prior, caller) {
    if (is.null(prior)) {
        return(.typed_column_named(value, length(value), caller, NULL))
    }
    .promoted_column(value, prior, length(value), caller)
}

# dplyr's "In argument: `y = (x + 1)`." bullets name the wrapped
# expression; the parentheses are stripped so the message reads as the
# user wrote the call.
.relabel_mask_conditions <- function(expression, labels) {
    if (length(labels) == 0L) return(expression)
    relabel <- function(condition) {
        for (field in c("message", "body")) {
            text <- condition[[field]]
            if (!is.character(text)) next
            from <- paste0("In argument: `", names(labels), "`.")
            to <- paste0("In argument: `", labels, "`.")
            condition[[field]] <- vapply(text, function(message) {
                if (is.na(message)) return(message)
                # Warnings can arrive with their cause already rendered into
                # the message. Rewrite only the generated annotation before
                # that cause, never the user's warning text below it.
                lines <- strsplit(paste0(message, "\n"), "\n", fixed = TRUE)[[1L]]
                for (index in seq_along(lines)) {
                    line <- lines[[index]]
                    if (startsWith(line, "Caused by ")) break
                    prefix <- if (startsWith(line, "\u2139 ")) "\u2139 " else
                        if (startsWith(line, "i ")) "i " else ""
                    annotation <- substring(line, nchar(prefix) + 1L)
                    replacement <- match(annotation, from)
                    if (!is.na(replacement)) {
                        lines[[index]] <- paste0(prefix, to[[replacement]])
                    }
                }
                paste(lines, collapse = "\n")
            }, character(1), USE.NAMES = FALSE)
            names(condition[[field]]) <- names(text)
        }
        condition
    }
    withCallingHandlers(
        tryCatch(expression, error = function(condition) {
            rlang::cnd_signal(relabel(condition))
        }),
        warning = function(condition) {
            rlang::cnd_signal(relabel(condition))
            invokeRestart("muffleWarning")
        }
    )
}

.typed_reference_replacement <- function(data, result, caller) {
    if (!is_dibble(data)) return(result)
    before <- .data_columns(data)
    .close_dibble(
        data, .retype_changed_columns(result, before, caller), caller
    )
}

# Grouping changes only dplyr metadata, so a dibble stays a dibble: the
# grouped or ungrouped snapshot is closed again, and `state$classes` then
# records the grouping for later snapshots. The result is a fresh object
# either way, so the mark never touches the caller's dataset.
.regroup_reference_data <- function(data, result) {
    .close_dibble(data, result)
}

#' @export
group_by.dtatools_ref_data <- function(
    .data, ..., .add = FALSE,
    .drop = dplyr::group_by_drop_default(.data)
) {
    # `group_by(d, g = x > 1)` computes a key as `mutate()` would, and
    # the key is typed before the groups form, so `NA` and `""` in a
    # computed string key make one group.
    .typed_mask_verb(
        .data, "group_by", rlang::enquos(..., .ignore_empty = "all"),
        list(.add = .add, .drop = .drop), "`group_by()`"
    )
}

#' @export
summarise.dtatools_ref_data <- function(
    .data, ..., .by = NULL, .groups = NULL
) {
    .typed_mask_verb(
        .data, "summarise", rlang::enquos(..., .ignore_empty = "all"),
        list(.by = rlang::enquo(.by), .groups = .groups), "`summarise()`"
    )
}

#' @export
distinct.dtatools_ref_data <- function(.data, ..., .keep_all = FALSE) {
    # `distinct(d, y = x * 2)` computes as `mutate()` does; the computed
    # key is typed before rows are compared.
    .typed_mask_verb(
        .data, "distinct", rlang::enquos(..., .ignore_empty = "all"),
        list(.keep_all = .keep_all), "`distinct()`"
    )
}

#' @export
reframe.dtatools_ref_data <- function(.data, ..., .by = NULL) {
    .typed_mask_verb(
        .data, "reframe", rlang::enquos(..., .ignore_empty = "all"),
        list(.by = rlang::enquo(.by)), "`reframe()`"
    )
}

#' @export
group_modify.dtatools_ref_data <- function(.data, .f, ..., .keep = FALSE) {
    .typed_reference_verb(
        .data, sys.call(), dplyr::group_modify, parent.frame(),
        "`group_modify()`"
    )
}

#' @export
nest_by.dtatools_ref_data <- function(.data, ..., .key = "data",
                                      .keep = FALSE) {
    .typed_mask_verb(
        .data, "nest_by", rlang::enquos(..., .ignore_empty = "all"),
        list(.key = .key, .keep = .keep), "`nest_by()`"
    )
}

#' @export
group_nest.dtatools_ref_data <- function(.tbl, ..., .key = "data",
                                         keep = FALSE) {
    .typed_mask_verb(
        .tbl, "group_nest", rlang::enquos(..., .ignore_empty = "all"),
        list(.key = .key, keep = keep), "`group_nest()`"
    )
}

#' @export
ungroup.dtatools_ref_data <- function(x, ...) {
    .regroup_reference_data(x, .reference_delegate(
        x, sys.call(), dplyr::ungroup, parent.frame()
    ))
}

#' @export
rowwise.dtatools_ref_data <- function(data, ...) {
    .regroup_reference_data(data, .reference_delegate(
        data, sys.call(), dplyr::rowwise, parent.frame()
    ))
}
