# Stata's tabulate, summarize() is a distinct command: the sample excludes
# missing outcomes, frequencies are unnormalised weight sums, and singleton
# cells have zero standard deviation (unlike summarize itself).
.tab_summary <- function(values, category_factors, weights = NULL,
                         weight_type = NULL, options = list(), headers,
                         summary_name, widths = rep(NA_integer_, length(category_factors))) {
    if (!length(category_factors) %in% 1:2)
        stop("`summarize` requires one or two tabulated variables", call. = FALSE)
    if (!is.null(weight_type) && !weight_type %in% c("aweight", "fweight"))
        stop("`summarize` allows only aweights and fweights", call. = FALSE)
    summary_header <- .tab_headers(list(values), summary_name)
    values <- .summarize_numeric(values)
    n <- length(values)
    if (any(lengths(category_factors) != n))
        stop("`summarize` must have the same length as the tabulated variables", call. = FALSE)
    if (any(is.infinite(values)))
        stop("summary inputs must be finite or missing", call. = FALSE)
    weighted <- !is.null(weight_type)
    statistics <- .tab_summary_options(options, weighted)
    if (!weighted) weights <- rep(1, n)
    else {
        weights <- .summarize_numeric(weights)
        if (length(weights) == 1L) weights <- rep(weights, n)
        if (length(weights) != n)
            stop("`weights` must have length one or the row count", call. = FALSE)
        .summarize_weights(weights, weight_type)
    }
    strings <- vapply(category_factors, is.character, logical(1)) | !is.na(widths)
    categories <- lapply(category_factors, function(value) {
        if (is.factor(value)) value else factor(value,
            exclude = if (identical(options$missing, "combine")) NULL else NA)
    })
    original_levels <- lapply(categories, levels)
    keep <- !is.na(values) & !is.na(weights) & weights > 0
    for (category in categories) keep <- keep & !is.na(as.integer(category))
    values <- values[keep]
    weights <- weights[keep]
    categories <- lapply(categories, function(value) droplevels(value[keep], exclude = NULL))
    levels <- lapply(categories, levels)
    display_levels <- if (is.null(options$display_levels)) levels else
        Map(function(current, original, display) display[match(current, original)],
            levels, original_levels, options$display_levels)
    extents <- lengths(levels)
    category_names <- names(category_factors)
    if (is.null(category_names)) category_names <- paste0("Var", seq_along(categories))
    names(levels) <- category_names
    indices <- lapply(categories, as.integer)
    fit <- function(rows) {
        result <- .summarize_statistics(values[rows], weights[rows],
            if (weighted) weight_type else NULL, FALSE, FALSE)$statistics
        c(mean = unname(result[["mean"]]),
          sd = if (length(rows) == 1L) 0 else unname(result[["sd"]]),
          freq = unname(result[["sum_w"]]), obs = unname(result[["N"]]))
    }
    # The final index in each dimension is its marginal total. Compute the
    # moments from the underlying observations, not averages of cell means.
    dimensions <- extents + 1L
    grid <- do.call(expand.grid, c(lapply(dimensions, seq_len),
        KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE))
    moments <- matrix(NA_real_, nrow(grid), 4L,
        dimnames = list(NULL, c("mean", "sd", "freq", "obs")))
    positions <- seq_along(values)
    grouped <- lapply(indices, function(index) split(positions, index))
    cells <- if (length(indices) == 2L)
        split(positions, indices[[1L]] + (indices[[2L]] - 1L) * dimensions[1L])
    for (i in seq_len(nrow(grid))) {
        active <- which(as.integer(grid[i, ]) <= extents)
        selected <- if (!length(active)) positions else if (length(active) == 1L)
            grouped[[active]][[as.character(grid[i, active])]] else
            cells[[as.character(grid[i, 1L] + (grid[i, 2L] - 1L) * dimensions[1L])]]
        moments[i, ] <- fit(selected)
    }
    margins <- lapply(seq_len(ncol(moments)), function(j) {
        array(moments[, j], dim = dimensions,
            dimnames = lapply(levels, c, "Total"))
    })
    names(margins) <- colnames(moments)
    interior <- rep(TRUE, nrow(grid))
    for (j in seq_along(indices)) interior <- interior & grid[, j] <= extents[j]
    result <- do.call(expand.grid, c(levels, KEEP.OUT.ATTRS = FALSE,
        stringsAsFactors = FALSE))
    # Match tab()'s data-frame convention without losing a grouping variable
    # that happens to be named "mean", "sd", "freq", or "obs".
    stat_names <- utils::tail(make.unique(c(names(result), colnames(moments))), 4L)
    for (j in seq_along(stat_names)) result[[stat_names[j]]] <- moments[interior, j]
    attr(result, "dta_tab_summary") <- list(
        levels = levels, display_levels = display_levels,
        headers = unname(headers), widths = widths,
        strings = strings, summary_name = summary_name,
        summary_header = unname(summary_header), statistics = statistics,
        stat_names = stats::setNames(stat_names, colnames(moments)),
        margins = margins, weight = if (weighted) weight_type else NULL,
        options = options, N = length(values))
    attr(result, "r") <- list()
    class(result) <- c("dta_tab_summary", "data.frame")
    result
}

