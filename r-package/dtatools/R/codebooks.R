#' Describe named Stata value-label tables
#'
#' `labelbook()` reports the value-label tables assigned to the current
#' variables. It is the table-centered companion to [codebook()].
#'
#' @param data A data frame, tibble, data table, or one `.dta` or `.arrow` path.
#' @param ... Exact unquoted table names.
#' @param .tables Exact table names supplied as a character vector. Do not use
#'   with `...`.
#' @param order Mapping order: Stata value order, text order, or recorded
#'   definition order.
#' @param length Comparison length for truncated label uniqueness.
#' @param list_limit Maximum mappings printed per table. The result retains all
#'   mappings. Unlike Stata's random subset, dtatools lists the first mappings
#'   in report order.
#' @param problems Print the problem report instead of the standard report.
#' @param detail With `problems`, also print the normal detailed report.
#' @return A `dtatools_labelbook` list with data-frame components `tables`,
#'   `mappings`, `assignments`, and `diagnostics`.
#' @export
labelbook <- function(data, ..., .tables = NULL,
                      order = c("value", "alpha", "definition"),
                      length = 12L, list_limit = 32000L,
                      problems = FALSE, detail = FALSE) {
    dots <- rlang::enquos(...)
    order <- match.arg(order)
    length <- .book_whole(length, "length", minimum = 1)
    list_limit <- .book_whole(list_limit, "list_limit", minimum = 0,
                              infinite = TRUE)
    problems <- .book_flag(problems, "problems")
    detail <- .book_flag(detail, "detail")
    if (detail && !problems) {
        stop("`detail` may be used only with `problems = TRUE`", call. = FALSE)
    }
    selection <- .book_names(dots, .tables, "table")
    input <- .labelbook_input(data)
    data <- input$data

    diagnostics <- list()
    registry_ok <- vapply(input$registry, .labelbook_shape_ok, logical(1))
    candidates <- lapply(input$registry[registry_ok], function(labels) list(list(
        labels = labels, variable = NA_character_, position = NA_integer_
    )))
    for (table in names(input$registry)[!registry_ok]) {
        diagnostics[[length(diagnostics) + 1L]] <- .book_diag(
            "malformed_value_labels", "table", table,
            message = "Value-label registry entry cannot be interpreted safely"
        )
    }
    assignments <- list()
    for (position in seq_along(data)) {
        column <- data[[position]]
        labels <- attr(column, "labels", exact = TRUE)
        explicit <- attr(column, "value.label.name", exact = TRUE)
        if (is.null(labels) && is.null(explicit)) next
        table <- if (is.null(explicit)) names(data)[[position]] else explicit
        assignments[[length(assignments) + 1L]] <- data.frame(
            table = if (.book_scalar_text(table)) table else NA_character_,
            variable = names(data)[[position]], position = position,
            stringsAsFactors = FALSE
        )
        if (!.book_scalar_text(table)) {
            diagnostics[[length(diagnostics) + 1L]] <- .book_diag(
                "invalid_table_name", "variable", table = NA_character_,
                variable = names(data)[[position]], position = position,
                message = "Variable has an invalid value-label table reference"
            )
            next
        }
        if (!.labelbook_shape_ok(labels)) {
            diagnostics[[length(diagnostics) + 1L]] <- .book_diag(
                "malformed_value_labels", "variable", table, names(data)[[position]],
                position, message = "Value-label metadata cannot be interpreted safely"
            )
            next
        }
        candidates[[table]] <- c(candidates[[table]], list(list(
            labels = labels, variable = names(data)[[position]], position = position
        )))
    }
    available <- unique(c(
        names(input$registry), names(candidates),
        vapply(assignments, `[[`, "", "table")
    ))
    available <- available[!is.na(available)]
    selected <- if (is.null(selection)) available else selection
    unknown <- setdiff(selected, available)
    if (length(unknown)) {
        stop("unknown value-label table `", unknown[[1L]], "`", call. = FALSE)
    }

    table_rows <- list()
    mapping_rows <- list()
    for (table in selected) {
        variants <- candidates[[table]]
        if (is.null(variants)) {
            table_rows[[length(table_rows) + 1L]] <- .labelbook_table_row(
                table, NULL, length, malformed = TRUE
            )
            next
        }
        keys <- vapply(variants, function(x) .book_mapping_signature(x$labels), "")
        malformed <- length(unique(keys)) > 1L
        if (malformed) {
            diagnostics[[length(diagnostics) + 1L]] <- .book_diag(
                "inconsistent_resolved_mappings", "table", table,
                message = paste0("Variables assigned to `", table,
                                 "` carry different resolved mappings"),
                details = list(lapply(variants, function(x) list(
                    variable = x$variable, position = x$position, labels = x$labels
                )))
            )
            table_rows[[length(table_rows) + 1L]] <- .labelbook_table_row(
                table, NULL, length, malformed = TRUE
            )
            next
        }
        labels <- variants[[1L]]$labels
        info <- .labelbook_mapping_frame(table, labels, order)
        mapping_rows[[length(mapping_rows) + 1L]] <- info
        table_rows[[length(table_rows) + 1L]] <- .labelbook_table_row(
            table, labels, length, malformed = FALSE
        )
        diagnostics <- c(diagnostics, .labelbook_diagnostics(
            table, labels, length,
            variables = stats::na.omit(vapply(variants, `[[`, "", "variable"))
        ))
    }

    assignments <- .book_bind(assignments, .labelbook_assignments())
    assignments <- assignments[assignments$table %in% selected, , drop = FALSE]
    result <- structure(list(
        tables = .book_bind(table_rows, .labelbook_tables()),
        mappings = .book_bind(mapping_rows, .labelbook_mappings()),
        assignments = assignments,
        diagnostics = .book_bind(diagnostics, .book_diagnostics()),
        options = list(order = order, length = length, list_limit = list_limit,
                       problems = problems, detail = detail),
        source = input$source
    ), class = "dtatools_labelbook")
    result
}

