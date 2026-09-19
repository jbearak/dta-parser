#' Tabulate vectors as Stata's `tabulate` does
#'
#' Creates one-way and two-way frequency tables that print as Stata's
#' `tabulate` prints them, using the value labels and extended missing codes
#' carried by vectors returned by [`read_dta()`][dtatools::read_dta]. Three
#' or more vectors give an R multidimensional table, which Stata's `tabulate`
#' does not offer. Ordinary unlabelled vectors keep the behavior of
#' [base::table()] for their categories.
#'
#' @param x A vector, or a data frame whose columns should be tabulated. When
#'   `data` is supplied, an unquoted column name. The argument may be omitted
#'   when `data` is supplied or named vectors are passed through `...`.
#' @param ... Additional vectors or, when `x` or `data` is a data frame,
#'   unquoted column names. All selected vectors must have the same length.
#' @param data Optional data frame in which to evaluate `x` and `...`.
#' @param missing How missing values should be handled. `FALSE` and
#'   `"exclude"` omit them; `TRUE` and `"distinguish"` give observed Stata
#'   system missing (`.`), extended missing codes (`.a` through `.z`), and R
#'   `NaN` separate categories; `"combine"` creates one base-R missing
#'   category. A character `""` or `NA` is Stata's string missing under every
#'   mode: excluded by default, and one blank category otherwise.
#' @param display How labelled values should be named: by `"label"` (the
#'   default), underlying `"value"` (Stata's `nolabel`), or `"both"`. An
#'   absent label always falls back to the underlying value. Duplicate
#'   displayed labels are qualified by their values.
#' @param sort One-way tables only. `TRUE` orders the categories by
#'   descending frequency, ties in value order, as Stata's `sort` does.
#' @param percent Two-way tables only. Any of `"row"`, `"column"`, and
#'   `"cell"`: the percentages to show under each frequency, as Stata's
#'   `row`, `column`, and `cell` options do.
#' @param expected Two-way tables only. `TRUE` shows each cell's expected
#'   frequency under independence, as Stata's `expected` does.
#' @param freq `FALSE` omits the frequencies, as Stata's `nofreq` does. It
#'   needs `percent` or `expected`, since a table with nothing to show is an
#'   error here where Stata prints nothing.
#'
#' @details
#' Calls may supply vectors directly, select unquoted names from `data`, or
#' pipe a data frame into `tab()`. A data frame passed as `x` contributes all
#' of its columns when no names follow it. Thus `tab(df)` tabulates every
#' column, while `tab(x, y, data = df)` and `df |> tab(x, y)` are equivalent
#' ways to select `x` and `y`.
#'
#' Value labels affect only displayed dimension names. Categories remain
#' ordered by their underlying values. Unused value-label definitions do not
#' create zero-count categories. If displayed labels collide, their underlying
#' values are appended to keep every dimension name unambiguous.
#'
#' With `missing = TRUE` or `"distinguish"`, numeric categories are ordered
#' after observed values as system missing, extended missings `.a` through
#' `.z`, and then R `NaN`. A labelled missing code uses its value label unless
#' `display = "value"`; otherwise its Stata code is shown.
#' `missing = "combine"` follows base R by collapsing all missing numeric
#' payloads into one category.
#'
#' The result prints as Stata prints `tabulate`: a one-way table with
#' frequency, percent, and cumulative percent columns and a total row; a
#' two-way table with row and column totals, the requested percentages and
#' expected frequencies under each frequency, a key when more than one
#' statistic is shown, and panels when the table is wider than the console.
#' The header uses each variable's label, or its name without one. A table
#' with no observations prints `no observations`. The
#' [parity matrix](https://github.com/jbearak/dta-parser/blob/main/docs/r-tab-stata-parity.md)
#' lists every `tabulate` form and option and how far each is matched.
#'
#' Numeric factorization is shared with [factor_from_labels()] and does not
#' materialize compact numeric columns returned by [`read_dta()`][dtatools::read_dta].
#'
#' @return A `table` of frequencies with class `dta_tab`. [as.table()] drops
#'   the class for a plain `table`, [as.data.frame()] adds the percentages
#'   and expected frequencies as columns, and [format()] gives the printed
#'   lines. Subsetting, arithmetic, [t()], and [aperm()] return plain
#'   tables. [margin.table()] is not generic and restores the class itself;
#'   its result carries no layout and prints as a plain table, and
#'   `as.table(margin.table(x, 1))` is the exact plain table.
#' @export
#' @examples
#' x <- set_val_labels(
#'     c(1, 2, 1, NA_real_, tagged_missing(c("a", "b"))),
#'     Yes = 1, No = 2, Refused = tagged_missing("a")
#' )
#'
#' table(unclass(x), useNA = "ifany")
#' table(factor_from_labels(x), useNA = "ifany")
#' tab(x, missing = TRUE)
#' tab(x, missing = TRUE, display = "both")
#' tab(x, sort = TRUE)
#'
#' mtcars |>
#'     tab(cyl, gear, percent = "row")
tab <- function(x, ..., data = NULL, missing = FALSE,
                display = c("label", "value", "both"), sort = FALSE,
                percent = NULL, expected = FALSE, freq = TRUE) {
    caller <- rlang::caller_env()
    x_is_missing <- missing(x)
    x_quo <- if (x_is_missing) NULL else rlang::enquo(x)
    dots <- rlang::enquos(...)

    missing <- .normalize_tab_missing(missing)
    display <- match.arg(display)
    inputs <- .tab_inputs(x_quo, dots, data, caller)
    x <- data <- x_quo <- dots <- NULL
    options <- .tab_options(sort, percent, expected, freq, length(inputs$values))
    headers <- .tab_headers(inputs$values, inputs$names)
    widths <- vapply(inputs$values, .tab_string_width, integer(1))
    for (index in seq_along(inputs$values)) {
        inputs$values[[index]] <- .prepare_tab_argument(
            inputs$values[[index]],
            missing = missing,
            display = display
        )
    }
    names(inputs$values) <- inputs$names

    counts <- base::table(
        inputs$values,
        useNA = if (identical(missing, "exclude")) "no" else "ifany"
    )
    if (options$sort) counts <- .sort_tab(counts)
    .new_dta_tab(counts, headers, widths, options)
}

