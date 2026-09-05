#' Generate a column from a selected calculation sample
#'
#' `egen()` creates one column by reference using the same target spelling,
#' data mask, and alias rules as [gen()]. Its value functions are ordinary R
#' functions, also available in `gen()` and dibble `:=` expressions.
#'
#' With no filter, these three forms give the same new column:
#' `egen(d, average = dta_mean(x), by = id)`,
#' `gen(d, average = dta_mean(x), by = id)`, and
#' `d[, average := dta_mean(x), by = id]`.
#'
#' With a filter, `egen()` evaluates its value expression on the selected
#' observations only. `gen()` and `:=` evaluate on the full group and restrict
#' writes. Thus `egen(d, total = dta_total(x), where = eligible, by = id)`
#' corresponds to
#' `d[eligible, total := dta_total(x[eligible]), by = id]`.
#' Excluded observations receive system missing, except that a
#' `dta_group_tag()` result gives them zero.
#'
#' `where` is evaluated on each full group, with `.n` and `.N` as its row
#' number and size. `rows` is intersected with that selection and is relative
#' to the full group. The value expression then sees the admitted sample,
#' with its own `.n` and `.N`. Missing keys, including distinct extended
#' missing codes, form valid `by` groups. Row calculations and group-ID/tag
#' calculations reject command-level grouping. `bysort` sorts the complete
#' dataset by its grouping keys when the operation succeeds.
#'
#' Supported value calls are [dta_mean()], [dta_min()], [dta_max()],
#' [dta_total()], [dta_row_max()], [dta_row_total()], [dta_group_id()], and
#' [dta_group_tag()], optionally wrapped in a storage constructor. These are
#' real R functions; base R names are not reinterpreted. Stored one-sided
#' formulas work as in `gen()`. Each value expression is evaluated once per
#' nonempty admitted group. An entirely empty sample is evaluated once with
#' zero-row inputs to establish the output type and metadata.
#'
#' Numeric source vectors cannot contain `NaN` or infinities. Within an
#' `egen()` calculation, arithmetic-produced `NaN` is normalized to system
#' missing. Standalone value functions reject `NaN`. Input temporal values
#' contribute their encoded Stata numbers; calculation outputs do not inherit
#' the source's labels, date class, or display format.
#'
#' Calculation, storage conversion, metadata, and optional row/column
#' ordering are prepared before one column-set commit. Failed validation
#' leaves the dataset unchanged. Insufficient capacity fails before calculation
#' or row selection. Assign [reserve_columns()] before calling `egen()`.
#'
#' @param data A data frame, tibble, dibble, or ordinary data table, modified
#'   by reference under the same capacity rules as `gen()`.
#' @param ... One `target = calculation` pair or `target, calculation`,
#'   optionally followed by an untagged `where`, as in `gen()`.
#' @param where A logical expression or row positions selecting the
#'   calculation sample, optionally supplied as a one-sided formula.
#' @param by,bysort Grouping columns, using the same captured names as
#'   `gen()`. A grouped tibble supplies its own groups.
#' @param rows Optional positive, unique integer row positions, intersected
#'   with `where` within each group. Evaluated in the calling environment.
#' @param type Optional Stata storage name: `"byte"`, `"int"`, `"long"`,
#'   `"float"`, or `"double"`. Tags always use byte. Otherwise explicit
#'   storage overrides the ordinary generation default.
#' @param before,after An optional existing column name before or after which
#'   to insert the new column. Supply at most one. Uses the target-name
#'   syntax, including bare names, strings, and tidy injection.
#' @return `data`, invisibly. Existing targets are errors; use dibble `:=`
#'   to create or overwrite a column.
#' @seealso [dta-calculations], [dta_group_id()], [gen()], [dibble-bracket]
#' @examples
#' d <- dibble(household = c(1, 1, 2), income = c(10, 100, 30),
#'             eligible = c(TRUE, FALSE, TRUE))
#' egen(d, average = dta_mean(income), by = household)
#' egen(d, selected = dta_total(income), where = eligible, by = household)
#' d[eligible, equivalent := dta_total(income[eligible]), by = household]
#' @export
egen <- function(data, ..., where = NULL, by = NULL, bysort = NULL,
                 rows = NULL, type = NULL, before = NULL, after = NULL) {
    .reject_data_table_subclass(data)
    original <- .as_mutation_data(data, allow_grouped = TRUE,
                                  allow_rowwise = FALSE)
    arguments <- .mutation_arguments(
        substitute(...()), rlang::enquo(where), missing(where),
        function() .capture_positional_pair(...),
        function() .capture_positional_triple(...),
        function() rlang::enquos(..., .ignore_empty = "none"),
        function() rlang::enquos0(...)
    )
    target <- .mutation_name(arguments$variable, TRUE, original)$name
    .prepare_column_operation(data, length(data) + 1L)
    storage <- .egen_storage(type)
    placement <- .egen_placement(rlang::enquo(before), rlang::enquo(after),
                                 names(data), target)
    positions <- .egen_positions(rows)
    calculation <- .egen_calculation(arguments$values, original$columns)
    group_plan <- .egen_groups(data, original, rlang::enquo(by),
                               rlang::enquo(bysort), calculation$kind)
    evaluated <- .egen_evaluate(original, group_plan, arguments$where,
                                 positions, calculation)
    if (identical(calculation$kind, "dta_group_tag")) {
        storage <- "byte"
    }
    values <- evaluated$values
    if (!is.null(storage)) {
        values <- .egen_storage_result(
            get(paste0("dta_", storage), mode = "function"), values)
    }
    column <- .generated_column(values, evaluated$rows, original$nrow,
                                caller = "egen()", generate = TRUE)
    if (identical(calculation$kind, "dta_group_tag") &&
        !is.null(evaluated$rows)) {
        excluded <- setdiff(seq_len(original$nrow), evaluated$rows)
        column[excluded] <- 0
    }
    columns <- .data_columns(data)
    columns[[target]] <- column
    columns <- columns[placement]
    if (!is.null(group_plan$order)) {
        columns <- .dta_merge_slice_columns(
            vctrs::new_data_frame(columns, n = original$nrow),
            group_plan$order, fill_string_missing = FALSE
        )
        columns <- as.list(columns)
    }
    result <- .install_column_selection(data, original, columns,
        source_names = if (is.null(group_plan$order)) names(columns) else
            rep(NA_character_, length(columns)))
    invisible(result)
}