.labelbook_shape_ok <- function(labels) {
    is.numeric(labels) && !is.null(names(labels)) &&
        length(names(labels)) == length(labels) && !anyNA(names(labels))
}

.labelbook_tables <- function() data.frame(
    table = character(), mapping_count = integer(), minimum = double(),
    maximum = double(), missing_mapping_count = integer(),
    minimum_text_length = integer(), maximum_text_length = integer(),
    unique_full = logical(), unique_truncated = logical(), malformed = logical(),
    stringsAsFactors = FALSE
)

.labelbook_mappings <- function() data.frame(
    table = character(), source_position = integer(), code = double(),
    missing_code = character(), code_text = character(), text = character(),
    stringsAsFactors = FALSE
)

.labelbook_assignments <- function() data.frame(
    table = character(), variable = character(), position = integer(),
    stringsAsFactors = FALSE
)

.labelbook_table_row <- function(table, labels, compare_length, malformed) {
    if (is.null(labels)) return(data.frame(
        table, mapping_count = NA_integer_, minimum = NA_real_, maximum = NA_real_,
        missing_mapping_count = NA_integer_, minimum_text_length = NA_integer_,
        maximum_text_length = NA_integer_, unique_full = NA, unique_truncated = NA,
        malformed = TRUE, stringsAsFactors = FALSE
    ))
    codes <- .book_codes(labels)
    ordinary <- is.na(codes$missing_code)
    text_length <- nchar(enc2utf8(names(labels)), type = "chars")
    range <- if (any(ordinary)) range(as.double(labels[ordinary])) else c(NA, NA)
    data.frame(
        table, mapping_count = length(labels), minimum = range[[1L]],
        maximum = range[[2L]], missing_mapping_count = sum(!ordinary),
        minimum_text_length = if (length(text_length)) min(text_length) else NA_integer_,
        maximum_text_length = if (length(text_length)) max(text_length) else NA_integer_,
        unique_full = !anyDuplicated(names(labels)),
        unique_truncated = !anyDuplicated(substr(names(labels), 1L, compare_length)),
        malformed, stringsAsFactors = FALSE
    )
}

.labelbook_mapping_frame <- function(table, labels, order) {
    codes <- .book_codes(labels)
    result <- data.frame(
        table, source_position = seq_along(labels), code = as.double(labels),
        missing_code = codes$missing_code, code_text = codes$text,
        text = names(labels), stringsAsFactors = FALSE
    )
    index <- switch(order,
        definition = seq_len(nrow(result)),
        alpha = order(enc2utf8(result$text), result$source_position, method = "radix"),
        value = order(codes$rank, result$code, result$source_position, na.last = TRUE,
                      method = "radix")
    )
    result[index, , drop = FALSE]
}