# Stata's `tabulate` options, checked against the number of variables the
# way Stata checks them: `sort` is a one-way option and `row`, `column`,
# `cell`, and `expected` are two-way options. `nofreq` with nothing else to
# show is an error rather than Stata's silent empty output.
.tab_options <- function(sort, percent, expected, freq, count) {
    for (flag in c("sort", "expected", "freq")) {
        value <- get(flag)
        if (!is.logical(value) || length(value) != 1L || is.na(value)) {
            stop(sprintf("`%s` must be `TRUE` or `FALSE`", flag), call. = FALSE)
        }
    }
    if (!is.null(percent)) {
        if (!is.character(percent) || anyNA(percent) || length(percent) == 0L) {
            stop("`percent` must name any of \"row\", \"column\", and \"cell\"",
                 call. = FALSE)
        }
        percent <- match.arg(percent, c("row", "column", "cell"), several.ok = TRUE)
    }
    if (sort && count != 1L) {
        stop("`sort` applies to one-way tabulations only", call. = FALSE)
    }
    if ((length(percent) || expected) && count != 2L) {
        stop("`percent` and `expected` apply to two-way tabulations only",
             call. = FALSE)
    }
    if (!freq && !length(percent) && !expected) {
        stop("`freq = FALSE` needs `percent` or `expected`; nothing would be shown",
             call. = FALSE)
    }
    list(sort = sort, percent = c("row", "column", "cell")[c("row", "column", "cell") %in% percent],
         expected = expected, freq = freq)
}

