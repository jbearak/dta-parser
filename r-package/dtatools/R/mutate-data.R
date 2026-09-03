#' Generate and replace variables by reference
#'
#' `gen()` and `replace_values()` modify a data frame or tibble by reference.
#' `repl()` is a direct alias for `replace_values()`. The return value is the
#' supplied dataset, invisibly, so assignment is neither needed nor advised.
#' Aliases of the dataset or the same target vector observe later generation
#' and replacement. This includes column-only subsets that share their column
#' payload. Row subsets have new payloads and remain independent. Use
#' `copy_data()` when isolation is required. Generic ALTREP columns created by
#' base R or another package are detached to ordinary vectors before
#' replacement because their private caches cannot be invalidated safely.
#' Aliases to the same dataset object observe the installed vector. A
#' standalone alias to the former generic ALTREP column, including one held by
#' a previously created subset, remains unchanged.
#' `gen()` attaches package-owned reference state to the same data-frame or
#' tibble object. Existing columns remain in the data frame;
#' generated columns live in the attached state until an ordinary R assignment
#' materializes a complete copy. This lets `gen()` grow the visible column set
#' without searching for or rebinding a name in the caller. Base extraction and
#' data-mask helpers, core dplyr verbs, tibble conversion, package writers, and
#' metadata helpers operate on the complete visible dataset. The delegated
#' dplyr verbs are `arrange()`, `distinct()`, `filter()`, `group_by()`,
#' `mutate()`, `relocate()`, `rename()`, `rowwise()`, `select()`, `slice()`,
#' `summarise()`, `transmute()`, and `ungroup()`. Consumers that
#' bypass S3 methods and inspect a data frame's internal column-pointer array do
#' not see generated columns; pass `as.data.frame(data)` or
#' `tibble::as_tibble(data)` to such a consumer. This includes non-generic
#' combiners such as `dplyr::bind_rows()` and other dplyr verbs. Base `rbind()`
#' and `cbind()` delegate when a reference dataset is the first argument; when
#' it is later, convert it explicitly because base dispatch has already chosen
#' the ordinary data-frame method.
#' `unclass()` and direct inspection of internal attributes are likewise not
#' supported ways to access generated columns.
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
#' in Stata's total order for `stata_*()` columns (finite values, then `.`,
#' then `.a` through `.z`), and then groups by those same columns, so the
#' rows within each group are the sorted rows and `.n` follows the sort.
#' Stata's parenthesized sort-only keys are not supported: `bysort id
#' (date):` is an `arrange()` or `reorder_dta_rows()` line followed by
#' `by = id`. Group identity uses Stata value identity for `stata_*()`
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
#' `after()` placement. A declared `dta_*()` result keeps its numeric storage;
#' otherwise logical, integer, double, and `Date` results use Stata `float`
#' storage. Ordinary `POSIXct` results use Stata `double` storage so their
#' millisecond datetime representation is not rounded. `Date` and `POSIXct`
#' results retain their temporal class and receive the corresponding Stata
#' temporal declaration. Standard `haven_labelled` results preserve their label
#' metadata. Other classed numeric results, including `difftime` and
#' `bit64::integer64`, are rejected because their physical representation does
#' not have Stata numeric semantics. Convert them explicitly to a bare numeric
#' or one of the supported labelled, temporal, or Stata types before generation.
#' Character results keep a valid declared `stata.string.storage`. Otherwise,
#' they use the smallest `str1` through `str2045` width that fits, or `strL`
#' above 2,045 UTF-8 bytes. Numeric rows excluded by `where` contain
#' system missing. Excluded string rows contain `""`, Stata's string missing.
#' Wrap the value expression in a Stata constructor to request explicit numeric
#' storage. Stata `[in]` and `:lblname` authoring are not supported; the
#' `by varlist:` prefix is `by`/`bysort`.
#' Unlike Stata's default `replace`, `replace_values()` never promotes a target
#' to wider storage. It rejects values that do not fit the declared storage.
#' Character `NA` replacement values are normalized to `""`, Stata's string
#' missing value.
#'
#' The table records the deliberate first-release choices relative to Stata's
#' `generate [type] newvar = exp [if] [in]` command.
#'
#' \tabular{lll}{
#' Topic \tab Stata \tab dtatools \cr
#' Existing name \tab Error \tab Error before mutation \cr
#' Numeric default \tab `float`, or `double` after `set type` \tab `float`; `POSIXct` uses `double` \cr
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
                           bysort = NULL) {
    arguments <- .mutation_arguments(
        substitute(...()), rlang::enquo(where), missing(where),
        function() .capture_positional_pair(...),
        function() .capture_positional_triple(...),
        function() rlang::enquos(..., .ignore_empty = "none"),
        function() rlang::enquos0(...)
    )
    # `missing()` keeps the two extra quosure captures off the ungrouped
    # path, which `repl()` in a loop depends on.
    .mutate_data(
        data, arguments$variable, arguments$values, arguments$where,
        generate = FALSE,
        by = if (missing(by)) NULL else rlang::enquo(by),
        bysort = if (missing(bysort)) NULL else rlang::enquo(bysort)
    )
}

