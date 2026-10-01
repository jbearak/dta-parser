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
#'   prints nothing without other cell statistics. In summary tables it
#'   selects or suppresses the sum of weights (unweighted frequency).
#' @param where An expression selecting rows within each group. `.n` and `.N`
#'   are the within-group row number and row count. Missing selections are omitted.
#' @param rows Positive row positions, interpreted within each group.
#' @param by Optional unquoted grouping columns, such as `by = c(region, sex)`.
#'   A grouped data frame also produces one table per group.
#' @param weights Optional numeric weight expression. Zero and missing weights
#'   are omitted; negative, infinite, and noninteger frequency weights are errors.
#' @param weight Weight type: `"aweight"` (normalized to the sample size),
#'   `"fweight"` (integer replication counts), or `"iweight"` (raw weight sums).
#' @param subpop Numeric or logical expression. Zero excludes an observation
#'   from counts while retaining its categories. As in Stata, missing is nonzero.
#' @param row,column,cell Logical alternatives to `percent`.
#' @param nofreq,nolabel Stata spellings of `freq = FALSE` and `display = "value"`.
#' @param chi2,lrchi2 Two-way Pearson and likelihood-ratio independence tests.
#' @param exact Fisher's exact test, including the one-sided probability for
#'   two-by-two tables. A positive integer multiplies the exact-test workspace.
#' @param gamma,taub,V Goodman--Kruskal gamma, Kendall tau-b (with asymptotic
#'   standard errors), and Cramer's V. V is signed for two-by-two tables.
#' @param all Request all association measures except Fisher's exact test.
#'   Explicit `chi2 = FALSE`, `lrchi2 = FALSE`, `gamma = FALSE`, `taub = FALSE`,
#'   or `V = FALSE` suppresses that measure even with `all = TRUE`.
#' @param cchi2,clrchi2 Show each cell's Pearson or likelihood-ratio contribution.
#' @param rowsort,colsort Sort two-way rows or columns by descending frequency.
#' @param key Force or suppress the two-way cell key; `NULL` chooses automatically.
#' @param nokey Suppress the key, as with `key = FALSE`.
#' @param wrap Keep a wide frequency table in one panel, as Stata's `wrap` does.
#' @param plot Print a one-way horizontal bar chart using stars.
#' @param nolog Accepted for Stata syntax compatibility. R's exact-test engine
#'   does not print Stata's enumeration progress log.
#' @param generate Optional prefix for indicator columns, returned in the
#'   result's `generated` data-frame attribute in original observation order.
#'   Excluded observations are missing. Source data are not modified.
#' @param matcell,matrow,matcol Save frequency or underlying numeric category
#'   matrices in `attr(result, "r")`. String category matrices are not allowed.
#' @param collect `TRUE` or a collection name attaches a `collection` list
#'   containing the tidy table and stored results. It is an R value, with no
#'   global Stata collection state or Stata style-file interpreter.
#' @param summarize Optional numeric response expression for a one-way or
#'   two-way table of means, standard deviations, frequencies, and observations.
#'   Missing responses are excluded. Only analytic and frequency weights apply.
#' @param means,standard,obs Summary-table switches. `NULL` uses Stata's defaults;
#'   `TRUE` selects a statistic and `FALSE` suppresses it. An affirmative `means`,
#'   `standard`, or `freq` narrows the default display; `obs` adds observations.
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
#' values are appended to keep every dimension name unambiguous. Printed labels
#' remain unchanged, as in Stata.
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
#'   `as.table(margin.table(x, 1))` is the exact plain table. `attr(result, "r")`
#'   holds Stata's stored counts and requested tests and matrices. Grouped calls
#'   return a `dta_tab_grouped` list. Summary calls return a `dta_tab_summary`
#'   data frame whose presentation attribute contains cell and marginal moments.
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
#' tabulate(mtcars, cyl, gear, all = TRUE)
#' tab(mtcars, cyl, summarize = mpg)
#' tab(mtcars, cyl, by = am, where = .n <= 10)
tab <- function(x, ..., data = NULL, missing = FALSE,
                display = c("label", "value", "both"), sort = FALSE,
                percent = NULL, expected = FALSE, freq = TRUE,
                where = NULL, rows = NULL, by = NULL, weights = NULL,
                weight = c("aweight", "fweight", "iweight"), subpop = NULL,
                row = FALSE, column = FALSE, cell = FALSE, nofreq = FALSE,
                nolabel = FALSE, chi2 = FALSE, lrchi2 = FALSE, exact = FALSE,
                gamma = FALSE, taub = FALSE, V = FALSE, all = FALSE,
                cchi2 = FALSE, clrchi2 = FALSE, rowsort = FALSE, colsort = FALSE,
                key = NULL, nokey = FALSE, wrap = FALSE, plot = FALSE,
                nolog = FALSE, generate = NULL, matcell = FALSE,
                matrow = FALSE, matcol = FALSE, collect = FALSE,
                summarize = NULL, means = NULL, standard = NULL, obs = NULL) {
    caller <- rlang::caller_env()
    x_quo <- if (missing(x)) NULL else rlang::enquo(x)
    dots <- rlang::enquos(...)
    # Retain the pre-existing named-vector call tab(row = vector, ...).
    if (is.null(x_quo) && !(is.logical(row) && length(row) == 1L)) {
        dots <- c(list(row = rlang::enquo(row)), dots)
        row <- FALSE
    }
    summary_quo <- rlang::enquo(summarize)
    summary <- !rlang::quo_is_null(summary_quo)
    flags <- list(sort = sort, expected = expected, freq = freq, row = row,
        column = column, cell = cell, nofreq = nofreq, nolabel = nolabel,
        chi2 = chi2, lrchi2 = lrchi2, gamma = gamma, taub = taub, V = V,
        all = all, cchi2 = cchi2, clrchi2 = clrchi2, rowsort = rowsort,
        colsort = colsort, nokey = nokey, wrap = wrap, plot = plot, nolog = nolog,
        matcell = matcell, matrow = matrow, matcol = matcol)
    for (name in names(flags)) .dta_group_flag(flags[[name]], name)
    for (name in c("key", "means", "standard", "obs"))
        if (!is.null(get(name))) .dta_group_flag(get(name), name)
    if (!(is.logical(exact) && length(exact) == 1L && !is.na(exact)) &&
        !(is.numeric(exact) && length(exact) == 1L && is.finite(exact) &&
          exact >= 1 && exact == floor(exact)))
        stop("`exact` must be TRUE, FALSE, or a positive integer", call. = FALSE)
    for (name in c("chi2", "lrchi2", "gamma", "taub", "V")) {
        # An explicitly disabled test overrides `all`, like Stata's no-options.
        flags[[paste0("no", name)]] <- all && !get(name) &&
            !eval(call("missing", as.name(name)))
    }
    flags$exact <- exact
    flags$key <- key
    missing <- .normalize_tab_missing(missing)
    display <- if (nolabel) "value" else match.arg(display)
    weight <- match.arg(weight)
    inputs <- .tab_inputs(x_quo, dots, data, caller)
    if (!length(inputs$values)) stop("nothing to tabulate", call. = FALSE)
    if (length(unique(lengths(inputs$values))) != 1L)
        stop("tabulation vectors must have the same length", call. = FALSE)
    for (value in inputs$values)
        if (!is.atomic(value) || !is.null(dim(value)))
            stop("tabulation inputs must be vectors", call. = FALSE)
    count <- length(inputs$values)
    options <- .tab_options(flags, percent, count, summary)
    if (!is.null(generate) && (!is.character(generate) || length(generate) != 1L ||
        is.na(generate) || !grepl("^[A-Za-z_][A-Za-z0-9_]*$", generate)))
        stop("`generate` must be an indicator variable name prefix", call. = FALSE)
    if (!is.null(generate) && (count != 1L || summary))
        stop("`generate` applies to one-way frequency tables only", call. = FALSE)
    subpop_quo <- rlang::enquo(subpop)
    if (!rlang::quo_is_null(subpop_quo) && (count > 2L || summary))
        stop("`subpop` applies to one-way and two-way frequency tables only", call. = FALSE)
    if (!summary && (!is.null(means) || !is.null(standard) || !is.null(obs)))
        stop("`means`, `standard`, and `obs` require `summarize`", call. = FALSE)
    options$subpop <- !rlang::quo_is_null(subpop_quo)
    options$means <- means
    options$standard <- standard
    options$obs <- obs
    options$summary_freq <- if (missing(freq) && !nofreq) NULL else options$freq
    .tab_run(inputs, options, missing, display, rlang::enquo(where), rows,
        rlang::enquo(by), rlang::enquo(weights), weight, subpop_quo,
        summary_quo, generate, collect, caller)
}