.tab_summary_options <- function(options, weighted) {
    fields <- c("means", "standard", "freq", "obs")
    for (field in fields) {
        value <- options[[field]]
        if (!is.null(value) && (!is.logical(value) || length(value) != 1L || is.na(value)))
            stop(sprintf("`%s` must be `TRUE`, `FALSE`, or `NULL`", field), call. = FALSE)
    }
    # obs adds to the default statistics; only means/standard/freq narrow
    # the displayed statistics when explicitly requested in positive form.
    narrow <- any(vapply(options[intersect(names(options), fields[1:3])], isTRUE, logical(1)))
    show <- stats::setNames(c(rep(!narrow, 3L), weighted), fields)
    for (field in fields) if (!is.null(options[[field]])) show[[field]] <- options[[field]]
    c("mean", "sd", "freq", "obs")[show]
}

#' @export
as.data.frame.dta_tab_summary <- function(x, row.names = NULL, optional = FALSE, ...) {
    class(x) <- "data.frame"
    attr(x, "dta_tab_summary") <- NULL
    attr(x, "r") <- NULL
    attr(x, "collection") <- NULL
    if (!is.null(row.names)) row.names(x) <- row.names
    x
}

#' @export
`[.dta_tab_summary` <- function(x, ...) as.data.frame(x)[...]

# Edits invalidate both the marginal moments and the selected display
# statistics. Drop that presentation record before modifying the cells.
#' @export
`[<-.dta_tab_summary` <- function(x, ..., value) {
    x <- as.data.frame(x)
    x[...] <- value
    x
}

#' @export
`[[<-.dta_tab_summary` <- function(x, ..., value) {
    x <- as.data.frame(x)
    x[[...]] <- value
    x
}

#' @export
`$<-.dta_tab_summary` <- function(x, name, value) {
    x <- as.data.frame(x)
    x[[name]] <- value
    x
}

#' @export
rbind.dta_tab_summary <- function(..., deparse.level = 1) {
    values <- lapply(list(...), function(value) {
        if (inherits(value, "dta_tab_summary")) as.data.frame(value) else value
    })
    do.call(base::rbind.data.frame, c(values, list(deparse.level = deparse.level)))
}

# Registered only while the optional dplyr namespace is loaded. Row slicing
# and binding reconstruct their result from the original table's attributes.
dplyr_reconstruct.dta_tab_summary <- function(data, template) {
    as.data.frame.dta_tab_summary(data)
}

#' @export
print.dta_tab_summary <- function(x, ..., width = getOption("width", 80L)) {
    lines <- format(x, ..., width = width)
    if (length(lines)) cat(lines, sep = "\n")
    invisible(x)
}

#' @export
format.dta_tab_summary <- function(x, ..., width = getOption("width", 80L)) {
    info <- attr(x, "dta_tab_summary", exact = TRUE)
    if (!info$N) return("no observations")
    if (!length(info$statistics)) return(character())
    if (length(info$levels) == 1L) .format_tab_summary_one(info)
    else .format_tab_summary_two(info)
}

.tab_summary_numbers <- function(values) {
    vapply(as.double(values), function(value) {
        if (!is.finite(value)) "." else .summarize_general(value, width = 10L)
    }, character(1), USE.NAMES = FALSE)
}

.tab_summary_center <- function(text, width) {
    paste0(strrep(" ", pmax(0L, ceiling((width - .tab_width(text)) / 2L))), text)
}

.tab_summary_stub <- function(info, one_way) {
    if (!info$strings[[1L]]) return(if (one_way) 12L else 11L)
    maximum <- if (one_way) 70L - 12L * length(info$statistics) else 41L
    storage <- info$widths[[1L]]
    if (is.na(storage)) storage <- max(.tab_width(.tab_level_text(info$display_levels[[1L]])))
    max(if (one_way) 12L else 11L, min(storage, maximum))
}

.tab_summary_labels <- function(levels, string, width) {
    text <- .tab_level_text(levels)
    if (!string) return(.tab_cut(text, 9L))
    too_long <- .tab_width(text) > width
    text[too_long] <- paste0(.tab_cut(text[too_long], width - 2L), "..")
    text
}

