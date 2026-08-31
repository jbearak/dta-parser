#' Generate and replace variables by reference
#'
#' `gen()` and `replace_values()` modify a data frame or tibble by reference.
#' `repl()` is a direct alias for `replace_values()`. The return value is the
#' supplied dataset, invisibly, so assignment is neither needed nor advised.
#' Aliases of the dataset or the same target vector observe later generation
#' and replacement. This includes column-only subsets that share their column
#' payload. Row subsets have new payloads and remain independent. Use
#' `copy_data()` when isolation is required.
#' The first mutation attaches package-owned reference state to the same
#' data-frame or tibble object. Existing columns remain in the data frame;
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
#'
#' `variable` must be one unquoted name. Tidy-evaluation injection is supported,
#' so `gen(data, !!rlang::sym(name), value)` handles a name stored in a string.
#' A quoted target is rejected.
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
#' accepted and the last replacement for a row wins. `values` must have size
#' one, the selected-row count, or the full dataset row count. Full-length
#' values are indexed by the selected row positions.
#'
#' `gen()` appends one variable and does not implement Stata's `before()` or
#' `after()` placement. A declared `stata_*()` result keeps its numeric storage;
#' otherwise logical, integer, and double results use Stata `float` storage.
#' Character results use the smallest `str1` through `str2045` width that fits,
#' or `strL` above 2,045 UTF-8 bytes. Numeric rows excluded by `where` contain
#' system missing. Excluded string rows contain `""`, Stata's string missing.
#' Wrap the value expression in a Stata constructor to request explicit numeric
#' storage. Stata `by`, `[in]`, and `:lblname` authoring are not supported.
#' Unlike Stata's default `replace`, `replace_values()` never promotes a target
#' to wider storage. It rejects values that do not fit the declared storage.
#'
#' The table records the deliberate first-release choices relative to Stata's
#' `generate [type] newvar = exp [if] [in]` command.
#'
#' \tabular{lll}{
#' Topic \tab Stata \tab dtatools \cr
#' Existing name \tab Error \tab Error before mutation \cr
#' Numeric default \tab `float`, or `double` after `set type` \tab Always `float` \cr
#' Explicit storage \tab Type prefix \tab `stata_*()` value expression \cr
#' Strings \tab Smallest fitting `str#` or `strL` \tab Smallest UTF-8-byte width or `strL` \cr
#' Rows outside `if` \tab Numeric `.` or string `""` \tab Same \cr
#' Expression with `if` \tab Evaluated only for selected observations \tab Evaluated once for all rows, then selected \cr
#' Placement \tab Optional placement commands \tab Append only \cr
#' Missing report \tab Command output \tab No printed report \cr
#' }
#'
#' Compact `byte`, `int`, `long`, and `float` columns are patched in their
#' native storage after validation. A direct compact target allocates work
#' proportional to the selected rows and does not create a full R double copy.
#' A metadata proxy first detaches by copying its compact native payload so an
#' independent source remains unchanged; it still avoids a full R double copy.
#' Ordinary and materialized numeric columns and character columns are patched in their
#' existing R representation. Replacing a dictionary-backed string materializes
#' that target character column, but does not copy the data frame. `copy_data()`
#' keeps unmaterialized compact numeric and dictionary-string columns compact.
#'
#' @param data A data frame or tibble to mutate, or the source passed to
#'   `copy_data()`.
#' @param variable Exactly one unquoted target name.
#' @param values A value expression or one-sided formula.
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

.data_columns <- function(data) {
    state <- .reference_state(data)
    columns <- .plain_data_columns(data)
    names(columns) <- attr(data, "names", exact = TRUE)
    if (!is.null(state)) columns <- c(columns, state$generated)
    columns
}