#' @rdname tab
#' @export
tabulate <- tab

.tab_options <- function(flags, percent, count, summary = FALSE) {
    if (!is.null(percent)) {
        if (!is.character(percent) || anyNA(percent) || length(percent) == 0L)
            stop("`percent` must name any of \"row\", \"column\", and \"cell\"",
                 call. = FALSE)
        percent <- match.arg(percent, c("row", "column", "cell"), several.ok = TRUE)
    }
    flags$percent <- c("row", "column", "cell")[
        c("row", "column", "cell") %in% percent |
            c(flags$row, flags$column, flags$cell)]
    flags$freq <- flags$freq && !flags$nofreq
    if ((flags$sort || flags$plot) && count != 1L)
        stop("`sort` and `plot` apply to one-way tabulations only", call. = FALSE)
    two_way <- c("expected", "chi2", "lrchi2", "gamma", "taub", "V", "all",
                 "cchi2", "clrchi2", "rowsort", "colsort", "wrap", "nokey", "nolog",
                 "matcol")
    if ((any(unlist(flags[two_way])) || length(flags$percent) ||
         !identical(flags$exact, FALSE) || !is.null(flags$key)) && count != 2L &&
        !(summary && flags$wrap && !any(unlist(flags[setdiff(two_way, "wrap")]))))
        stop("two-way options apply to two-way tabulations only", call. = FALSE)
    if (summary && (any(unlist(flags[setdiff(two_way, "wrap")])) ||
        length(flags$percent) || flags$sort || flags$plot || flags$matcell ||
        flags$matrow || !identical(flags$exact, FALSE) || !is.null(flags$key)))
        stop("frequency-table options may not be combined with `summarize`", call. = FALSE)
    if (summary && !count %in% 1:2)
        stop("summary tabulation needs one or two grouping variables", call. = FALSE)
    flags
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
    ordering <- order(-as.double(counts), seq_along(counts))
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
    for (name in c("dta_tab", "r", "generated", "collection", "data")) attr(x, name) <- NULL
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
            return(list(values = as.list(data), names = names(data), data = data))
        }
        result <- .eval_tab_quosures(quosures, data = data, caller = caller)
        result$data <- data
        return(result)
    }

    if (is.null(x)) {
        if (length(dots) == 0L) stop("nothing to tabulate", call. = FALSE)
        return(.eval_tab_quosures(dots, caller = caller))
    }

    first <- rlang::eval_tidy(x, env = caller)
    if (is.data.frame(first)) {
        if (length(dots) == 0L) {
            return(list(values = as.list(first), names = names(first), data = first))
        }
        result <- .eval_tab_quosures(dots, data = first, caller = caller)
        result$data <- first
        return(result)
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

.tab_level_labels <- function(labels, observed_values, missing_codes, allow_empty = FALSE) {
    count <- length(observed_values) + length(missing_codes)
    result <- rep(NA_character_, count)
    if (is.null(labels) || length(labels) == 0L) return(result)

    label_names <- names(labels)
    usable <- !is.na(label_names) & (allow_empty | nzchar(label_names))
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