.format_tab_summary_one <- function(info) {
    stats <- info$statistics
    block <- 12L * length(stats)
    stub <- .tab_summary_stub(info, TRUE)
    header <- .tab_wrap(info$headers[[1L]], stub - 1L)
    summary_header <- .tab_summary_center(.tab_wrap(
        paste("Summary of", info$summary_header), block - 1L), block)
    statistic_labels <- c(mean = "Mean", sd = "Std. dev.", freq = "Freq.", obs = "Obs")
    height <- max(length(header), length(summary_header) + 1L)
    left <- c(rep("", height - length(header)), header)
    right <- c(rep("", height - length(summary_header) - 1L), summary_header,
        paste(.tab_pad(statistic_labels[stats], 12L), collapse = ""))
    rule <- paste0(strrep("-", stub), "+", strrep("-", block))
    numbers <- vapply(stats, function(stat) .tab_summary_numbers(info$margins[[stat]]),
        character(length(info$levels[[1L]]) + 1L))
    labels <- c(.tab_summary_labels(info$display_levels[[1L]], info$strings[[1L]], stub - 1L), "Total")
    body <- .tab_stub_lines(labels, stub,
        apply(numbers, 1L, function(row) paste(.tab_pad(row, 12L), collapse = "")))
    c(.tab_stub_lines(left, stub, right), rule,
      utils::head(body, -1L), rule, utils::tail(body, 1L))
}

.format_tab_summary_two <- function(info) {
    stats <- info$statistics
    labels <- c(mean = "Means", sd = "Standard Deviations", freq = "Frequencies",
        obs = "Number of observations")[stats]
    description <- if (length(labels) == 1L) labels else
        paste(paste(utils::head(labels, -1L), collapse = ", "), utils::tail(labels, 1L), sep = " and ")
    outcome <- paste("of", info$summary_header)
    title <- paste(description, outcome)
    title <- if (.tab_width(title) <= 70L) title else
        c(.tab_wrap(description, 70L), .tab_wrap(outcome, 70L))
    title <- .tab_summary_center(title, 74L)
    stub <- .tab_summary_stub(info, FALSE)
    rows <- .tab_summary_labels(info$display_levels[[1L]], info$strings[[1L]], stub - 1L)
    columns <- .tab_summary_labels(info$display_levels[[2L]], info$strings[[2L]], 9L)
    statistics <- lapply(info$margins[stats], function(values) {
        matrix(.tab_summary_numbers(values), nrow = nrow(values))
    })
    # Native summarize tables use the legacy fixed 80-column layout,
    # independently of Stata's linesize setting. wrap uses ten-column panels.
    per_panel <- if (isTRUE(info$options$wrap)) 10L else
        max(1L, (80L - stub - 13L) %/% 11L)
    panels <- split(seq_along(columns), (seq_along(columns) - 1L) %/% per_panel)
    output <- lapply(seq_along(panels), function(i) {
        panel <- .format_tab_summary_panel(rows, columns, info$headers,
            stub, statistics, panels[[i]])
        c(if (i > 1L) "", panel)
    })
    c(title, "", unlist(output, use.names = FALSE))
}

.format_tab_summary_panel <- function(rows, columns, headers, stub, statistics, selected) {
    block <- 11L * length(selected)
    row_header <- .tab_wrap(headers[[1L]], stub - 1L)
    column_header <- .tab_summary_center(.tab_wrap(headers[[2L]], 10L * length(selected)),
        10L * length(selected))
    cells <- function(values) paste0(paste(.tab_pad(values, 10L), collapse = " "), " ")
    levels_line <- paste0(cells(columns[selected]), "|", .tab_pad("Total", 10L))
    height <- max(length(row_header), length(column_header) + 1L)
    stub_text <- c(rep("", height - length(row_header)), row_header)
    right <- c(rep("", height - 1L - length(column_header)), column_header, levels_line)
    rule <- paste0(strrep("-", stub), "+", strrep("-", block), "+", strrep("-", 10L))
    total_column <- ncol(statistics[[1L]])
    body <- function(index, label) .tab_stub_lines(
        c(label, rep("", length(statistics) - 1L)), stub,
        vapply(statistics, function(statistic) {
            paste0(cells(statistic[index, selected]), "|",
                .tab_pad(statistic[index, total_column], 10L))
        }, character(1)))
    c(.tab_stub_lines(stub_text, stub, right), rule,
      unlist(lapply(seq_along(rows), function(i) {
          c(body(i, rows[[i]]), if (length(statistics) > 1L && i < length(rows)) rule)
      }), use.names = FALSE), rule, body(length(rows) + 1L, "Total"))
}