# The header text of each variable: its label, or its name without one, as
# Stata heads a `tabulate` column.
.tab_headers <- function(values, names) {
    labels <- vapply(values, function(value) {
        label <- attr(value, "label", exact = TRUE)
        if (is.character(label) && length(label) == 1L && !is.na(label) &&
            nzchar(label)) label else NA_character_
    }, character(1))
    ifelse(is.na(labels), names, labels)
}

# Stata sizes a string variable's stub from its storage width, `str18` for
# `make` in auto.dta, so a short subset prints in the width the file gave
# the variable. Plain character vectors have no width and size from their
# values.
.tab_string_width <- function(value) {
    storage <- attr(value, "stata.string.storage", exact = TRUE)
    if (is.character(storage) && length(storage) == 1L &&
        grepl("^str[0-9]+$", storage)) {
        return(as.integer(substring(storage, 4L)))
    }
    NA_integer_
}

# Stata's `sort`: descending frequency, and ties keep their value order, so
# the sort is stable over the already ordered categories.
.sort_tab <- function(counts) {
    ordering <- order(-as.integer(counts), seq_along(counts))
    # `drop = FALSE` keeps the one dimension of a table with a single
    # category, or none, which plain `[` would flatten to a bare vector.
    counts[ordering, drop = FALSE]
}

.new_dta_tab <- function(counts, headers, widths, options) {
    attr(counts, "dta_tab") <- list(
        headers = unname(headers), widths = unname(widths), options = options
    )
    class(counts) <- c("dta_tab", class(counts))
    counts
}

#' @export
as.table.dta_tab <- function(x, ...) {
    attr(x, "dta_tab") <- NULL
    class(x) <- "table"
    x
}

.normalize_tab_missing <- function(value) {
    if (is.logical(value)) {
        if (length(value) != 1L || is.na(value)) {
            stop("`missing` must be one non-missing logical or string",
                 call. = FALSE)
        }
        return(if (value) "distinguish" else "exclude")
    }
    if (!is.character(value) || length(value) != 1L || is.na(value)) {
        stop("`missing` must be one non-missing logical or string",
             call. = FALSE)
    }
    match.arg(value, c("exclude", "distinguish", "combine"))
}

.tab_inputs <- function(x, dots, data, caller) {
    if (!is.null(data)) {
        if (!is.data.frame(data)) {
            stop("`data` must be a data frame", call. = FALSE)
        }
        quosures <- c(if (is.null(x)) list() else list(x), dots)
        if (length(quosures) == 0L) {
            return(list(values = as.list(data), names = names(data)))
        }
        return(.eval_tab_quosures(quosures, data = data, caller = caller))
    }

    if (is.null(x)) {
        if (length(dots) == 0L) stop("nothing to tabulate", call. = FALSE)
        return(.eval_tab_quosures(dots, caller = caller))
    }

    first <- rlang::eval_tidy(x, env = caller)
    if (is.data.frame(first)) {
        if (length(dots) == 0L) {
            return(list(values = as.list(first), names = names(first)))
        }
        return(.eval_tab_quosures(dots, data = first, caller = caller))
    }
    if (is.list(first) && !is.object(first) && length(dots) == 0L) {
        input_names <- names(first)
        if (is.null(input_names)) {
            input_names <- paste0(
                .tab_quo_name(x), ".", seq_along(first)
            )
        }
        return(list(values = first, names = input_names))
    }

    rest <- if (length(dots) == 0L) {
        list(values = list(), names = character())
    } else {
        .eval_tab_quosures(dots, caller = caller)
    }
    list(
        values = c(list(first), rest$values),
        names = c(.tab_quo_name(x), rest$names)
    )
}