.labelbook_diagnostics <- function(table, labels, compare_length, variables) {
    result <- list()
    codes <- .book_codes(labels)
    ordinary <- as.double(labels[is.na(codes$missing_code)])
    add <- function(code, condition, message, details = list()) {
        if (condition) result[[length(result) + 1L]] <<- .book_diag(
            code, "table", table, message = message,
            details = list(c(list(variables = variables), details))
        )
    }
    sorted <- sort(unique(ordinary))
    gaps <- length(sorted) > 1L && all(sorted == floor(sorted)) &&
        any(diff(sorted) > 1)
    text <- names(labels)
    keys <- .dta_value_label_keys(labels)
    add("invalid_table_name", !.valid_dta_name_syntax(table, 32L),
        "Table name is not a valid Stata name")
    add("duplicate_codes", anyDuplicated(keys) > 0L,
        "Value-label table contains duplicate codes")
    add("gaps", gaps, "Mapped integer values contain gaps")
    add("leading_or_trailing_blanks", any(grepl("^\\s|\\s$", text)),
        "Label text contains leading or trailing blanks")
    add("duplicate_label_text", anyDuplicated(text) > 0L,
        "Different codes use the same full label text")
    add("duplicate_truncated_text", anyDuplicated(substr(text, 1L, compare_length)) > 0L,
        "Different codes use the same truncated label text")
    numeric_text <- suppressWarnings(!is.na(as.double(trimws(text)))) & nzchar(trimws(text))
    add("numeric_label_text", any(numeric_text), "Numeric codes map to numeric-looking text")
    add("empty_label_text", any(text == ""), "Numeric codes map to empty text")
    add("unassigned_table", !length(variables),
        "Value-label table is not assigned to any variable")
    result
}

#' Describe variables and observed data
#'
#' `codebook()` returns Stata-shaped variable metadata, summaries,
#' tabulations, notes, missingness relationships, and diagnostics.
#'
#' @inheritParams labelbook
#' @param ... Exact unquoted variable names.
#' @param .vars Exact variable names supplied as a character vector.
#' @param where A logical expression or numeric row positions evaluated in the
#'   full dataset. Duplicate positions are discarded.
#' @param all Equivalent to `header = TRUE, notes = TRUE`.
#' @param header Include known dataset metadata.
#' @param notes Include variable notes.
#' @param mv Analyze pairwise missingness implications.
#' @param tabulate Maximum unique nonmissing values for categorical tabulation.
#' @param compact Return and print the compact variable report.
#' @param dots Print one progress dot per variable. Valid only with `compact`.
#' @param diagnostic_limit Maximum example row positions retained per
#'   row-level diagnostic. Use `Inf` for all and zero for none.
#' @return A `dtatools_codebook` list with documented data-frame components.
#' @export
codebook <- function(data, ..., .vars = NULL, where = NULL, all = FALSE,
                     header = FALSE, notes = FALSE, mv = FALSE, tabulate = 9L,
                     problems = FALSE, detail = FALSE, compact = FALSE,
                     dots = FALSE, diagnostic_limit = 100L) {
    selections <- rlang::enquos(...)
    where_quo <- rlang::enquo(where)
    vars <- .book_names(selections, .vars, "variable")
    flags <- lapply(list(all = all, header = header, notes = notes, mv = mv,
                         problems = problems, detail = detail, compact = compact,
                         dots = dots), function(x) x)
    flags <- Map(.book_flag, flags, names(flags))
    list2env(flags, environment())
    tabulate <- .book_whole(tabulate, "tabulate", minimum = 0)
    diagnostic_limit <- .book_whole(diagnostic_limit, "diagnostic_limit",
                                    minimum = 0, infinite = TRUE)
    if (detail && !problems) stop("`detail` requires `problems = TRUE`", call. = FALSE)
    if (dots && !compact) stop("`dots` requires `compact = TRUE`", call. = FALSE)
    if (compact && any(c(all, header, notes, mv, problems, detail))) {
        stop("`compact` may be combined only with `dots`", call. = FALSE)
    }
    if (all) header <- notes <- TRUE
    input <- .book_input(data)
    data <- input$data
    positions <- .codebook_variable_positions(data, vars)
    rows <- .codebook_rows(where_quo, data)
    selected <- if (is.null(rows)) data else data[rows, , drop = FALSE]
    source_rows <- if (is.null(rows)) seq_len(nrow(data)) else rows

    variables <- list(); tabulations <- list(); examples <- list(); diagnostics <- list()
    note_rows <- list(); missing_masks <- list()
    for (i in seq_along(positions)) {
        position <- positions[[i]]
        name <- names(data)[[position]]
        column <- selected[[position]]
        summary <- .codebook_variable(column, name, position, tabulate, compact)
        variables[[length(variables) + 1L]] <- summary$variable
        tabulations[[length(tabulations) + 1L]] <- summary$tabulation
        examples[[length(examples) + 1L]] <- summary$examples
        diagnostics <- c(diagnostics, .codebook_diagnostics(
            column, name, position, source_rows, diagnostic_limit
        ))
        missing_masks[[as.character(position)]] <- .codebook_missing(column)
        if (notes) {
            variable_notes <- dta_notes(data, variable = position)
            if (length(variable_notes)) note_rows[[length(note_rows) + 1L]] <- data.frame(
                position, variable = name, number = as.integer(names(variable_notes)),
                text = unname(variable_notes), stringsAsFactors = FALSE
            )
        }
        if (dots) cat(".")
    }
    if (dots) cat("\n")
    if (length(positions)) {
        duplicate <- vctrs::vec_duplicate_detect(selected[positions])
        diagnostics <- c(diagnostics, .book_row_diag(
            "duplicate_observations", "Selected variables contain duplicate observations",
            source_rows[duplicate], diagnostic_limit
        ))
        all_missing <- if (length(missing_masks)) Reduce(`&`, missing_masks) else logical()
        diagnostics <- c(diagnostics, .book_row_diag(
            "all_selected_variables_missing",
            "Observations are missing across every selected variable",
            source_rows[all_missing], diagnostic_limit
        ))
    }
    relationships <- if (mv) .codebook_missing_relationships(
        missing_masks, names(data)[positions], positions
    ) else .codebook_relationships()
    structure(list(
        variables = .book_bind(variables, .codebook_variables()),
        tabulations = .book_bind(tabulations, .codebook_tabulations()),
        examples = .book_bind(examples, .codebook_examples()),
        missing_relationships = relationships,
        notes = .book_bind(note_rows, .codebook_notes()),
        diagnostics = .book_bind(diagnostics, .book_diagnostics()),
        header = if (header) .codebook_header(data, input$source) else NULL,
        options = list(mode = if (compact) "compact" else "standard",
                       problems = problems, detail = detail, mv = mv,
                       tabulate = tabulate), source = input$source
    ), class = "dtatools_codebook")
}

