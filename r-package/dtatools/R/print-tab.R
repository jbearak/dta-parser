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
        lines <- format(x, width = width)
        if (length(lines)) cat(lines, sep = "\n")
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
        lines <- .format_two_way_tab(x, info, width)
        tests <- if (length(info$tests)) .tab_format_association(info$tests) else character()
        c(lines, if (length(lines) && length(tests)) "", tests)
    }
}

# The presentation record, or `NULL` for a table this printer cannot
# describe: three or more variables, a result that arithmetic or a
# reshaping has turned into something other than counts, or one whose
# category names were removed. Weighted frequencies also permit doubles.
.dta_tab_info <- function(x) {
    info <- attr(x, "dta_tab", exact = TRUE)
    extents <- dim(x)
    names <- dimnames(x)
    if (is.null(info) ||
        !(is.integer(x) || (is.double(x) && !is.null(info$options$weight))) ||
        !length(extents) %in% 1:2 ||
        length(info$headers) != length(extents) ||
        length(names) != length(extents) ||
        !all(lengths(names) == extents)) {
        return(NULL)
    }
    info
}

#' @export
`[.dta_tab` <- function(x, ...) as.table(x)[...]

# Assignment invalidates statistics and category text just as arithmetic
# and subsetting do. Return a plain table rather than retaining stale results.
#' @export
`[<-.dta_tab` <- function(x, ..., value) {
    x <- as.table(x)
    x[...] <- value
    x
}

#' @export
`[[<-.dta_tab` <- function(x, ..., value) {
    x <- as.table(x)
    x[[...]] <- value
    x
}

#' @export
`dimnames<-.dta_tab` <- function(x, value) {
    x <- as.table(x)
    dimnames(x) <- value
    x
}

#' @export
`dim<-.dta_tab` <- function(x, value) {
    x <- as.table(x)
    dim(x) <- value
    x
}

#' @export
`names<-.dta_tab` <- function(x, value) {
    x <- as.table(x)
    names(x) <- value
    x
}

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
    counts <- as.numeric(x)
    info <- .dta_tab_info(x)
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
        if (isTRUE(info$options$cchi2)) {
            statistics$cchi2 <- as.vector((counts - outer(row_total, column_total) / total)^2 /
                                          (outer(row_total, column_total) / total))
        }
        if (isTRUE(info$options$clrchi2)) {
            contribution <- 2 * counts * log(counts / (outer(row_total, column_total) / total))
            contribution[counts == 0 & outer(row_total, column_total) / total > 0] <- 0
            statistics$clrchi2 <- as.vector(contribution)
        }
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
    counts <- as.numeric(x)
    total <- sum(counts)
    if (total == 0L && (!isTRUE(info$options$subpop) || !length(x)))
        return("no observations")
    if (!info$options$freq) return(character())
    levels <- .tab_level_text(if (is.null(info$levels)) dimnames(x)[[1L]] else info$levels[[1L]])
    stub <- .tab_stub_width(levels, info$widths[[1L]], 11L, 39L)
    header <- .tab_wrap(info$headers[[1L]], stub - 1L)
    if (isTRUE(info$options$plot)) return(.format_tab_plot(counts, levels, header, stub))
    percent <- 100 * counts / total
    columns <- sprintf("%11s%12s%12s", "Freq.", "Percent", "Cum.")
    rule <- paste0(strrep("-", stub), "+", strrep("-", 35L))
    c(
        .tab_stub_lines(header, stub, c(rep("", length(header) - 1L), columns)),
        rule,
        .tab_stub_lines(
            levels, stub,
            paste0(
                .tab_pad(.tab_count_text(counts, 11L, total), 11L),
                .tab_pad(.tab_decimal_text(percent, 2L), 12L),
                .tab_pad(.tab_decimal_text(cumsum(percent), 2L), 12L)
            )
        ),
        rule,
        .tab_stub_lines(
            "Total", stub,
            paste0(.tab_pad(.tab_count_text(total, 11L), 11L),
                   if (total > 0) .tab_pad("100.00", 12L) else " ")
        )
    )
}

# The text plot occupies a fixed 79-column line in Stata, independent of
# the current line size. Frequencies smaller than the available bar width
# retain one star per observation; larger counts scale the longest bar.
.format_tab_plot <- function(counts, levels, header, stub) {
    bar_width <- 65L - stub
    stars <- if (max(counts) <= bar_width) floor(counts) else
        floor(counts * bar_width / max(counts) + 0.5)
    rule <- paste0(strrep("-", stub), "+", strrep("-", 12L), "+",
                   strrep("-", bar_width))
    c(.tab_stub_lines(header, stub,
                      c(rep("", length(header) - 1L), .tab_pad("Freq.", 11L))),
      rule,
      .tab_stub_lines(levels, stub, paste0(
          .tab_pad(.tab_count_text(counts, 11L, sum(counts)), 11L), " |", strrep("*", stars))),
      rule,
      .tab_stub_lines("Total", stub, paste0(
          .tab_pad(.tab_count_text(sum(counts), 11L), 11L), " ")))
}