.eval_tab_quosures <- function(quosures, data = NULL, caller) {
    values <- if (is.null(data)) {
        lapply(quosures, rlang::eval_tidy, env = caller)
    } else {
        column_names <- vapply(quosures, function(value) {
            expression <- rlang::quo_get_expr(value)
            if (!rlang::is_symbol(expression)) {
                stop("data-frame tabulation requires column names", call. = FALSE)
            }
            rlang::as_name(expression)
        }, character(1))
        unknown <- !column_names %in% names(data)
        if (any(unknown)) {
            stop(
                "unknown column `", column_names[which(unknown)[[1L]]], "`",
                call. = FALSE
            )
        }
        duplicate_names <- names(data)[
            duplicated(names(data)) | duplicated(names(data), fromLast = TRUE)
        ]
        ambiguous <- column_names %in% duplicate_names
        if (any(ambiguous)) {
            stop(
                "column `", column_names[which(ambiguous)[[1L]]],
                "` is ambiguous because its name is duplicated",
                call. = FALSE
            )
        }
        lapply(column_names, function(name) data[[name]])
    }
    supplied_names <- names(quosures)
    if (is.null(supplied_names)) supplied_names <- rep("", length(quosures))
    inferred_names <- vapply(quosures, .tab_quo_name, character(1))
    use_supplied <- nzchar(supplied_names)
    inferred_names[use_supplied] <- supplied_names[use_supplied]
    list(values = values, names = inferred_names)
}

.tab_quo_name <- function(value) {
    expression <- rlang::quo_get_expr(value)
    if (rlang::is_symbol(expression)) rlang::as_name(expression) else ""
}

.prepare_tab_argument <- function(value, missing, display) {
    if (is.character(value) && !is.factor(value)) {
        return(.tab_character(value, missing))
    }
    labels <- attr(value, "labels", exact = TRUE)
    numeric_data <- typeof(value) %in% c("double", "integer") &&
        !is.factor(value)
    labelled <- numeric_data && .valid_tab_labels(labels)
    needs_missing <- !identical(missing, "exclude") && numeric_data

    if (!labelled && !needs_missing) return(value)

    restore_to <- if (is.object(value) &&
        !inherits(value, "haven_labelled")) value else NULL
    if (labelled) labels <- .tab_label_values(labels, value)
    .tab_factor(
        value,
        if (labelled) labels else NULL,
        missing,
        display,
        restore_to,
        drop_unused = TRUE
    )
}

# Stata's string missing is the empty string, and there is only one: `""`
# and R's `NA_character_` are the same category. Excluded by default, it is
# one blank category, sorted first, under `distinguish` and `combine`.
.tab_character <- function(value, missing) {
    text <- unclass(value)
    attributes(text) <- NULL
    blank <- is.na(text) | !nzchar(text)
    text[blank] <- if (identical(missing, "exclude")) NA_character_ else ""
    text
}

.valid_tab_labels <- function(labels) {
    !is.null(labels) &&
        typeof(labels) %in% c("double", "integer") &&
        length(labels) == length(names(labels))
}

.tab_label_values <- function(labels, value) {
    format <- attr(value, "format.stata", exact = TRUE)
    if (!is.character(format) || length(format) != 1L || is.na(format)) {
        return(labels)
    }
    observed <- !is.na(labels)
    if (inherits(value, "POSIXct") && grepl("^%t[cC]", format)) {
        labels[observed] <- labels[observed] / 1000 - 315619200
    } else if (inherits(value, "Date") && grepl("^%(td|d)", format)) {
        labels[observed] <- labels[observed] - 3653
    }
    labels
}

.tab_factor <- function(value, labels, missing, display, restore_to,
                        drop_unused) {
    seeds <- if (drop_unused) NULL else labels
    grouped <- .factorize_numeric(value, seeds, missing)
    factor_codes <- grouped$codes
    observed_values <- grouped$values
    observed_missing_codes <- grouped$missing_codes
    level_values <- if (is.null(restore_to)) {
        as.character(observed_values)
    } else {
        as.character(vctrs::vec_restore(observed_values, restore_to))
    }
    if (length(observed_missing_codes) > 0L) {
        level_values <- c(
            level_values,
            vapply(
                observed_missing_codes,
                .tab_missing_name,
                character(1)
            )
        )
    }

    label_names <- .tab_level_labels(
        labels,
        observed_values,
        observed_missing_codes
    )
    level_names <- switch(display,
        value = level_values,
        label = ifelse(is.na(label_names), level_values, label_names),
        both = ifelse(
            is.na(label_names),
            level_values,
            paste0("[", level_values, "] ", label_names)
        )
    )
    level_names <- as.character(level_names)
    level_names <- .disambiguate_tab_levels(level_names, level_values)

    structure(
        factor_codes,
        levels = level_names,
        class = "factor"
    )
}