.codebook_variables <- function() data.frame(
    position = integer(), variable = character(), label = character(),
    type = character(), storage = character(), format = character(),
    value_label_table = character(), report_type = character(), observations = integer(),
    unique_nonmissing = integer(), missing_count = integer(),
    system_missing_count = integer(), extended_missing_count = integer(),
    nan_count = integer(), empty_count = integer(), na_string_count = integer(),
    minimum = double(), maximum = double(), unit = double(), mean = double(),
    sd = double(), p10 = double(), p25 = double(), p50 = double(),
    p75 = double(), p90 = double(), stringsAsFactors = FALSE
)

.codebook_tabulations <- function() data.frame(
    position = integer(), variable = character(), value = character(),
    numeric_value = double(), missing_code = character(), label = character(),
    frequency = integer(), stringsAsFactors = FALSE
)

.codebook_examples <- function() data.frame(
    position = integer(), variable = character(), example = character(),
    stringsAsFactors = FALSE
)

.codebook_notes <- function() data.frame(
    position = integer(), variable = character(), number = integer(), text = character(),
    stringsAsFactors = FALSE
)

.codebook_relationships <- function() data.frame(
    left_position = integer(), left_variable = character(), relationship = character(),
    right_position = integer(), right_variable = character(), stringsAsFactors = FALSE
)