.egen_storage <- function(type) {
    if (is.null(type)) return(NULL)
    if (!is.character(type) || length(type) != 1L || is.na(type) ||
        !type %in% c("byte", "int", "long", "float", "double")) {
        stop("`type` must be byte, int, long, float, or double", call. = FALSE)
    }
    type
}

.egen_placement <- function(before, after, columns, target) {
    has_before <- !rlang::quo_is_null(before)
    has_after <- !rlang::quo_is_null(after)
    if (has_before && has_after) {
        stop("supply either `before` or `after`, not both", call. = FALSE)
    }
    if (!has_before && !has_after) return(c(columns, target))
    name <- .unquoted_variable_name(if (has_before) before else after)
    index <- match(name, columns)
    if (is.na(index)) stop(sprintf("Column `%s` does not exist", name),
                           call. = FALSE)
    append(columns, target, after = index - as.integer(has_before))
}

.egen_positions <- function(rows) {
    if (is.null(rows)) return(NULL)
    if (!is.numeric(rows) || is.object(rows) || !is.null(dim(rows)) ||
        anyNA(rows) || any(!is.finite(rows) | rows < 1 | rows != floor(rows)) ||
        anyDuplicated(rows)) {
        stop("`rows` must contain unique positive integer positions",
             call. = FALSE)
    }
    rows
}

.EGEN_FUNCTIONS <- c("dta_mean", "dta_min", "dta_max", "dta_total",
                     "dta_row_max", "dta_row_total", "dta_group_id",
                     "dta_group_tag")