.factorize_numeric <- function(value, seeds, missing) {
    missing_mode <- switch(missing,
        exclude = 0L,
        distinguish = 1L,
        combine = 2L
    )
    result <- .Call(C_dtatools_factorize_numeric, value, seeds, missing_mode)
    if (typeof(value) == "integer") {
        result$values <- as.integer(result$values)
    }
    result
}

.tab_level_labels <- function(labels, observed_values, missing_codes) {
    count <- length(observed_values) + length(missing_codes)
    result <- rep(NA_character_, count)
    if (is.null(labels) || length(labels) == 0L) return(result)

    label_names <- names(labels)
    usable <- !is.na(label_names) & nzchar(label_names)
    if (!any(usable)) return(result)
    labels <- labels[usable]
    label_names <- label_names[usable]
    label_missing_codes <- .tab_missing_codes(labels)

    if (length(observed_values) > 0L) {
        observed_labels <- is.na(label_missing_codes)
        if (any(observed_labels)) {
            matches <- match(observed_values, labels[observed_labels])
            found <- !is.na(matches)
            result[which(found)] <-
                label_names[observed_labels][matches[found]]
        }
    }

    if (length(missing_codes) > 0L) {
        missing_labels <- !is.na(label_missing_codes)
        if (any(missing_labels)) {
            matches <- match(missing_codes, label_missing_codes[missing_labels])
            found <- !is.na(matches)
            positions <- length(observed_values) + which(found)
            result[positions] <- label_names[missing_labels][matches[found]]
        }
    }
    result
}

.disambiguate_tab_levels <- function(names, values) {
    duplicated_names <- duplicated(names) | duplicated(names, fromLast = TRUE)
    names[duplicated_names] <- paste0(
        names[duplicated_names], " [", values[duplicated_names], "]"
    )
    make.unique(names, sep = " #")
}

.tab_missing_name <- function(code) .stata_missing_text(code)

# Stata's spelling of the missing codes `.tab_missing_codes()` reports: `.`
# for system missing, `.a` through `.z` for a tagged missing, `NaN` for
# R's own NaN, and `NA_character_` for an observed value. Every console
# surface that shows a missing value, the codebooks, `tab()`, `format()`,
# and the error messages, spells it through here (ADR 0040).
.stata_missing_text <- function(codes) {
    text <- rep(NA_character_, length(codes))
    known <- !is.na(codes)
    text[known & codes == 0L] <- "."
    text[known & codes == 256L] <- "NaN"
    tagged <- known & codes >= utf8ToInt("a") & codes <= utf8ToInt("z")
    text[tagged] <- paste0(".", intToUtf8(codes[tagged], multiple = TRUE))
    other <- known & is.na(text)
    text[other] <- paste0(".<tag ", codes[other], ">")
    text
}

.tab_missing_codes <- function(value) {
    .Call(C_dtatools_missing_codes, value)
}

# Printing. A `dta_tab` prints as Stata prints `tabulate`; the layout rules
# below were measured on Stata 19 output over auto.dta and are pinned by
# the tests in test-tab-stata-parity.R. Row levels sit in a stub whose
# width is the longest level, or the string variable's storage width, kept
# between 11 and 39 characters for a one-way table and between 10 and 21
# for a two-way table, plus one space before the bar. Two-way columns are
# ten characters wide with a single space between them, and column levels
# are cut to nine. Headers are variable labels, wrapped by word within the
# stub or centered over the columns, and bottom-aligned with the column
# levels. A two-way table wider than the console prints in panels.

#' @export
print.dta_tab <- function(x, ..., width = getOption("width", 80L)) {
    if (is.null(.dta_tab_info(x))) {
        print(as.table(x), ...)
    } else {
        cat(format(x, width = width), sep = "\n")
    }
    invisible(x)
}

