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
#' `gen()` and `replace_values()` reject grouped and rowwise tibbles. Ungroup
#' them before mutation. `copy_data()` accepts them and preserves their class.
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
#' call other than `.()`, `...`, and a missing argument are errors.
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
#' mutation. Columns win over objects in the calling environment; use `.env`
#' for an environment value when names collide. A stored or inline one-sided
#' formula evaluates its right-hand side in the same data mask and uses the
#' formula environment as its fallback. Two-sided formulas are rejected.
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
#' `gen()` appends one variable and does not implement Stata's `before()` or
#' `after()` placement. A declared `stata_*()` result keeps its numeric storage;
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
#' storage. Stata `by`, `[in]`, and `:lblname` authoring are not supported.
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
#' Explicit storage \tab Type prefix \tab `stata_*()` value expression \cr
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
#' @param data An ungrouped data frame or tibble to mutate. `copy_data()` also
#'   accepts grouped and rowwise tibbles.
#' @param variable Exactly one unquoted target name, or one nonempty,
#'   non-missing character string, which is what `!!name` unquotes to and
#'   what a `.(name)` call supplies in place. An empty string, `NA`, a
#'   character vector of length other than one, a call other than `.()`,
#'   `...`, and a missing argument are errors.
#' @param values A value expression or one-sided formula. It may reference a
#'   column whose name is a string through the mask's `.data` pronoun.
#' @param where `NULL`, a logical expression, valid row positions, or a
#'   one-sided formula.
#' @return `gen()` and `replace_values()` return `data` invisibly.
#'   `copy_data()` returns an independent data frame or tibble.
#' @references
#' StataCorp, \href{https://www.stata.com/manuals/dgenerate.pdf}{generate manual}.
#' @examples
#' survey <- data.frame(income = c(10, 20), eligible = c(TRUE, FALSE))
#' replace_values(survey, income, income * 2, where = eligible)
#' gen(survey, adjusted, income + 5)
#' independent <- copy_data(survey)
#' repl(independent, income, 0)
#'
#' # A name known only at run time, in each position that accepts one
#' target_name <- "adjusted"
#' source_name <- "income"
#' repl(survey, !!target_name, 0)
#' repl(survey, !!rlang::sym(target_name), 1)
#' gen(survey, doubled, .data[[source_name]] * 2)
#' repl(survey, doubled, 0, where = .data[[source_name]] > 15)
#' @export
replace_values <- function(data, variable, values, where = NULL) {
    variable <- rlang::enquo(variable)
    values <- rlang::enquo(values)
    where <- rlang::enquo(where)
    .mutate_data(data, variable, values, where, generate = FALSE)
}

#' @rdname replace_values
#' @export
repl <- replace_values

#' @rdname replace_values
#' @export
gen <- function(data, variable, values, where = NULL) {
    variable <- rlang::enquo(variable)
    values <- rlang::enquo(values)
    where <- rlang::enquo(where)
    .mutate_data(data, variable, values, where, generate = TRUE)
}

.reference_state <- function(data) {
    state <- attr(data, ".dtatools_ref_state", exact = TRUE)
    if (is.environment(state)) state else NULL
}