.codebook_variable <- function(x, name, position, threshold, compact) {
    supported <- is.atomic(x) && is.null(dim(x)) || is.factor(x)
    missing <- if (supported) .codebook_missing(x) else rep(FALSE, length(x))
    observed <- x[!missing]
    unique_count <- if (supported) length(unique(observed)) else NA_integer_
    numeric <- supported && (is.numeric(x) || is.logical(x)) && !is.factor(x)
    categorical <- supported && (is.factor(x) || is.logical(x) ||
        (numeric && unique_count <= threshold))
    report_type <- if (!supported) "unsupported" else if (categorical) {
        "categorical"
    } else if (numeric) "continuous" else "examples"
    storage <- if (inherits(x, "dta_numeric") || inherits(x, "dta_temporal")) {
        .declared_dta_storage(x)
    } else if (is.character(x) && !is.null(dta_storage_type(x))) {
        # Stata's codebook names a string variable's storage `str8` or `strL`,
        # and a `gen()` string carries the declaration without the
        # `dta_string` class, so the declaration is the test.
        dta_storage_type(x)
    } else typeof(x)
    type <- if (is.ordered(x)) "ordered factor" else if (is.factor(x)) "factor" else {
        paste(class(x), collapse = "/")
    }
    if (!nzchar(type)) type <- typeof(x)
    codes <- if (is.numeric(x)) .book_codes(x) else list(missing_code = rep(NA_character_, length(x)))
    system <- if (is.numeric(x)) codes$missing_code == "." & !is.na(codes$missing_code) else rep(FALSE, length(x))
    extended <- if (is.numeric(x)) grepl("^\\.[a-z]$", codes$missing_code) & !is.na(codes$missing_code) else rep(FALSE, length(x))
    finite_observed <- if (numeric) .book_numeric_data(observed) else double()
    stats <- rep(NA_real_, 10L)
    if (numeric && length(finite_observed)) {
        q <- stats::quantile(finite_observed, c(.1, .25, .5, .75, .9),
                             names = FALSE, type = 2)
        sorted <- sort(unique(finite_observed))
        unit <- if (length(sorted) < 2L) NA_real_ else min(diff(sorted))
        stats <- c(min(finite_observed), max(finite_observed), unit,
                   mean(finite_observed), if (length(finite_observed) > 1L) stats::sd(finite_observed) else NA,
                   q)
    }
    labels <- attr(x, "labels", exact = TRUE)
    table_name <- attr(x, "value.label.name", exact = TRUE)
    if (is.null(table_name) && !is.null(labels)) table_name <- name
    variable <- data.frame(
        position, variable = name,
        label = .book_or_na(attr(x, "label", exact = TRUE)), type,
        storage = .book_or_na(storage), format = .book_or_na(attr(x, "format.stata", exact = TRUE)),
        value_label_table = .book_or_na(table_name), report_type,
        observations = length(x), unique_nonmissing = unique_count,
        missing_count = sum(missing), system_missing_count = sum(system),
        extended_missing_count = sum(extended), nan_count = if (is.numeric(x)) sum(is.nan(x)) else 0L,
        empty_count = if (is.character(x)) sum(x == "", na.rm = TRUE) else 0L,
        na_string_count = if (is.character(x)) sum(is.na(x)) else 0L,
        minimum = stats[[1L]], maximum = stats[[2L]], unit = stats[[3L]],
        mean = stats[[4L]], sd = stats[[5L]], p10 = stats[[6L]], p25 = stats[[7L]],
        p50 = stats[[8L]], p75 = stats[[9L]], p90 = stats[[10L]],
        stringsAsFactors = FALSE
    )
    tabulation <- if (!compact && categorical) .codebook_tabulate(x, name, position) else .codebook_tabulations()
    example <- if (!compact && report_type == "examples") {
        values <- unique(as.character(observed)); values <- utils::head(values, 5L)
        data.frame(position = rep(position, length(values)),
                   variable = rep(name, length(values)), example = values,
                   stringsAsFactors = FALSE)
    } else .codebook_examples()
    list(variable = variable, tabulation = tabulation, examples = example)
}

.codebook_tabulate <- function(x, name, position) {
    factorized <- if (is.numeric(x) && !is.factor(x)) {
        .prepare_tab_argument(x, "distinguish", "value")
    } else addNA(x, ifany = TRUE)
    counts <- table(factorized, useNA = "ifany")
    if (!length(counts)) return(.codebook_tabulations())
    displayed <- names(counts)
    numeric_value <- suppressWarnings(as.double(displayed))
    missing_code <- ifelse(grepl("^\\.[a-z]$|^\\.$|^NaN$", displayed), displayed, NA_character_)
    labels <- rep(NA_character_, length(displayed))
    source_labels <- attr(x, "labels", exact = TRUE)
    if (is.numeric(x) && .valid_tab_labels(source_labels)) {
        prepared <- .prepare_tab_argument(x, "distinguish", "label")
        label_counts <- table(prepared, useNA = "ifany")
        if (length(label_counts) == length(counts)) labels <- names(label_counts)
    } else if (is.factor(x)) labels <- displayed
    data.frame(position, variable = name, value = displayed, numeric_value,
               missing_code, label = labels, frequency = as.integer(counts),
               stringsAsFactors = FALSE)
}