.new_reference_state <- function(data) {
    state <- new.env(parent = emptyenv())
    state$generated <- list()
    state$nrow <- base::nrow(data)
    state$classes <- class(data)
    state
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

.as_mutation_data <- function(data) {
    if (!is.data.frame(data)) {
        stop("`data` must be a data frame or tibble", call. = FALSE)
    }
    if (inherits(data, "grouped_df") || inherits(data, "rowwise_df")) {
        stop("`data` must be an ungrouped data frame or tibble", call. = FALSE)
    }
    names <- names(data)
    if (is.null(names) || anyNA(names) || any(names == "") ||
        anyDuplicated(names)) {
        stop("`data` must have unique, non-missing column names",
             call. = FALSE)
    }
    columns <- .data_columns(data)
    sizes <- lengths(columns)
    row_count <- nrow(data)
    if (any(sizes != row_count)) {
        stop("`data` has columns with inconsistent row counts",
             call. = FALSE)
    }
    list(columns = columns, names = names, nrow = row_count)
}

.mutation_name <- function(variable, generate, names) {
    if (rlang::quo_is_missing(variable)) {
        stop("`variable` must be one unquoted column name", call. = FALSE)
    }
    expression <- rlang::quo_get_expr(variable)
    if (!is.symbol(expression) || identical(expression, quote(...))) {
        stop("`variable` must be one unquoted column name", call. = FALSE)
    }
    name <- as.character(expression)
    location <- match(name, names)
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
        return(rlang::eval_tidy(
            expression[[2L]],
            data = columns,
            env = rlang::quo_get_env(quo)
        ))
    }
    value <- rlang::eval_tidy(quo, data = columns)
    formula <- .formula_expression(value, argument)
    if (is.null(formula)) return(value)
    rlang::eval_tidy(
        formula$expression,
        data = columns,
        env = formula$environment
    )
}

.mutation_rows <- function(value, row_count) {
    if (is.null(value)) return(seq_len(row_count))
    if (is.logical(value)) {
        if (length(value) == 1L) value <- rep_len(value, row_count)
        if (length(value) != row_count) {
            stop(sprintf(
                "`where` has size %s; expected size 1 or %s",
                length(value), row_count
            ), call. = FALSE)
        }
        value[is.na(value)] <- FALSE
        return(which(value))
    }
    if (inherits(value, "stata_numeric") &&
        !inherits(value, "stata_temporal")) {
        value <- as.double(value)
    }
    if (!is.numeric(value) || is.object(value) || !is.null(dim(value))) {
        stop("`where` must yield logical values or numeric row positions",
             call. = FALSE)
    }
    if (length(value) == 0L) return(integer())
    if (anyNA(value) || any(!is.finite(value)) ||
        any(value != trunc(value)) || any(value <= 0) ||
        any(value > row_count)) {
        stop(paste0(
            "`where` row positions must be positive, finite, whole, ",
            "and no greater than the row count"
        ), call. = FALSE)
    }
    as.integer(value)
}