#' @export
format.dta_tab <- function(x, ..., width = getOption("width", 80L)) {
    info <- .dta_tab_info(x)
    if (is.null(info)) return(utils::capture.output(print(as.table(x))))
    if (length(dim(x)) == 1L) {
        .format_one_way_tab(x, info)
    } else {
        .format_two_way_tab(x, info, width)
    }
}

# The presentation record, or `NULL` for a table this printer cannot
# describe: three or more variables, a result that arithmetic or a
# reshaping has turned into something other than integer counts, or one
# whose category names were removed.
.dta_tab_info <- function(x) {
    info <- attr(x, "dta_tab", exact = TRUE)
    extents <- dim(x)
    names <- dimnames(x)
    if (is.null(info) || !is.integer(x) || !length(extents) %in% 1:2 ||
        length(info$headers) != length(extents) ||
        length(names) != length(extents) ||
        !all(lengths(names) == extents)) {
        return(NULL)
    }
    info
}

#' @export
`[.dta_tab` <- function(x, ...) as.table(x)[...]

#' @export
Math.dta_tab <- function(x, ...) get(.Generic)(as.table(x), ...)

#' @export
t.dta_tab <- function(x) t(as.table(x))

#' @export
aperm.dta_tab <- function(a, perm = NULL, ...) aperm(as.table(a), perm, ...)

#' @export
Ops.dta_tab <- function(e1, e2) {
    if (inherits(e1, "dta_tab")) e1 <- as.table(e1)
    if (!missing(e2) && inherits(e2, "dta_tab")) e2 <- as.table(e2)
    if (missing(e2)) get(.Generic)(e1) else get(.Generic)(e1, e2)
}

#' @export
as.data.frame.dta_tab <- function(x, ...) {
    result <- as.data.frame(as.table(x), ...)
    if (is.null(.dta_tab_info(x))) return(result)
    counts <- as.integer(x)
    total <- sum(counts)
    if (length(dim(x)) == 1L) {
        percent <- 100 * counts / total
        statistics <- list(percent = percent, cum = cumsum(percent))
    } else {
        counts <- matrix(counts, nrow = dim(x)[[1L]])
        row_total <- rowSums(counts)
        column_total <- colSums(counts)
        statistics <- list(
            expected = as.vector(outer(row_total, column_total) / total),
            row_percent = as.vector(100 * counts / row_total),
            column_percent = as.vector(100 * sweep(counts, 2L, column_total, "/")),
            cell_percent = as.vector(100 * counts / total)
        )
    }
    # A variable named like a statistic keeps its column; the statistic
    # takes the next free name, as `make.unique()` spells it.
    names(statistics) <- utils::tail(
        make.unique(c(names(result), names(statistics))), length(statistics)
    )
    for (name in names(statistics)) result[[name]] <- statistics[[name]]
    result
}

.format_one_way_tab <- function(x, info) {
    counts <- as.integer(x)
    total <- sum(counts)
    if (total == 0L) return("no observations")
    levels <- .tab_level_text(dimnames(x)[[1L]])
    stub <- .tab_stub_width(levels, info$widths[[1L]], 11L, 39L)
    header <- .tab_wrap(info$headers[[1L]], stub - 1L)
    percent <- 100 * counts / total
    columns <- sprintf("%11s%12s%12s", "Freq.", "Percent", "Cum.")
    rule <- paste0(strrep("-", stub), "+", strrep("-", 35L))
    c(
        .tab_stub_lines(header, stub, c(rep("", length(header) - 1L), columns)),
        rule,
        .tab_stub_lines(
            levels, stub,
            paste0(
                .tab_pad(.tab_count_text(counts), 11L),
                .tab_pad(sprintf("%.2f", percent), 12L),
                .tab_pad(sprintf("%.2f", cumsum(percent)), 12L)
            )
        ),
        rule,
        .tab_stub_lines(
            "Total", stub,
            paste0(.tab_pad(.tab_count_text(total), 11L), .tab_pad("100.00", 12L))
        )
    )
}