.codebook_diagnostics <- function(x, name, position, source_rows, limit) {
    result <- list(); add <- function(code, condition, message, severity = "problem", details = list()) {
        if (condition) result[[length(result) + 1L]] <<- .book_diag(
            code, "variable", variable = name, position = position,
            severity = severity, message = message, details = list(details)
        )
    }
    supported <- is.atomic(x) && is.null(dim(x)) || is.factor(x)
    missing <- if (supported) .codebook_missing(x) else logical()
    add("unsupported_column", !supported,
        "Column type is not supported", "suggestion")
    add("constant_or_all_missing", supported && length(x) > 0L &&
            length(unique(x[!missing])) <= 1L,
        "Variable is constant or always missing")
    if (is.character(x)) {
        observed <- x[!is.na(x)]
        add("leading_blanks", any(grepl("^\\s", observed)), "Strings contain leading blanks")
        add("trailing_blanks", any(grepl("\\s$", observed)), "Strings contain trailing blanks")
        add("embedded_blanks", any(grepl("\\S\\s+\\S", observed)), "Strings contain embedded blanks")
        declared <- attr(x, "stata.string.storage", exact = TRUE)
        # The declaration is `str8` or `strL`, never a number. Only a fixed
        # width can be compared with the bytes the values need.
        width <- if (is.character(declared) && length(declared) == 1L &&
            !is.na(declared) && grepl("^str[0-9]+$", declared)) {
            as.integer(sub("^str", "", declared))
        } else NULL
        needed <- if (length(observed)) max(nchar(enc2utf8(observed), type = "bytes")) else 0L
        add("string_storage_wider_than_required",
            !is.null(width) && width > needed,
            "Declared string storage is wider than required", "suggestion",
            list(declared = declared, required = needed))
        add("few_unique_strings", length(unique(observed[observed != ""])) <= 9L &&
                length(unique(observed[observed != ""])) > 0L,
            "String variable has few unique values and may be better represented as labelled numeric data",
            "suggestion")
    }
    labels <- attr(x, "labels", exact = TRUE)
    reference <- attr(x, "value.label.name", exact = TRUE)
    add("undefined_value_label_table", !is.null(reference) && is.null(labels),
        "Variable refers to an undefined value-label table")
    if (is.numeric(x) && !is.null(labels) && .valid_tab_labels(labels)) {
        observed <- .book_numeric_data(x[!missing])
        uncovered <- !(.dta_value_label_keys(observed) %in% .dta_value_label_keys(labels))
        add("incomplete_value_labels", any(uncovered), "Observed values are not fully value labelled",
            details = list(values = unique(observed[uncovered])))
    }
    format <- attr(x, "format.stata", exact = TRUE)
    if (is.numeric(x) && .book_scalar_text(format) && grepl("^%t", format)) {
        date_values <- .book_numeric_data(x[!missing])
        add("noninteger_date_values", any(date_values != floor(date_values)),
            "Date variable contains noninteger values")
    }
    declared <- if (inherits(x, "dta_numeric") || inherits(x, "dta_temporal")) {
        .declared_dta_storage(x)
    } else NULL
    if (!is.null(declared) && is.numeric(x)) {
        observed <- .book_numeric_data(x[!missing])
        narrower <- .codebook_narrower_storage(observed, declared)
        add("numeric_storage_may_be_compressed", !is.null(narrower),
            "Numeric storage may be compressed", "suggestion",
            list(declared = declared, suggested = narrower))
    }
    result
}

.codebook_narrower_storage <- function(values, declared) {
    if (!length(values) || any(!is.finite(values))) return(NULL)
    whole <- all(values == floor(values))
    target <- if (whole && all(values >= -127 & values <= 100)) {
        "byte"
    } else if (whole && all(values >= -32767 & values <= 32740)) {
        "int"
    } else if (whole && all(values >= -2147483647 & values <= 2147483620)) {
        "long"
    } else if (all(abs(values) <= .dta_float_max)) "float" else "double"
    ranks <- c(byte = 1L, int = 2L, long = 3L, float = 4L, double = 5L)
    if (!declared %in% names(ranks) || ranks[[target]] >= ranks[[declared]]) NULL else target
}

.codebook_missing <- function(x) {
    if (is.factor(x)) return(is.na(x))
    if (is.character(x)) return(is.na(x) | x == "")
    if (is.numeric(x) || is.logical(x) || inherits(x, c("Date", "POSIXct", "difftime"))) return(is.na(x))
    rep(FALSE, length(x))
}

.codebook_missing_relationships <- function(masks, names, positions) {
    if (length(masks) < 2L || !length(masks[[1L]])) return(.codebook_relationships())
    rows <- list()
    for (i in seq_along(masks)) for (j in seq_along(masks)) {
        if (i == j) next
        implies <- all(!masks[[i]] | masks[[j]]) && any(masks[[i]])
        reverse <- all(!masks[[j]] | masks[[i]]) && any(masks[[j]])
        if (implies && (!reverse || i < j)) rows[[length(rows) + 1L]] <- data.frame(
            left_position = positions[[i]], left_variable = names[[i]],
            relationship = if (reverse) "equivalent" else "implies",
            right_position = positions[[j]], right_variable = names[[j]],
            stringsAsFactors = FALSE
        )
    }
    .book_bind(rows, .codebook_relationships())
}

.codebook_rows <- function(where, data) {
    if (rlang::quo_is_null(where)) return(NULL)
    value <- .eval_mutation_expression(where, as.list(data), "where")
    rows <- .mutation_rows(value, nrow(data))
    if (is.null(rows)) return(NULL)
    unique(as.integer(rows))
}