.egen_function <- function(head, environment) {
    if (is.symbol(head)) {
        return(get0(as.character(head), envir = environment,
                    mode = "function", inherits = TRUE))
    }
    if (is.call(head) && length(head) == 3L &&
        identical(head[[1L]], quote(`::`)) &&
        identical(head[[2L]], quote(dtatools))) {
        return(get0(as.character(head[[3L]]), envir = environment(egen),
                    mode = "function", inherits = FALSE))
    }
    NULL
}

.egen_kind <- function(expression, environment) {
    if (!is.call(expression)) return(NULL)
    fun <- .egen_function(expression[[1L]], environment)
    for (name in .EGEN_FUNCTIONS) {
        if (identical(fun, get(name, envir = environment(egen)))) return(name)
    }
    for (name in paste0("dta_", c("byte", "int", "long", "float", "double"))) {
        if (identical(fun, get(name, envir = environment(egen))) &&
            length(expression) >= 2L) {
            return(.egen_kind(expression[[2L]], environment))
        }
    }
    NULL
}

.egen_calculation <- function(quo, columns) {
    if (rlang::quo_is_missing(quo)) stop("`values` is required", call. = FALSE)
    expression <- rlang::quo_get_expr(quo)
    frame <- rlang::quo_get_env(quo)
    formula <- FALSE
    if (is.call(expression) && identical(expression[[1L]], quote(`~`))) {
        if (length(expression) != 2L) {
            stop("`values` formulas must be one-sided", call. = FALSE)
        }
        expression <- expression[[2L]]
        formula <- TRUE
    } else if (is.symbol(expression) ||
               (is.call(expression) &&
                (identical(expression[[1L]], quote(`$`)) ||
                 identical(expression[[1L]], quote(`[[`))))) {
        value <- .eval_in_mutation_data(quo, columns)
        stored <- .formula_expression(value, "values")
        if (!is.null(stored)) {
            expression <- stored$expression
            frame <- stored$environment
            formula <- TRUE
        }
    }
    kind <- .egen_kind(expression, frame)
    if (is.null(kind)) {
        stop(paste0("`egen()` requires a value call to one of: ",
                    paste(.EGEN_FUNCTIONS, collapse = ", "),
                    ". See the egen help page for supported calculations."),
             call. = FALSE)
    }
    list(quo = rlang::new_quosure(expression, frame), kind = kind,
         shadow = !formula)
}

.egen_groups <- function(data, original, by, bysort, kind) {
    by <- if (rlang::quo_is_null(by)) NULL else by
    bysort <- if (rlang::quo_is_null(bysort)) NULL else bysort
    grouped <- inherits(data, "grouped_df")
    if (!is.null(by) && !is.null(bysort)) {
        stop("supply either `by` or `bysort`, not both", call. = FALSE)
    }
    if (grouped && (!is.null(by) || !is.null(bysort))) {
        stop(.MUTATION_GROUPED_MESSAGE, call. = FALSE)
    }
    if (grouped || !is.null(by) || !is.null(bysort)) {
        if (!kind %in% c("dta_mean", "dta_min", "dta_max", "dta_total")) {
            stop(sprintf("`%s()` does not allow outer `by` or `bysort`", kind),
                 call. = FALSE)
        }
        argument <- if (is.null(by)) "bysort" else "by"
        keys <- if (grouped) dplyr::group_vars(data) else
            .mutation_group_expression(
                rlang::quo_get_expr(if (is.null(by)) bysort else by),
                rlang::quo_get_env(if (is.null(by)) bysort else by), argument
            )
        if (!length(keys) || anyDuplicated(keys)) {
            stop("Grouping columns must be nonempty and unique", call. = FALSE)
        }
        columns <- lapply(keys, function(key) {
            if (!.has_mutation_column(original$columns, key)) {
                stop(sprintf("Column `%s` does not exist", key), call. = FALSE)
            }
            .mutation_column(original$columns, key)
        })
        names(columns) <- keys
        plan <- .dta_egen_key_plan(columns)
        groups <- unname(split(seq_len(original$nrow), plan$codes))
        sorted <- if (!is.null(bysort)) order(plan$codes, method = "radix") else NULL
        return(list(rows = groups, order = sorted))
    }
    list(rows = list(seq_len(original$nrow)), order = NULL)
}