.format_two_way_tab <- function(x, info, width) {
    counts <- matrix(as.numeric(x), nrow = dim(x)[[1L]])
    total <- sum(counts)
    if (!info$options$freq && !info$options$expected &&
        !isTRUE(info$options$cchi2) && !isTRUE(info$options$clrchi2) &&
        !length(info$options$percent) && !length(info$tests)) return(character())
    if (total == 0L && (!isTRUE(info$options$subpop) || !length(x)))
        return("no observations")
    rows <- .tab_level_text(if (is.null(info$levels)) dimnames(x)[[1L]] else info$levels[[1L]])
    columns <- .tab_cut(.tab_level_text(if (is.null(info$levels)) dimnames(x)[[2L]] else info$levels[[2L]]), 9L)
    stub <- .tab_stub_width(rows, info$widths[[1L]], 10L, 21L)
    statistics <- .tab_two_way_statistics(counts, info$options)
    if (!length(statistics)) return(character())
    # A panel line is the stub, a bar, eleven columns per level, a bar, the
    # ten-wide total, and its trailing space: `stub + 11 * k + 13` columns.
    per_panel <- max(1L, (as.integer(width) - stub - 13L) %/% 11L)
    if (isTRUE(info$options$wrap)) per_panel <- ncol(counts)
    panels <- split(seq_len(ncol(counts)), (seq_len(ncol(counts)) - 1L) %/% per_panel)
    lines <- lapply(panels, function(selected) {
        .format_tab_panel(rows, columns, info$headers, stub, statistics, selected)
    })
    c(
        if (!isTRUE(info$options$nokey) &&
            (isTRUE(info$options$key) ||
             (is.null(info$options$key) && length(statistics) > 1L)))
            c(.tab_key(names(statistics)), ""),
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
            outer(row_total, column_total) / total,
            if (total > 0) row_total else row_total * NA_real_,
            if (total > 0) column_total else column_total * NA_real_,
            if (total > 0) total else NA_real_
        ), 1L)
    }
    expected <- outer(row_total, column_total) / total
    contribution <- function(cells) {
        .tab_decimal_text(with_margins(cells, rowSums(cells),
                                      colSums(cells), sum(cells)), 1L)
    }
    if (isTRUE(options$cchi2)) {
        cells <- (counts - expected)^2 / expected
        statistics[["chi2 contribution"]] <- contribution(cells)
    }
    if (isTRUE(options$clrchi2)) {
        cells <- 2 * counts * log(counts / expected)
        cells[counts == 0 & !is.na(expected) & expected > 0] <- 0
        statistics[["LR chi2 contribution"]] <- contribution(cells)
    }
    if ("row" %in% options$percent) {
        statistics[["row percentage"]] <- percent(with_margins(
            100 * counts / row_total, 100 * row_total / row_total,
            100 * column_total / total, 100 * total / total
        ))
    }
    if ("column" %in% options$percent) {
        statistics[["column percentage"]] <- percent(with_margins(
            100 * sweep(counts, 2L, column_total, "/"), 100 * row_total / total,
            100 * column_total / column_total, 100 * total / total
        ))
    }
    if ("cell" %in% options$percent) {
        statistics[["cell percentage"]] <- percent(with_margins(
            100 * counts / total, 100 * row_total / total,
            100 * column_total / total, 100 * total / total
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

.tab_count_text <- function(counts, width = 10L, largest = max(abs(counts))) {
    commas <- is.finite(largest) &&
        nchar(formatC(largest, big.mark = ",", format = "f", digits = 0L)) <= width
    text <- vapply(as.numeric(counts), function(value) {
        if (!is.finite(value)) return(".")
        # Stata preserves exact short decimal frequencies, and otherwise
        # uses its general numeric format at the available column width.
        fixed <- format(value, scientific = FALSE, digits = width, trim = TRUE)
        fixed <- sub("^0\\.", ".", fixed)
        if (value == round(value)) {
            grouped <- formatC(value, big.mark = ",", format = "f", digits = 0L)
            if (commas && nchar(grouped) <= width) return(grouped)
            fixed <- formatC(value, format = "f", digits = 0L)
        }
        if (nchar(fixed) <= width) return(fixed)
        text <- .summarize_general(value, width = width)
        if (grepl("^[0-9]+$", text)) {
            grouped <- formatC(as.numeric(text), big.mark = ",", format = "f", digits = 0L)
            if (commas && nchar(grouped) <= width) return(grouped)
        }
        text
    }, character(1), USE.NAMES = FALSE)
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