.codebook_header <- function(data, source) list(
    source = source, label = dataset_label(data), variables = ncol(data), observations = nrow(data)
)

.codebook_variable_positions <- function(data, vars) {
    if (is.null(vars)) return(seq_along(data))
    duplicates <- unique(names(data)[duplicated(names(data)) | duplicated(names(data), fromLast = TRUE)])
    ambiguous <- intersect(vars, duplicates)
    if (length(ambiguous)) stop("variable `", ambiguous[[1L]], "` is ambiguous", call. = FALSE)
    unknown <- setdiff(vars, names(data))
    if (length(unknown)) stop("unknown variable `", unknown[[1L]], "`", call. = FALSE)
    match(vars, names(data))
}

.book_input <- function(data) {
    if (is.data.frame(data)) return(list(data = data, source = NULL))
    if (.book_scalar_text(data)) {
        extension <- tolower(tools::file_ext(data))
        reader <- switch(extension, dta = read_dta, arrow = read_arrow, NULL)
        if (is.null(reader)) stop("path input must end in `.dta` or `.arrow`", call. = FALSE)
        return(list(data = reader(data, .name_repair = "minimal"), source = data))
    }
    stop("`data` must be a data frame or one `.dta` or `.arrow` path", call. = FALSE)
}

.labelbook_input <- function(data) {
    if (.book_scalar_text(data) && identical(tolower(tools::file_ext(data)), "dta")) {
        metadata <- .dta_metadata(data, include_value_labels = TRUE)
        registry <- attr(metadata, "dta_value_label_registry", exact = TRUE)
        references <- attr(metadata, "dta_value_label_names", exact = TRUE)
        columns <- lapply(references, function(reference) {
            value <- double()
            if (nzchar(reference)) {
                attr(value, "labels") <- registry[[reference]]
                attr(value, "value.label.name") <- reference
            }
            value
        })
        names(columns) <- as.character(metadata)
        frame <- as.data.frame(columns, optional = TRUE, stringsAsFactors = FALSE)
        names(frame) <- as.character(metadata)
        return(list(data = frame, registry = registry, source = data))
    }
    if (.book_scalar_text(data) && identical(tolower(tools::file_ext(data)), "arrow")) {
        source <- .resolve_dta_source(
            data, fileext = ".arrow", implicit_extension = FALSE
        )
        snapshot <- NULL
        on.exit({
            if (!is.null(snapshot)) .Call(C_dtatools_close_arrow, snapshot)
            .cleanup_dta_source(source)
        }, add = TRUE)
        snapshot <- .Call(C_dtatools_open_arrow, source$path)
        metadata <- .arrow_metadata(snapshot, profile = TRUE)
        registry <- metadata$value_label_registry
        columns <- lapply(metadata$value_label_names, function(reference) {
            value <- double()
            if (nzchar(reference)) {
                attr(value, "labels") <- registry[[reference]]
                attr(value, "value.label.name") <- reference
            }
            value
        })
        names(columns) <- metadata$names
        frame <- as.data.frame(columns, optional = TRUE, stringsAsFactors = FALSE)
        names(frame) <- metadata$names
        return(list(data = frame, registry = registry, source = data))
    }
    input <- .book_input(data)
    input$registry <- list()
    input
}

.book_names <- function(dots, programmatic, kind) {
    if (length(dots) && !is.null(programmatic)) {
        stop("unquoted selections and the programmatic selection cannot be combined", call. = FALSE)
    }
    if (!is.null(programmatic)) {
        if (!is.character(programmatic) || anyNA(programmatic)) {
            stop("programmatic selections must be a character vector", call. = FALSE)
        }
        return(programmatic)
    }
    if (!length(dots)) return(NULL)
    vapply(dots, function(x) {
        expr <- rlang::quo_get_expr(x)
        if (!rlang::is_symbol(expr)) stop("unquoted ", kind, " selections must be names", call. = FALSE)
        rlang::as_name(expr)
    }, "")
}

.book_codes <- function(x) {
    raw <- .tab_missing_codes(x)
    values <- .book_numeric_data(x)
    missing <- rep(NA_character_, length(x)); rank <- rep(0L, length(x))
    system <- !is.na(raw) & raw == 0L
    tagged <- !is.na(raw) & raw >= utf8ToInt("a") & raw <= utf8ToInt("z")
    nan <- !is.na(raw) & raw == 256L
    missing[system] <- "."; rank[system] <- 1L
    missing[tagged] <- paste0(".", intToUtf8(raw[tagged], multiple = TRUE)); rank[tagged] <- raw[tagged] - 95L
    missing[nan] <- "NaN"; rank[nan] <- 28L
    text <- ifelse(is.na(missing), format(values, trim = TRUE, scientific = FALSE), missing)
    list(missing_code = missing, rank = rank, text = text)
}

