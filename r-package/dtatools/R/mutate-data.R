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
#' Ordinary and materialized numeric columns and character columns are patched in their
#' existing R representation. Replacing a dictionary-backed string materializes
#' that target character column, but does not copy the data frame.
#' Dictionary-backed replacement values are validated through a read-only
#' native reader, so a successful mutation, error, or interrupt does not
#' populate a shared source cache. `copy_data()` keeps unmaterialized compact
#' numeric and dictionary-string columns compact.
#'
#' @param data An ungrouped data frame or tibble to mutate. `copy_data()` also
#'   accepts grouped and rowwise tibbles.
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

.as_mutation_data <- function(data, allow_grouped = FALSE) {
    if (!is.data.frame(data)) {
        stop("`data` must be a data frame or tibble", call. = FALSE)
    }
    if (!allow_grouped &&
        (inherits(data, "grouped_df") || inherits(data, "rowwise_df"))) {
        stop("`data` must be an ungrouped data frame or tibble", call. = FALSE)
    }
    names <- names(data)
    if (is.null(names) || anyNA(names) || any(names == "") ||
        anyDuplicated(names)) {
        stop("`data` must have unique, non-missing column names",
             call. = FALSE)
    }
    columns <- .data_columns(data)
    sizes <- vapply(columns, NROW, numeric(1))
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
    if (is.null(value)) return(NULL)
    stata_positions <- inherits(value, "stata_numeric") &&
        !inherits(value, "stata_temporal")
    if (!is.null(dim(value)) ||
        (!is.logical(value) &&
         (!is.numeric(value) || (is.object(value) && !stata_positions)))) {
        stop("`where` must yield logical values or numeric row positions",
             call. = FALSE)
    }
    .Call(C_dtatools_mutation_rows, value, as.double(row_count))
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
    if (.is_unmaterialized_numeric_altrep(target) &&
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
    original <- .as_mutation_data(data)
    target <- .mutation_name(variable, generate, original$names)

    selected <- .eval_mutation_expression(where, original$columns, "where")
    rows <- .mutation_rows(selected, original$nrow)
    evaluated <- .eval_mutation_expression(values, original$columns, "values")
    value_mode <- .mutation_value_mode(evaluated, rows, original$nrow)
    values <- evaluated

    state <- .reference_state(data)
    if (generate) {
        column <- .generated_column(values, rows, original$nrow)
        if (is.null(state)) state <- .new_reference_state(data)
        generated <- state$generated
        generated[[target$name]] <- column
    } else {
        column <- original$columns[[target$location]]
        replacement <- .cast_replacement(
            values, column, rows, value_mode
        )
    }

    if (!generate) {
        .Call(
            C_dtatools_patch_data_column,
            data, as.integer(target$location), column, rows, replacement
        )
    }
    if (generate) {
        state$generated <- generated
        if (is.null(.reference_state(data))) .mark_reference_data(data, state)
    }
    invisible(data)
}

.generated_numeric_class_supported <- function(values) {
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

#' @rdname replace_values
#' @export
copy_data <- function(data) {
    source <- .as_mutation_data(data, allow_grouped = TRUE)
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
    call <- sys.call()
    call[[1L]] <- quote(`$`)
    call[[2L]] <- .reference_snapshot(x)
    eval(call, parent.frame())
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
