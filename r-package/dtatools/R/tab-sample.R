# Selection is shared by frequencies, summary tables, and by-group calls.
# Categories are formed only after the joint calculation sample is known.
.tab_run <- function(inputs, options, missing, display, where, rows, by,
                     weights, weight, subpop, summary, generate, collect, caller) {
    n <- length(inputs$values[[1L]])
    columns <- if (is.null(inputs$data)) {
        stats::setNames(inputs$values, make.unique(ifelse(nzchar(inputs$names),
            inputs$names, paste0("v", seq_along(inputs$values)))))
    } else as.list(inputs$data)
    data <- if (is.null(inputs$data)) vctrs::new_data_frame(columns, n = n) else inputs$data
    if (inherits(data, "rowwise_df")) stop("`tab()` does not accept rowwise data", call. = FALSE)
    group_columns <- columns
    grouped <- !rlang::quo_is_null(by) || inherits(data, "grouped_df")
    group_names <- if (!rlang::quo_is_null(by)) .mutation_group_names(by, columns, "by") else character()
    for (name in group_names) {
        key <- group_columns[[name]]
        if (typeof(key) == "double" && any(is_tagged_missing(key)))
            group_columns[[name]] <- dta_double(as.double(unclass(key)))
        if (is.character(key) && anyNA(key)) {
            key <- as.character(key)
            key[is.na(key)] <- ""
            group_columns[[name]] <- key
        }
    }
    if (grouped && !is.null(generate))
        stop("`generate` may not be combined with `by`", call. = FALSE)
    groups <- .assignment_groups(data, list(columns = group_columns, nrow = n),
        by, NULL, inherits(data, "grouped_df"))
    if (!is.null(groups) && !inherits(data, "grouped_df")) {
        first <- vapply(groups$rows, `[[`, integer(1), 1L)
        groups$keys <- vctrs::new_data_frame(lapply(columns[names(groups$keys)],
            function(key) {
                key <- .tab_slice(key, first)
                if (is.character(key)) key[is.na(key)] <- ""
                key
            }), n = length(first))
    }
    group_rows <- if (grouped && n == 0L) list() else if (is.null(groups))
        list(seq_len(n)) else groups$rows
    positions <- .egen_positions(rows)
    weighted <- !rlang::quo_is_null(weights)
    has_summary <- !rlang::quo_is_null(summary)
    if (has_summary && weighted && weight == "iweight")
        stop("iweights are not allowed with `summarize`", call. = FALSE)
    options$weight <- if (weighted) weight else NULL
    if (has_summary) options$missing <- missing
    if (!(is.logical(collect) && length(collect) == 1L && !is.na(collect)) &&
        !(is.character(collect) && length(collect) == 1L && !is.na(collect) && nzchar(collect)))
        stop("`collect` must be TRUE, FALSE, or a collection name", call. = FALSE)
    result <- vector("list", length(group_rows))
    for (g in seq_along(group_rows)) {
        full <- group_rows[[g]]
        size <- length(full)
        view <- lapply(columns, function(z) .tab_slice(z, full))
        extras <- list(.n = seq_len(size), .N = size)
        keep <- .mutation_rows(.eval_mutation_expression(where, view, "where", extras), size)
        if (is.null(keep)) keep <- seq_len(size)
        if (!is.null(positions)) {
            if (any(positions > size)) stop("`rows` exceeds the group row count", call. = FALSE)
            keep <- intersect(keep, positions)
        }
        selected <- full[sort(unique(keep))]
        w <- if (weighted) .tab_eval_vector(weights, view, extras, size, "weights") else rep(1, size)
        if (weighted) {
            w <- .summarize_numeric(w)
        }
        population <- if (rlang::quo_is_null(subpop)) rep(TRUE, size) else {
            s <- .tab_eval_vector(subpop, view, extras, size, "subpop")
            if (!is.numeric(s) && !is.logical(s))
                stop("`subpop` must be numeric or logical", call. = FALSE)
            # Stata's subpop excludes exactly zero, including missing as nonzero.
            is.na(s) | s != 0
        }
        response <- if (has_summary)
            .tab_eval_vector(summary, view, extras, size, "summarize") else NULL
        local <- match(selected, full)
        values <- lapply(inputs$values, function(z) .tab_slice(z, selected))
        names(values) <- inputs$names
        result[[g]] <- .tab_compute(values, w[local], if (weighted) weight else NULL,
            population[local], options, missing, display, selected, n, generate,
            if (has_summary) .tab_slice(response, local) else NULL,
            if (has_summary) rlang::as_label(summary) else NULL)
        if (!identical(collect, FALSE)) {
            attr(result[[g]], "collection") <- list(
                name = if (isTRUE(collect)) "Tabulate" else collect,
                table = as.data.frame(result[[g]]), r = attr(result[[g]], "r"))
        }
    }
    if (!grouped) return(result[[1L]])
    attr(result, "groups") <- if (is.null(groups)) data.frame() else groups$keys
    attr(result, "r") <- if (length(result)) attr(result[[length(result)]], "r") else list()
    class(result) <- c("dta_tab_grouped", "list")
    result
}