.book_numeric_data <- function(x) {
    if (!is.object(x)) return(as.double(x))
    value <- unclass(x)
    attributes(value) <- NULL
    as.double(value)
}

.book_mapping_signature <- function(labels) paste(
    .dta_value_label_keys(labels), enc2utf8(names(labels)), collapse = "\r"
)

.book_diag <- function(code, scope, table = NA_character_, variable = NA_character_,
                       position = NA_integer_, severity = "problem", details = list(), message) {
    data.frame(code, scope, table, variable, position = as.integer(position), severity,
               details = I(list(details)), message, stringsAsFactors = FALSE)
}

.book_row_diag <- function(code, message, rows, limit) {
    if (!length(rows)) return(list())
    examples <- if (is.infinite(limit)) rows else utils::head(rows, limit)
    list(.book_diag(code, "observation", message = message,
                    details = list(list(count = length(rows), rows = examples))))
}

.book_diagnostics <- function() data.frame(
    code = character(), scope = character(), table = character(), variable = character(),
    position = integer(), severity = character(), details = I(list()),
    message = character(), stringsAsFactors = FALSE
)

.book_bind <- function(rows, empty) {
    rows <- Filter(function(x) !is.null(x) && nrow(x), rows)
    if (!length(rows)) return(empty)
    result <- do.call(rbind, rows); rownames(result) <- NULL; result
}

.book_flag <- function(x, name) {
    if (!is.logical(x) || length(x) != 1L || is.na(x)) stop("`", name, "` must be one logical value", call. = FALSE)
    x
}

.book_whole <- function(x, name, minimum, infinite = FALSE) {
    valid <- is.numeric(x) && length(x) == 1L && !is.na(x) && x >= minimum &&
        (is.finite(x) && x == floor(x) || infinite && is.infinite(x) && x > 0)
    if (!valid) stop("`", name, "` must be one whole number", call. = FALSE)
    x
}

.book_scalar_text <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
.book_or_na <- function(x) if (.book_scalar_text(x)) x else NA_character_

#' @export
print.dtatools_labelbook <- function(x, ...) {
    if (x$options$problems) {
        cat("Potential problems\n")
        if (!nrow(x$diagnostics)) cat("  none\n") else print(x$diagnostics[c("code", "table", "variable", "message")], row.names = FALSE)
        if (!x$options$detail) return(invisible(x))
        cat("\n")
    }
    if (!nrow(x$tables)) { cat("No value-label tables\n"); return(invisible(x)) }
    for (i in seq_len(nrow(x$tables))) {
        info <- x$tables[i, ]
        cat(if (i > 1L) "\n" else "", "Value label ", info$table, "\n", sep = "")
        print(info, row.names = FALSE)
        mappings <- x$mappings[x$mappings$table == info$table, , drop = FALSE]
        limit <- x$options$list_limit
        if (limit > 0 && nrow(mappings)) print(utils::head(mappings[c("code_text", "text")], limit), row.names = FALSE)
        assigned <- x$assignments$variable[x$assignments$table == info$table]
        cat("Variables: ", if (length(assigned)) paste(assigned, collapse = " ") else "(none)", "\n", sep = "")
    }
    invisible(x)
}

#' @export
print.dtatools_codebook <- function(x, ...) {
    if (x$options$problems) {
        cat("Potential problems\n")
        if (!nrow(x$diagnostics)) cat("  none\n") else print(x$diagnostics[c("code", "variable", "message")], row.names = FALSE)
        if (!x$options$detail) return(invisible(x))
        cat("\n")
    }
    if (!is.null(x$header)) print(x$header)
    if (!nrow(x$variables)) { cat("No variables\n"); return(invisible(x)) }
    if (identical(x$options$mode, "compact")) {
        print(x$variables[c("variable", "observations", "unique_nonmissing", "mean", "minimum", "maximum", "label")], row.names = FALSE)
        return(invisible(x))
    }
    for (i in seq_len(nrow(x$variables))) {
        variable <- x$variables[i, ]
        cat("\n", variable$variable, if (!is.na(variable$label)) paste0("  ", variable$label) else "", "\n", sep = "")
        print(variable, row.names = FALSE)
        tabulation <- x$tabulations[x$tabulations$position == variable$position, , drop = FALSE]
        if (nrow(tabulation)) print(tabulation[c("frequency", "value", "label")], row.names = FALSE)
        examples <- x$examples$example[x$examples$position == variable$position]
        if (length(examples)) cat("Examples: ", paste(examples, collapse = ", "), "\n", sep = "")
    }
    invisible(x)
}