.plain_data_columns <- function(data) {
    physical <- unclass(data)
    unname(lapply(seq_along(physical), function(index) physical[[index]]))
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

.as_mutation_data <- function(data, allow_grouped = FALSE) {
    if (!is.data.frame(data)) {
        stop("`data` must be a data frame or tibble", call. = FALSE)
    }
    if (!allow_grouped &&
        (inherits(data, "grouped_df") || inherits(data, "rowwise_df"))) {
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

.eval_plain_mutation <- function(expression, columns, environment) {
    if (!is.environment(columns)) {
        return(eval(expression, columns, environment))
    }
    previous_parent <- parent.env(columns)
    on.exit(parent.env(columns) <- previous_parent, add = TRUE)
    parent.env(columns) <- environment
    eval(expression, new.env(parent = columns))
}

.eval_in_mutation_data <- function(expression, columns, environment = NULL) {
    # Plain expressions -- no `.data`/`.env` pronouns and no embedded
    # quosures -- have identical semantics under base evaluation with the
    # columns masking the expression environment. Skipping the rlang data
    # mask there removes the dominant per-call cost of `gen()`/`repl()`.
    if (is.null(environment)) {
        if (rlang::is_quosure(expression) &&
            .plain_mutation_expression(rlang::quo_get_expr(expression))) {
            return(.eval_plain_mutation(
                rlang::quo_get_expr(expression), columns,
                rlang::quo_get_env(expression)
            ))
        }
    } else if (.plain_mutation_expression(expression)) {
        return(.eval_plain_mutation(expression, columns, environment))
    }
    reader_environment <- if (!is.null(environment)) {
        environment
    } else if (rlang::is_quosure(expression)) {
        rlang::quo_get_env(expression)
    } else {
        parent.frame()
    }
    if (!is.environment(columns)) {
        mask <- rlang::as_data_mask(columns)
        mask$. <- .runtime_name_reader(columns, reader_environment)
        return(if (is.null(environment)) {
            rlang::eval_tidy(expression, data = mask)
        } else {
            rlang::eval_tidy(expression, data = mask, env = environment)
        })
    }
    previous_parent <- parent.env(columns)
    on.exit(parent.env(columns) <- previous_parent, add = TRUE)
    mask <- rlang::new_data_mask(columns)
    mask$.data <- rlang::as_data_pronoun(columns)
    mask$. <- .runtime_name_reader(columns, reader_environment)
    if (is.null(environment)) {
        rlang::eval_tidy(expression, data = mask)
    } else {
        rlang::eval_tidy(expression, data = mask, env = environment)
    }
}

.eval_mutation_expression <- function(quo, columns, argument) {
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
            rlang::quo_get_env(quo)
        ))
    }
    value <- .eval_in_mutation_data(quo, columns)
    formula <- .formula_expression(value, argument)
    if (is.null(formula)) return(value)
    .eval_in_mutation_data(
        formula$expression,
        columns,
        formula$environment
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

.fused_comparison_scalar <- function(expression, columns, environment) {
    value <- .eval_in_mutation_data(expression, columns, environment)
    scalar <- .stata_compare_scalar(value)
    if (length(value) != 1L || is.null(scalar)) return(NULL)
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

.mutation_value_mode <- function(values, rows, row_count) {
    size <- vctrs::vec_size(values)
    selected <- .mutation_selected_count(rows, row_count)
    if (size == 1L) return("scalar")
    if (!is.null(rows) && size == row_count) return("row")
    if (size == selected || (selected == 0L && size == 0L)) {
        return("selected")
    }
    stop(sprintf(
        paste0(
            "`values` has size %s; expected size 1, the selected-row ",
            "count (%s), or the data row count (%s)"
        ),
        size, selected, row_count
    ), call. = FALSE)
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
        .stata_temporal_ptype(stata_storage_type(target), target)
    } else if (inherits(target, "stata_numeric")) {
        .stata_ptype(stata_storage_type(target), target)
    } else {
        target[integer()]
    }
    result <- vctrs::vec_cast(values, prototype)
    .validate_numeric_values(result)
    result
}

.mutate_data <- function(data, variable, values, where, generate) {
    .reject_data_table_subclass(data)
    original <- .as_mutation_data(data)
    target <- .mutation_name(variable, generate, original)
    state <- .reference_state(data)
    access <- NULL
    column <- NULL

    fused <- if (generate) NULL else {
        .fused_comparison_plan(where, original$columns, original$nrow)
    }
    if (is.null(fused)) {
        selected <- .eval_mutation_expression(
            where, original$columns, "where"
        )
        evaluated <- .eval_mutation_expression(
            values, original$columns, "values"
        )
    } else {
        evaluated <- .eval_mutation_expression(
            values, original$columns, "values"
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
    declared <- stata_storage_type(values)
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
        # `locations` also indexes generated columns, which live past the
        # end of the physical object, so confirm the hit is a physical one.
        location <- state$locations[[name]]
        physical <- attr(data, "names", exact = TRUE)
        if (!is.null(location) && location <= length(physical) &&
            identical(physical[[location]], name)) {
            return(list(.subset2(data, location)))
        }
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

#' @export
`[.dtatools_ref_data` <- function(x, i, j, ..., drop) {
    call <- sys.call()
    call[[1L]] <- quote(`[`)
    call[[2L]] <- .reference_snapshot(x)
    eval(call, parent.frame())
}

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

#' @export
print.dtatools_ref_data <- function(x, ...) {
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

#' @export
group_by.dtatools_ref_data <- function(
    .data, ..., .add = FALSE,
    .drop = dplyr::group_by_drop_default(.data)
) {
    .reference_delegate(.data, sys.call(), dplyr::group_by, parent.frame())
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
    .reference_delegate(x, sys.call(), dplyr::ungroup, parent.frame())
}

#' @export
rowwise.dtatools_ref_data <- function(data, ...) {
    .reference_delegate(data, sys.call(), dplyr::rowwise, parent.frame())
}