.format_two_way_tab <- function(x, info, width) {
    counts <- matrix(as.integer(x), nrow = dim(x)[[1L]])
    total <- sum(counts)
    if (total == 0L) return("no observations")
    rows <- .tab_level_text(dimnames(x)[[1L]])
    columns <- .tab_cut(.tab_level_text(dimnames(x)[[2L]]), 9L)
    stub <- .tab_stub_width(rows, info$widths[[1L]], 10L, 21L)
    statistics <- .tab_two_way_statistics(counts, info$options)
    # A panel line is the stub, a bar, eleven columns per level, a bar, the
    # ten-wide total, and its trailing space: `stub + 11 * k + 13` columns.
    per_panel <- max(1L, (as.integer(width) - stub - 13L) %/% 11L)
    panels <- split(seq_len(ncol(counts)), (seq_len(ncol(counts)) - 1L) %/% per_panel)
    lines <- lapply(panels, function(selected) {
        .format_tab_panel(rows, columns, info$headers, stub, statistics, selected)
    })
    c(
        if (length(statistics) > 1L) c(.tab_key(names(statistics)), ""),
        unlist(Map(function(panel, index) {
            if (index > 1L) c("", "", panel) else panel
        }, lines, seq_along(lines)), use.names = FALSE)
    )
}

# Every statistic the options ask for, in Stata's order, each as a
# character matrix with the row totals as its last column and the column
# totals as its last row.
.tab_two_way_statistics <- function(counts, options) {
    row_total <- rowSums(counts)
    column_total <- colSums(counts)
    total <- sum(counts)
    with_margins <- function(cells, right, bottom, corner) {
        rbind(cbind(cells, right), c(bottom, corner))
    }
    percent <- function(values) .tab_decimal_text(values, 2L)
    statistics <- list()
    if (options$freq) {
        statistics$frequency <- .tab_count_text(
            with_margins(counts, row_total, column_total, total)
        )
    }
    if (options$expected) {
        statistics[["expected frequency"]] <- .tab_decimal_text(with_margins(
            outer(row_total, column_total) / total, row_total, column_total, total
        ), 1L)
    }
    if ("row" %in% options$percent) {
        statistics[["row percentage"]] <- percent(with_margins(
            100 * counts / row_total, 100 * row_total / row_total,
            100 * column_total / total, 100
        ))
    }
    if ("column" %in% options$percent) {
        statistics[["column percentage"]] <- percent(with_margins(
            100 * sweep(counts, 2L, column_total, "/"), 100 * row_total / total,
            100 * column_total / column_total, 100
        ))
    }
    if ("cell" %in% options$percent) {
        statistics[["cell percentage"]] <- percent(with_margins(
            100 * counts / total, 100 * row_total / total,
            100 * column_total / total, 100
        ))
    }
    lapply(statistics, function(cells) matrix(cells, nrow = nrow(counts) + 1L))
}

.format_tab_panel <- function(rows, columns, headers, stub, statistics, selected) {
    block <- 11L * length(selected)
    row_header <- .tab_wrap(headers[[1L]], stub - 1L)
    column_header <- .tab_wrap(headers[[2L]], block - 1L)
    column_header <- paste0(
        strrep(" ", pmax(0L, ceiling((block - .tab_width(column_header)) / 2))),
        column_header
    )
    cells <- function(values) paste0(paste(.tab_pad(values, 10L), collapse = " "), " ")
    levels_line <- paste0(cells(columns[selected]), "|", .tab_pad("Total", 10L))
    height <- max(length(row_header), length(column_header) + 1L)
    stub_text <- c(rep("", height - length(row_header)), row_header)
    right <- c(rep("", height - 1L - length(column_header)), column_header, levels_line)
    rule <- paste0(strrep("-", stub), "+", strrep("-", block), "+", strrep("-", 10L))
    total_column <- ncol(statistics[[1L]])
    body <- function(index, label) {
        .tab_stub_lines(
            c(label, rep("", length(statistics) - 1L)), stub,
            vapply(statistics, function(statistic) {
                paste0(cells(statistic[index, selected]), "|",
                       .tab_pad(statistic[index, total_column], 10L), " ")
            }, character(1))
        )
    }
    separated <- length(statistics) > 1L
    c(
        .tab_stub_lines(stub_text, stub, right),
        rule,
        unlist(lapply(seq_along(rows), function(index) {
            c(body(index, rows[[index]]), if (separated && index < length(rows)) rule)
        }), use.names = FALSE),
        rule,
        body(length(rows) + 1L, "Total")
    )
}