# Validate source values when they are read, before allowing arithmetic NaN
# results. Native validation streams compact vectors without decoding them.
.egen_validate_source <- function(value) {
    previous <- .dta_egen_evaluation$allow_nan
    on.exit(.dta_egen_evaluation$allow_nan <- previous)
    .dta_egen_evaluation$allow_nan <- FALSE
    if (is.list(value) && !is.object(value)) {
        for (column in value) .egen_validate_source(column)
    } else if (is.data.frame(value)) {
        for (column in as.list(value)) .egen_validate_source(column)
    } else if (typeof(value) %in% c("double", "integer", "logical") &&
        .dta_egen_numeric_supported(value) && is.null(dim(value))) {
        .dta_egen_summary(value, 2L, FALSE)
    }
    invisible(NULL)
}

.egen_source_view <- function(columns) {
    view <- .mutation_group_view(columns)
    checked <- new.env(hash = TRUE, parent = emptyenv())
    source <- view$columns
    validated <- new.env(hash = TRUE, parent = emptyenv())
    for (name in ls(source, all.names = TRUE)) local({
        key <- name
        makeActiveBinding(key, function(value) {
            if (!missing(value)) stop("Calculation columns are read-only",
                                       call. = FALSE)
            value <- source[[key]]
            if (!isTRUE(checked[[key]])) {
                .egen_validate_source(.mutation_column(columns, key))
                checked[[key]] <- TRUE
            }
            value
        }, validated)
    })
    view$columns <- validated
    view
}

.egen_validate_external <- function(expression, frame, columns) {
    if (is.symbol(expression)) {
        name <- as.character(expression)
        if (!name %in% c(".data", ".env", ".n", ".N", ".") &&
            !.has_mutation_column(columns, name) &&
            exists(name, envir = frame, inherits = TRUE)) {
            .egen_validate_source(get(name, envir = frame, inherits = TRUE))
        }
    } else if (is.call(expression)) {
        if (identical(expression[[1L]], quote(`$`))) {
            # The field name is literal, not a second external variable.
            # Validate the extracted value at evaluation time, once its
            # possibly computed selector has run.
            .egen_validate_external(expression[[2L]], frame, columns)
        } else if (identical(expression[[1L]], quote(`::`))) {
            return(invisible(NULL))
        } else {
            for (piece in as.list(expression)[-1L]) {
                if (rlang::is_missing(piece)) next
                .egen_validate_external(piece, frame, columns)
            }
        }
    } else if (is.atomic(expression)) {
        .egen_validate_source(expression)
    }
    invisible(NULL)
}

.egen_checked_source <- function(value) {
    .egen_validate_source(value)
    value
}

.egen_storage_result <- function(.constructor, x, ...) {
    metadata <- attributes(x)
    result <- .constructor(x, ...)
    for (name in intersect(names(metadata), c("label", "labels", "notes",
        "stata.note.numbers", "value.label.name"))) {
        attr(result, name) <- metadata[[name]]
    }
    result
}

.egen_source_reference <- function(expression) {
    if (is.symbol(expression) || is.atomic(expression)) return(TRUE)
    if (!is.call(expression)) return(FALSE)
    head <- expression[[1L]]
    if (identical(head, quote(`$`)) || identical(head, quote(`[[`)) ||
        identical(head, quote(`[`)) || identical(head, quote(`(`))) {
        return(.egen_source_reference(expression[[2L]]))
    }
    FALSE
}