.tab_eval_vector <- function(quo, columns, extras, size, name) {
    value <- .eval_mutation_expression(quo, columns, name, extras)
    if (!is.atomic(value) || !is.null(dim(value)) || !length(value) %in% c(1L, size))
        stop(sprintf("`%s` must have length one or the group row count", name), call. = FALSE)
    if (length(value) == 1L && size != 1L) value <- rep(value, size)
    value
}

.tab_compute <- function(values, weights, weight, population, options, missing,
                         display, selected, n, generate, response, summary_name) {
    headers <- .tab_headers(values, names(values))
    widths <- vapply(values, .tab_string_width, integer(1))
    valid <- !is.na(weights) & weights != 0
    if (identical(missing, "exclude")) for (value in values) {
        valid <- valid & !is.na(value)
        if (is.character(value)) valid <- valid & nzchar(value)
    }
    if (!is.null(summary_name)) {
        valid <- valid & !is.na(.summarize_numeric(response))
    }
    if (!is.null(weight)) {
        if (any(!is.finite(weights[valid]) | weights[valid] < 0))
            stop("weights must be finite and nonnegative", call. = FALSE)
        .summarize_weights(weights[valid], weight)
    }
    values <- lapply(values, function(z) .tab_slice(z, which(valid)))
    weights <- weights[valid]
    population <- population[valid]
    selected <- selected[valid]
    factors <- lapply(values, function(z) .tab_categories(z, missing, display))
    if (!is.null(summary_name)) {
        summary_options <- options
        summary_options$freq <- options$summary_freq
        summary_options$display_levels <- Map(function(value, f)
            .tab_category_text(value, f, display, missing), values, factors)
        for (i in seq_along(values)) if (is.character(values[[i]]) && is.na(widths[i]))
            widths[i] <- max(c(0L, nchar(values[[i]], type = "width")), na.rm = TRUE)
        return(.tab_summary(.tab_slice(response, which(valid)), factors, weights, weight,
            summary_options, headers, summary_name, widths))
    }
    dimensions <- lengths(lapply(factors, levels))
    level_names <- lapply(factors, levels)
    raw_levels <- Map(function(value, f) {
        if (is.factor(value)) return(levels(value))
        out <- value[match(seq_len(nlevels(f)), as.integer(f))]
        if (inherits(out, c("Date", "POSIXct"))) return(.summarize_numeric(out))
        if (is.numeric(out)) return(as.double(unclass(out)))
        as.character(out)
    }, values, factors)
    if (identical(weight, "aweight") && any(population)) {
        # Only the subpopulation contributes to the normalization denominator.
        weights <- weights / .summarize_sum(weights[population]) * sum(population)
    }
    weights[!population] <- 0
    if (is.null(weight)) {
        counts <- base::table(lapply(factors, function(z) z[population]), useNA = "no")
    } else {
        counts <- array(0, dim = dimensions, dimnames = level_names)
        if (length(weights) && length(counts)) {
            stride <- c(1, utils::head(cumprod(dimensions), -1L))
            index <- 1 + Reduce(`+`, Map(function(z, s) (as.integer(z) - 1) * s, factors, stride))
            sums <- rowsum(weights, index, reorder = FALSE)
            counts[as.integer(rownames(sums))] <- sums[, 1L]
        }
        class(counts) <- "table"
    }
    ordering <- lapply(dimensions, seq_len)
    if (options$sort) ordering[[1L]] <- order(-as.double(counts), ordering[[1L]])
    if (options$rowsort) ordering[[1L]] <- order(-rowSums(counts), ordering[[1L]])
    if (options$colsort) ordering[[2L]] <- order(-colSums(counts), ordering[[2L]])
    counts <- do.call(`[`, c(list(counts), ordering, list(drop = FALSE)))
    class(counts) <- "table"
    raw_levels <- Map(`[`, raw_levels, ordering)
    if (options$matrow && is.character(raw_levels[[1L]]))
        stop("`matrow` is not allowed with a string row variable", call. = FALSE)
    if (options$matcol && is.character(raw_levels[[2L]]))
        stop("`matcol` is not allowed with a string column variable", call. = FALSE)
    tests <- if (length(dimensions) == 2L) .tab_association(counts, options, weight) else list()
    result <- .new_dta_tab(counts, headers, widths, options)
    info <- attr(result, "dta_tab")
    info$tests <- tests
    info$levels <- Map(function(value, f, order)
        .tab_category_text(value, f, display, missing)[order], values, factors, ordering)
    attr(result, "dta_tab") <- info
    r <- c(list(N = sum(counts), r = unname(dimensions[1L])),
        if (length(dimensions) == 2L) list(c = unname(dimensions[2L])))
    statistics <- setdiff(names(tests), c("N", "r", "c"))
    r[statistics] <- tests[statistics]
    if (options$matcell) r$matcell <- if (length(dimensions) == 1L)
        matrix(as.double(counts), ncol = 1L) else
            matrix(as.double(counts), nrow = dimensions[1L])
    if (options$matrow) r$matrow <- matrix(raw_levels[[1L]], ncol = 1L)
    if (options$matcol) r$matcol <- matrix(raw_levels[[2L]], nrow = 1L)
    attr(result, "r") <- r
    if (!is.null(generate)) {
        if (any(nchar(paste0(generate, seq_len(dimensions[1L]))) > 32L))
            stop("generated variable names must fit in 32 characters", call. = FALSE)
        indicators <- lapply(ordering[[1L]], function(level) {
            value <- rep(NA_integer_, n)
            value[selected] <- as.integer(factors[[1L]]) == level
            dta_byte(value)
        })
        names(indicators) <- if (length(indicators)) paste0(generate, seq_along(indicators)) else character()
        label_text <- .tab_category_labels(values[[1L]], factors[[1L]], missing)[ordering[[1L]]]
        for (j in seq_along(indicators)) attr(indicators[[j]], "label") <-
            .tab_indicator_label(raw_levels[[1L]][j], names(values)[1L],
                if (display != "value" && !is.na(label_text[j])) label_text[j] else NULL)
        attr(result, "generated") <- vctrs::new_data_frame(indicators, n = n)
    }
    result
}