.tab_key <- function(items) {
    inner <- max(.tab_width(items)) + 2L
    border <- paste0("+", strrep("-", inner), "+")
    lead <- (inner - .tab_width(items)) %/% 2L
    c(
        border,
        paste0("| Key", strrep(" ", inner - 4L), "|"),
        paste0("|", strrep("-", inner), "|"),
        paste0("|", strrep(" ", lead), items,
               strrep(" ", inner - .tab_width(items) - lead), "|"),
        border
    )
}

# `text` right-justified in the stub and cut to it, a space, the bar, and
# whatever follows on that line.
.tab_stub_lines <- function(text, stub, rest) {
    paste0(.tab_pad(.tab_cut(text, stub - 1L), stub - 1L), " |", rest)
}

.tab_stub_width <- function(levels, storage_width, minimum, maximum) {
    widest <- max(minimum, .tab_width(levels),
                  if (!is.na(storage_width)) storage_width else 0L)
    min(widest, maximum) + 1L
}

# The fixed-width layout measures terminal columns, not characters, so a
# double-width label takes the room it occupies on screen. `formatC()` and
# `substr()` count characters and are not used here.
.tab_width <- function(text) nchar(text, type = "width", allowNA = FALSE)

.tab_pad <- function(text, width) {
    paste0(strrep(" ", pmax(0L, width - .tab_width(text))), text)
}

# The longest prefix of each string that fits in `width` columns.
.tab_cut <- function(text, width) {
    vapply(text, function(string) {
        if (is.na(string) || .tab_width(string) <= width) return(string)
        characters <- strsplit(string, "", fixed = TRUE)[[1L]]
        paste(characters[cumsum(.tab_width(characters)) <= width], collapse = "")
    }, character(1), USE.NAMES = FALSE)
}

.tab_level_text <- function(names) {
    names[is.na(names)] <- "."
    names
}

# A percentage or expected frequency; a value with nothing to divide by,
# the row of an unused factor level, is shown as Stata shows a missing.
.tab_decimal_text <- function(values, digits) {
    text <- sprintf(paste0("%.", digits, "f"), values)
    text[!is.finite(values)] <- "."
    text
}

.tab_count_text <- function(counts) {
    text <- formatC(counts, big.mark = ",", format = "d")
    if (is.matrix(counts)) dim(text) <- dim(counts)
    text
}

# Greedy word wrap at `width`; a word longer than the width is cut into
# pieces of that width first, as Stata cuts a long label.
.tab_wrap <- function(text, width) {
    words <- strsplit(text, " ", fixed = TRUE)[[1L]]
    words <- words[nzchar(words)]
    if (length(words) == 0L) return("")
    pieces <- unlist(lapply(words, function(word) {
        cuts <- character()
        while (.tab_width(word) > width) {
            piece <- .tab_cut(word, width)
            if (!nzchar(piece)) break # one character wider than the whole width
            cuts <- c(cuts, piece)
            word <- substring(word, nchar(piece) + 1L)
        }
        c(cuts, word)
    }), use.names = FALSE)
    lines <- character()
    current <- ""
    for (piece in pieces) {
        candidate <- if (nzchar(current)) paste(current, piece) else piece
        if (.tab_width(candidate) <= width) {
            current <- candidate
        } else {
            lines <- c(lines, current)
            current <- piece
        }
    }
    c(lines, current)
}