.egen_checked_extractions <- function(expression, frame) {
    if (!is.call(expression)) return(expression)
    if (identical(expression[[1L]], quote(`::`))) return(expression)
    extraction <- (identical(expression[[1L]], quote(`$`)) ||
        identical(expression[[1L]], quote(`[[`)) ||
        identical(expression[[1L]], quote(`[`))) &&
        .egen_source_reference(expression[[2L]])
    positions <- seq_along(expression)[-1L]
    if (identical(expression[[1L]], quote(`$`))) positions <- 2L
    for (position in positions) {
        piece <- expression[[position]]
        if (rlang::is_missing(piece)) next
        expression[[position]] <- .egen_checked_extractions(piece, frame)
    }
    if (extraction) return(as.call(list(.egen_checked_source, expression)))
    fun <- .egen_function(expression[[1L]], frame)
    for (name in paste0("dta_", c("byte", "int", "long", "float", "double"))) {
        if (identical(fun, get(name, envir = environment(egen)))) {
            return(as.call(c(list(.egen_storage_result, fun),
                             as.list(expression)[-1L])))
        }
    }
    expression
}

.egen_evaluate <- function(original, groups, where, positions, calculation) {
    view <- .egen_source_view(original$columns)
    quo <- calculation$quo
    .egen_validate_external(rlang::quo_get_expr(quo), rlang::quo_get_env(quo),
                            original$columns)
    group_rows <- groups$rows
    if (!length(group_rows)) group_rows <- list(integer())
    values <- rows <- vector("list", length(group_rows))
    count <- 0L
    for (index in seq_along(group_rows)) {
        full <- group_rows[[index]]
        size <- length(full)
        view$rows <- full
        view$cache <- new.env(hash = TRUE, parent = emptyenv())
        selected <- .mutation_rows(.eval_mutation_expression(
            where, view$columns, "where", list(.n = seq_len(size), .N = size)
        ), size)
        if (is.null(selected)) selected <- seq_len(size)
        selected <- sort(unique(as.integer(selected)))
        if (!is.null(positions)) {
            if (any(positions > size)) {
                stop("`rows` contains a position beyond the group row count",
                     call. = FALSE)
            }
            selected <- intersect(selected, positions)
        }
        admitted <- full[selected]
        if (!length(admitted)) next
        view$rows <- admitted
        view$cache <- new.env(hash = TRUE, parent = emptyenv())
        piece <- .egen_eval_value(quo, view$columns, length(admitted),
                                  calculation$shadow)
        size <- vctrs::vec_size(piece)
        if (!size %in% c(1L, length(admitted))) {
            stop("Calculation must return one value or one value per admitted row",
                 call. = FALSE)
        }
        count <- count + 1L
        values[[count]] <- vctrs::vec_recycle(piece, length(admitted))
        rows[[count]] <- admitted
    }
    if (!count) {
        view$rows <- integer()
        view$cache <- new.env(hash = TRUE, parent = emptyenv())
        piece <- .egen_eval_value(quo, view$columns, 0L, calculation$shadow)
        return(list(values = vctrs::vec_slice(piece, integer()), rows = integer()))
    }
    values <- values[seq_len(count)]
    admitted_rows <- unlist(rows[seq_len(count)], use.names = FALSE)
    result <- .mutation_gather_values(values)
    order <- order(admitted_rows)
    list(values = vctrs::vec_slice(result, order),
         rows = if (length(admitted_rows) == original$nrow) NULL else admitted_rows[order])
}

.egen_eval_value <- function(quo, columns, size, shadow) {
    previous <- .dta_egen_evaluation$allow_nan
    on.exit(.dta_egen_evaluation$allow_nan <- previous)
    .dta_egen_evaluation$allow_nan <- TRUE
    quo <- rlang::quo_set_expr(quo,
        .egen_checked_extractions(rlang::quo_get_expr(quo), rlang::quo_get_env(quo)))
    .eval_in_mutation_data(quo, columns, extras = list(.n = seq_len(size), .N = size),
                           shadow = shadow)
}