.tab_categories <- function(value, missing, display) {
    result <- .prepare_tab_argument(value, missing, display)
    if (!is.factor(result)) result <- factor(result)
    if (missing != "exclude" && anyNA(result)) result <- addNA(result, ifany = TRUE)
    result
}

#' @export
print.dta_tab_grouped <- function(x, ...) {
    lines <- format(x, ...)
    if (length(lines)) cat(lines, sep = "\n")
    invisible(x)
}

#' @export
format.dta_tab_grouped <- function(x, ..., width = getOption("width", 80L)) {
    keys <- attr(x, "groups", exact = TRUE)
    unlist(lapply(seq_along(x), function(i) c(
        if (i > 1L) "", strrep("-", width),
        paste0("-> ", .mutation_group_label(keys, i)), "", format(x[[i]], ..., width = width))),
        use.names = FALSE)
}

# Base subsetting drops descriptive attributes on plain R vectors. These
# are variable metadata, so retain them on the selected calculation sample.
.tab_slice <- function(value, rows) {
    if (identical(rows, seq_along(value))) return(value)
    result <- value[rows]
    for (name in c("label", "labels", "format.stata", "stata.string.storage"))
        attr(result, name) <- attr(value, name, exact = TRUE)
    result
}

.tab_category_text <- function(value, category, display, missing) {
    text <- levels(category)
    if ((!is.numeric(value) && !inherits(value, c("Date", "POSIXct"))) ||
        is.factor(value)) return(text)
    first <- match(seq_len(nlevels(category)), as.integer(category))
    raw <- value[first]
    observed <- !is.na(raw)
    fmt <- attr(value, "format.stata", exact = TRUE)
    if (!is.null(fmt) || !inherits(value, c("Date", "POSIXct"))) {
        if (is.null(fmt)) fmt <- "%9.0g"
        fmt <- sub("^%(-?[0-9]*)?d", "%\\1td", fmt)
        text[observed] <- .summarize_number(.summarize_numeric(raw)[observed], fmt)
        long <- observed & nchar(text, type = "width") > 9L
        text[long] <- paste0(.tab_cut(text[long], 7L), "..")
    }
    if (display != "value") {
        label_text <- .tab_category_labels(value, category, missing)
        have_label <- !is.na(label_text)
        text[have_label] <- if (display == "label") label_text[have_label] else
            paste0("[", text[have_label], "] ", label_text[have_label])
    }
    text
}

.tab_category_labels <- function(value, category, missing) {
    result <- rep(NA_character_, nlevels(category))
    labels <- attr(value, "labels", exact = TRUE)
    if (!.valid_tab_labels(labels) || is.factor(value)) return(result)
    raw <- value[match(seq_len(nlevels(category)), as.integer(category))]
    observed <- !is.na(raw)
    labels <- .tab_label_values(labels, value)
    result[observed] <- .tab_level_labels(labels, as.double(unclass(raw))[observed],
        integer(), allow_empty = TRUE)
    if (missing != "combine") result[!observed] <- .tab_level_labels(labels,
        numeric(), .tab_missing_codes(raw[!observed]), allow_empty = TRUE)
    result
}