.slice_mutation_values <- function(values, rows, row_count) {
    size <- vctrs::vec_size(values)
    selected <- length(rows)
    if (size == row_count) return(vctrs::vec_slice(values, rows))
    if (size == selected) return(values)
    if (size == 1L) return(vctrs::vec_recycle(values, selected))
    if (selected == 0L && size == 0L) return(values)
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

.validate_string_storage <- function(values, storage, operation) {
    lengths <- nchar(enc2utf8(values), type = "bytes", allowNA = TRUE)
    lengths[is.na(lengths)] <- 0L
    maximum <- if (length(lengths) == 0L) 0L else max(lengths)
    if (maximum > 2000000000) {
        stop(sprintf(
            "A %s string exceeds Stata's 2,000,000,000-byte limit",
            operation
        ), call. = FALSE)
    }
    if (!is.null(storage) && !identical(storage, "strL")) {
        width <- suppressWarnings(as.integer(sub("^str", "", storage)))
        if (is.na(width) || width < 1L || width > 2045L || maximum > width) {
            stop(sprintf(
                "%s values do not fit their declared Stata string storage",
                tools::toTitleCase(operation)
            ), call. = FALSE)
        }
    }
    list(maximum = maximum, storage = storage)
}

.cast_replacement <- function(values, target) {
    .validate_numeric_values(values)
    if (is.factor(target) || !is.null(dim(target)) ||
        !(typeof(target) %in% c("logical", "integer", "double", "character"))) {
        stop("The target column has an unsupported replacement type",
             call. = FALSE)
    }
    result <- vctrs::vec_cast(values, vctrs::vec_ptype(target))
    if (typeof(target) == "character") {
        storage <- attr(target, "stata.string.storage", exact = TRUE)
        .validate_string_storage(result, storage, "replacement")
    }
    .validate_numeric_values(result)
    result
}

.mutate_data <- function(data, variable, values, where, generate) {
    original <- .as_mutation_data(data)
    target <- .mutation_name(variable, generate, original$names)

    selected <- .eval_mutation_expression(where, original$columns, "where")
    rows <- .mutation_rows(selected, original$nrow)
    evaluated <- .eval_mutation_expression(values, original$columns, "values")
    values <- .slice_mutation_values(evaluated, rows, original$nrow)

    state <- .reference_state(data)
    if (generate) {
        column <- .generated_column(values, rows, original$nrow)
        if (is.null(state)) state <- .new_reference_state(data)
        generated <- state$generated
        generated[[target$name]] <- column
    } else {
        column <- original$columns[[target$location]]
        replacement <- .cast_replacement(values, column)
        if (is.null(state)) state <- .new_reference_state(data)
    }

    if (!generate && length(rows) > 0L) {
        .Call(C_dtatools_patch_vector, column, as.integer(rows), replacement)
    }
    if (generate) state$generated <- generated
    if (is.null(.reference_state(data))) .mark_reference_data(data, state)
    invisible(data)
}

.generated_numeric <- function(values, rows, row_count) {
    declared <- stata_storage_type(values)
    temporal <- inherits(values, "stata_temporal")
    storage <- if (is.null(declared)) "float" else declared
    output <- rep(NA_real_, row_count)
    source <- if (inherits(values, "stata_numeric")) {
        as.double(values)
    } else {
        as.double(vctrs::vec_data(values))
    }
    if (length(rows) > 0L) output[rows] <- source

    result <- .construct_stata_numeric(
        output, NULL, storage,
        temporal = if (temporal) .stata_temporal_code(values) else 0L
    )
    if (temporal) {
        return(.attach_stata_temporal(result, values, storage))
    }
    result <- .restore_stata_metadata(result, values, storage)
    .apply_haven_labelled_class(
        result, !is.null(attr(result, "labels", exact = TRUE))
    )
}

.generated_character <- function(values, rows, row_count) {
    output <- rep("", row_count)
    if (length(rows) > 0L) output[rows] <- values
    output[is.na(output)] <- ""
    sizing <- .validate_string_storage(output, NULL, "generated")
    maximum <- sizing$maximum
    inferred <- if (maximum > 2045L) "strL" else paste0("str", max(1L, maximum))
    declared <- attr(values, "stata.string.storage", exact = TRUE)
    storage <- if (is.null(declared)) inferred else declared
    .validate_string_storage(output, storage, "generated")
    result <- .metadata_copy(output)
    source_attributes <- attributes(values)
    source_attributes$names <- NULL
    for (name in names(source_attributes)) {
        attr(result, name) <- source_attributes[[name]]
    }
    attr(result, "stata.string.storage") <- storage
    result
}

.generated_column <- function(values, rows, row_count) {
    if (is.factor(values) || !is.null(dim(values))) {
        stop("`gen()` values must be numeric, logical, or character",
             call. = FALSE)
    }
    .validate_numeric_values(values)
    if (typeof(values) == "character") {
        return(.generated_character(values, rows, row_count))
    }
    if (typeof(values) %in% c("logical", "integer", "double")) {
        return(.generated_numeric(values, rows, row_count))
    }
    stop("`gen()` values must be numeric, logical, or character",
         call. = FALSE)
}

#' @rdname replace_values
#' @export
copy_data <- function(data) {
    source <- .as_mutation_data(data)
    columns <- lapply(source$columns, function(column) {
        .Call(C_dtatools_deep_copy_column, column)
    })
    names(columns) <- source$names
    snapshot <- .reference_snapshot(data)
    attributes(columns) <- attributes(snapshot)
    columns
}

#' @export
`$.dtatools_ref_data` <- function(x, name) {
    .data_columns(x)[[name]]
}

#' @export
`[[.dtatools_ref_data` <- function(x, i, ..., exact = TRUE) {
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
    names(.data_columns(x))
}

#' @export
length.dtatools_ref_data <- function(x) {
    length(.data_columns(x))
}

#' @export
dim.dtatools_ref_data <- function(x) {
    state <- .reference_state(x)
    c(state$nrow, length(.data_columns(x)))
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