#' @rdname replace_values
#' @export
repl <- replace_values

#' @rdname replace_values
#' @export
gen <- function(data, ..., where = NULL, by = NULL, bysort = NULL) {
    arguments <- .mutation_arguments(
        substitute(...()), rlang::enquo(where), missing(where),
        function() .capture_positional_pair(...),
        function() .capture_positional_triple(...),
        function() rlang::enquos(..., .ignore_empty = "none"),
        function() rlang::enquos0(...)
    )
    .mutate_data(
        data, arguments$variable, arguments$values, arguments$where,
        generate = TRUE,
        by = if (missing(by)) NULL else rlang::enquo(by),
        bysort = if (missing(bysort)) NULL else rlang::enquo(bysort)
    )
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

.reference_state <- function(data) {
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

.new_reference_state <- function(data) {
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
    state
}

.new_structural_reference_state <- function(columns, row_count, classes) {
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

.mark_reference_data <- function(data, state) {
    classes <- unique(c("dtatools_ref_data", state$classes))
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
    if (!inherits(value, "stata_numeric") || length(value) != row_count ||
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
    scalar <- .stata_compare_scalar(value)
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
        if (inherits(left_column, "stata_temporal") &&
            inherits(right_column, "stata_temporal") &&
            !identical(
                .stata_temporal_kind(left_column),
                .stata_temporal_kind(right_column)
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
    .stata_compare(plan$op, plan$original_left, plan$original_right)
}

.fused_replacement_plan <- function(values, target, row_count) {
    native_numeric <- inherits(target, "stata_numeric") &&
        !inherits(target, "stata_temporal") &&
        typeof(values) %in% c("logical", "integer", "double") &&
        (!is.object(values) || inherits(values, "stata_numeric"))
    native_temporal <- inherits(target, "stata_temporal") &&
        ((inherits(target, "stata_date") && inherits(values, "Date")) ||
         (inherits(target, "stata_datetime") &&
          inherits(values, "POSIXct")))
    if ((!native_numeric && !native_temporal) || is.factor(values) ||
        !is.null(dim(values))) {
        return(NULL)
    }
    size <- vctrs::vec_size(values)
    if (size == 1L) {
        scalar <- .stata_compare_scalar(values)
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
    classified <- if (inherits(value, .stata_metadata_vector_class)) {
        .stata_metadata_vector_base(value)
    } else value
    stata_positions <- inherits(classified, "stata_numeric") &&
        !inherits(classified, "stata_temporal")
    if (!is.null(dim(classified)) ||
        (!is.logical(classified) &&
         (!is.numeric(classified) ||
          (is.object(classified) && !stata_positions)))) {
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
        text <- if (inherits(piece, "stata_numeric")) {
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
                              selected = NULL) {
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
        } else if (inherits(group_rows, "stata_numeric")) {
            positions <- as.integer(.stata_data(group_rows))
        } else {
            positions <- as.integer(group_rows)
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
    if (is.object(result)) return(result)
    first <- attributes(pieces[[1L]])
    first$names <- NULL
    if (length(first) == 0L) return(result)
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
    native_numeric <- inherits(target, "stata_numeric") &&
        !inherits(target, "stata_temporal") &&
        typeof(values) %in% c("logical", "integer", "double") &&
        (!is.object(values) || inherits(values, "stata_numeric"))
    native_temporal <- inherits(target, "stata_temporal") &&
        ((inherits(target, "stata_date") && inherits(values, "Date")) ||
         (inherits(target, "stata_datetime") &&
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
        slice_rows <- if (inherits(rows, "stata_numeric")) {
            .stata_data(rows)
        } else {
            rows
        }
        values <- vctrs::vec_slice(values, slice_rows)
    }
    .validate_numeric_values(values)
    # Build Stata prototypes from metadata rather than proxying the target.
    # A real metadata copy must revoke exclusive patch ownership; this internal
    # cast must not.
    prototype <- if (inherits(target, "stata_temporal")) {
        .stata_temporal_ptype(dta_storage_type(target), target)
    } else if (inherits(target, "stata_numeric")) {
        .stata_ptype(dta_storage_type(target), target)
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
                         by = NULL, bysort = NULL, selection = NULL) {
    .reject_data_table_subclass(data)
    grouped_input <- inherits(data, "grouped_df")
    original <- .as_mutation_data(
        data, allow_grouped = TRUE, allow_rowwise = FALSE
    )
    target <- .mutation_name(variable, generate, original)
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
            selected = selection$group_rows
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
        column <- .generated_column(values, rows, original$nrow)
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
        replacement <- .cast_replacement(
            values, column, rows, value_mode
        )
    }

    if (!generate) {
        patch <- function() .Call(
            C_dtatools_patch_data_column, data,
            as.integer(.native_data_column_location(access, target$location)),
            column, rows, replacement
        )
        column <- if (.ordinary_data_table(data)) {
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
    if (generate) {
        .append_generated_column(state, target$name, column)
        if (is.null(.reference_state(data))) .mark_reference_data(data, state)
    }
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
        if (target %in% key_columns) data.table::setkeyv(data, NULL)
        if (any(affected_indexes)) {
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
        if (target %in% key_columns) data.table::setkeyv(data, NULL)
        if (any(affected_indexes)) {
            retained <- index_columns[!affected_indexes]
            data.table::setindexv(data, NULL)
            for (columns in retained) data.table::setindexv(data, columns)
        }
        result
    })
}

.generated_numeric_class_supported <- function(values) {
    if (inherits(values, .stata_metadata_vector_class)) {
        values <- .stata_metadata_vector_base(values)
    }
    if (!is.object(values) || inherits(values, "stata_numeric")) return(TRUE)
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

.generated_numeric <- function(values, rows, row_count) {
    if (!.generated_numeric_class_supported(values)) {
        stop(
            "`gen()` does not support this classed numeric result; convert it explicitly",
            call. = FALSE
        )
    }
    declared <- dta_storage_type(values)
    base_date <- inherits(values, "Date") &&
        !inherits(values, "stata_temporal")
    base_datetime <- inherits(values, "POSIXct") &&
        !inherits(values, "stata_temporal")
    temporal <- inherits(values, "stata_temporal") ||
        base_date || base_datetime
    storage <- if (!is.null(declared)) {
        declared
    } else if (base_datetime) {
        # Stata datetimes are millisecond counts and require double storage to
        # preserve ordinary POSIXct values.
        "double"
    } else {
        "float"
    }
    prototype <- if (base_date) {
        structure(values, class = unique(c(
            "stata_temporal", "stata_date", class(values)
        )))
    } else if (base_datetime) {
        structure(values, class = unique(c(
            "stata_temporal", "stata_datetime", class(values)
        )))
    } else {
        values
    }
    source <- if (inherits(values, "stata_numeric") &&
        !identical(storage, "double")) {
        values
    } else {
        # The native reader consumes logical, integer, and double vectors
        # directly. Preserve their storage to avoid a full double temporary.
        vctrs::vec_data(values)
    }
    temporal_code <- if (temporal) .stata_temporal_code(prototype) else 0L
    kind <- match(storage, c("byte", "int", "long", "float", "double")) - 1L
    generated_attributes <- .stata_attribute_plan(
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

.generated_column <- function(values, rows, row_count) {
    if (is.factor(values) || !is.null(dim(values))) {
        stop("`gen()` values must be numeric, logical, or character",
             call. = FALSE)
    }
    if (typeof(values) == "character") {
        return(.generated_character(values, rows, row_count))
    }
    if (typeof(values) %in% c("logical", "integer", "double")) {
        return(.generated_numeric(values, rows, row_count))
    }
    stop("`gen()` values must be numeric, logical, or character",
         call. = FALSE)
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

# Ordinary R replacement has a caller binding to receive its result. Materialize
# the complete visible dataset first, then preserve normal copy-on-modify
# behavior instead of changing shared reference state as a side effect.
#' @export
`$<-.dtatools_ref_data` <- function(x, name, value) {
    result <- .reference_snapshot(x)
    result[[name]] <- value
    result
}

#' @export
`[[<-.dtatools_ref_data` <- function(x, i, ..., value) {
    result <- .reference_snapshot(x)
    result[[i, ...]] <- value
    result
}

#' @export
`[<-.dtatools_ref_data` <- function(x, i, j, ..., value) {
    call <- sys.call()
    call[[1L]] <- quote(`[<-`)
    call[[2L]] <- .reference_snapshot(x)
    eval(call, parent.frame())
}

#' @export
`names<-.dtatools_ref_data` <- function(x, value) {
    result <- .reference_snapshot(x)
    names(result) <- value
    result
}

#' @export
`dimnames<-.dtatools_ref_data` <- function(x, value) {
    result <- .reference_snapshot(x)
    dimnames(result) <- value
    result
}

#' @export
`row.names<-.dtatools_ref_data` <- function(x, value) {
    result <- .reference_snapshot(x)
    row.names(result) <- value
    result
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
vec_restore.dtatools_ref_data <- function(x, to, ...) {
    vctrs::vec_restore(x, .reference_snapshot(to), ...)
}

#' @export
dplyr_reconstruct.dtatools_ref_data <- function(data, template) {
    dplyr::dplyr_reconstruct(data, .reference_snapshot(template))
}

#' @export
select.dtatools_ref_data <- function(.data, ...) {
    dplyr::select(.reference_snapshot(.data), ...)
}

.reference_delegate <- function(data, call, generic, environment) {
    call[[1L]] <- generic
    call[[2L]] <- .reference_snapshot(data)
    eval(call, environment)
}

# Base and dplyr methods share one boundary: reference state is materialized to
# a shallow, complete data-frame snapshot before the ordinary implementation
# runs. The returned transformation follows normal copy-on-modify semantics.
#' @export
with.dtatools_ref_data <- function(data, expr, ...) {
    .reference_delegate(data, sys.call(), base::with, parent.frame())
}

#' @export
within.dtatools_ref_data <- function(data, expr, ...) {
    .reference_delegate(data, sys.call(), base::within, parent.frame())
}

#' @export
subset.dtatools_ref_data <- function(x, ...) {
    .reference_delegate(x, sys.call(), base::subset, parent.frame())
}

#' @export
transform.dtatools_ref_data <- function(`_data`, ...) {
    .reference_delegate(`_data`, sys.call(), base::transform, parent.frame())
}

#' @export
rbind.dtatools_ref_data <- function(..., deparse.level = 1) {
    values <- lapply(list(...), .reference_snapshot)
    do.call(base::rbind, c(values, list(deparse.level = deparse.level)))
}

#' @export
cbind.dtatools_ref_data <- function(..., deparse.level = 1) {
    values <- lapply(list(...), .reference_snapshot)
    do.call(base::cbind, c(values, list(deparse.level = deparse.level)))
}

#' @export
arrange.dtatools_ref_data <- function(.data, ..., .by_group = FALSE) {
    .reference_delegate(.data, sys.call(), dplyr::arrange, parent.frame())
}

#' @export
filter.dtatools_ref_data <- function(
    .data, ..., .by = NULL, .preserve = FALSE
) {
    .reference_delegate(.data, sys.call(), dplyr::filter, parent.frame())
}

#' @export
slice.dtatools_ref_data <- function(.data, ..., .by = NULL, .preserve = FALSE) {
    .reference_delegate(.data, sys.call(), dplyr::slice, parent.frame())
}

#' @export
relocate.dtatools_ref_data <- function(
    .data, ..., .before = NULL, .after = NULL
) {
    .reference_delegate(.data, sys.call(), dplyr::relocate, parent.frame())
}

#' @export
rename.dtatools_ref_data <- function(.data, ...) {
    .reference_delegate(.data, sys.call(), dplyr::rename, parent.frame())
}

#' @export
mutate.dtatools_ref_data <- function(.data, ...) {
    .reference_delegate(.data, sys.call(), dplyr::mutate, parent.frame())
}

#' @export
transmute.dtatools_ref_data <- function(.data, ...) {
    .reference_delegate(.data, sys.call(), dplyr::transmute, parent.frame())
}

# Grouping changes only dplyr metadata, so a dibble stays a dibble: the
# grouped or ungrouped snapshot is marked again, and `state$classes` then
# records the grouping for later snapshots. The result is a fresh object
# either way, so the mark never touches the caller's dataset.
.regroup_reference_data <- function(data, result) {
    if (is_dibble(data) && !is_dibble(result)) .as_dibble(result) else result
}

#' @export
group_by.dtatools_ref_data <- function(
    .data, ..., .add = FALSE,
    .drop = dplyr::group_by_drop_default(.data)
) {
    .regroup_reference_data(.data, .reference_delegate(
        .data, sys.call(), dplyr::group_by, parent.frame()
    ))
}

#' @export
summarise.dtatools_ref_data <- function(
    .data, ..., .by = NULL, .groups = NULL
) {
    .reference_delegate(.data, sys.call(), dplyr::summarise, parent.frame())
}

#' @export
distinct.dtatools_ref_data <- function(.data, ..., .keep_all = FALSE) {
    .reference_delegate(.data, sys.call(), dplyr::distinct, parent.frame())
}

#' @export
ungroup.dtatools_ref_data <- function(x, ...) {
    .regroup_reference_data(x, .reference_delegate(
        x, sys.call(), dplyr::ungroup, parent.frame()
    ))
}

#' @export
rowwise.dtatools_ref_data <- function(data, ...) {
    .reference_delegate(data, sys.call(), dplyr::rowwise, parent.frame())
}
