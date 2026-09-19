# General snapshots remove dibble dispatch. A display snapshot restores only
# its public identity, plus temporary string views; stored columns are unchanged.
.dibble_display_snapshot <- function(x) {
    result <- .reference_snapshot(x)
    for (index in seq_along(result)) {
        column <- .subset2(result, index)
        classes <- setdiff(class(column), .dta_metadata_vector_class)
        bare_string <- !length(classes) || identical(classes, "character")
        if (is.character(column) && bare_string &&
            !is.null(attr(column, "stata.string.storage", exact = TRUE))) {
            column <- .metadata_copy(column)
            class(column) <- c("dtatools_dibble_string", class(column))
            result[[index]] <- column
        }
    }
    class(result) <- c("dibble", class(result))
    result
}

# Keep pillar's dimensions and any registered grouping summary. Without dplyr,
# supply its grouping labels from the stored metadata. See NOTICE.
#' @exportS3Method pillar::tbl_sum
tbl_sum.dibble <- function(x, ...) {
    result <- NextMethod()
    names(result)[[1L]] <- "A dibble"
    if (inherits(x, "grouped_df") && !"Groups" %in% names(result)) {
        groups <- attr(x, "groups", exact = TRUE)
        count <- length(.subset2(groups, ".rows"))
        separator <- if (identical(getOption("OutDec"), ",")) "." else ","
        result <- c(result, Groups = paste0(paste(.group_vars(x), collapse = ", "),
            " [", formatC(count, big.mark = separator), "]"))
    } else if (inherits(x, "rowwise_df") && !"Rowwise" %in% names(result)) {
        result <- c(result, Rowwise = paste(.group_vars(x), collapse = ", "))
    }
    result
}

# Delegate to the registered ordinary table method so pillar can still call
# tbl_sum.dibble on the snapshot, without recursively dispatching print.dibble.
.print_dibble <- function(x, ...) {
    utils::getS3method("print", "tbl")(.dibble_display_snapshot(x), ...)
}

#' @export
print.dibble <- function(x, ...) {
    if (.skip_bracket_autoprint(x, sys.nframe(), sys.call(1L))) {
        return(invisible(x))
    }
    .print_dibble(x, ...)
    invisible(x)
}

#' @export
format.dibble <- function(x, ...) {
    utils::getS3method("format", "tbl")(.dibble_display_snapshot(x), ...)
}

# These labels read declarations only, including for empty vectors and
# string declarations wider than their current contents. The temporary
# character class is restored by vctrs when pillar slices displayed rows.
#' @exportS3Method vctrs::vec_ptype_abbr
vec_ptype_abbr.dtatools_dibble_string <- function(x, ...) {
    attr(x, "stata.string.storage", exact = TRUE)
}

#' @exportS3Method vctrs::vec_ptype_abbr
vec_ptype_abbr.dta_numeric <- function(x, ...) {
    .declared_dta_storage(x)
}

# A Stata numeric column in a dibble or tibble takes pillar's own numeric
# shaft for its observed values, so `pillar.sigfig` and `sigfig` apply as
# they do to any double, and at format time the missing cells take
# Stata's spelling, `.` and `.a`, and a value-labelled cell is annotated
# with its text, `1 [One]`, as haven's shaft annotated it. Registered on
# the package class so that it wins over haven's shaft on a column that
# also carries `haven_labelled`. `options(dtatools.show_pillar_labels =
# FALSE)` turns the annotation off; haven's option of the same meaning is
# honoured when the dtatools one is unset.
#' @exportS3Method pillar::pillar_shaft
pillar_shaft.dta_numeric <- function(x, show_labels = NULL, ...) {
    values <- .dta_snapshot(x)
    inner <- pillar::pillar_shaft(unname(values), ...)
    labels <- .pillar_value_labels(x, show_labels)
    label_width <- if (is.null(labels) || !length(labels)) {
        0L
    } else {
        max(pillar::get_extent(labels))
    }
    pillar::new_pillar_shaft(
        list(inner = inner, codes = .tab_missing_codes(values), labels = labels),
        width = attr(inner, "width") + label_width,
        min_width = attr(inner, "min_width") + .pillar_label_reserve(label_width),
        class = "pillar_shaft_dta_numeric"
    )
}

# The observed cells are pillar's own rendering, so `sigfig` and the
# decimal alignment are pillar's; a missing cell takes Stata's spelling in
# the space pillar gave the `NA`. A table-less column keeps pillar's right
# alignment. A labelled column is left-aligned so the annotation follows
# each value, as haven's shaft laid it out, with a label that does not fit
# cut to the room left, and then styled subtle as haven styled it.
#' @export
format.pillar_shaft_dta_numeric <- function(x, width, ...) {
    labels <- x$labels
    label_width <- if (is.null(labels) || !length(labels)) {
        0L
    } else {
        max(pillar::get_extent(labels))
    }
    # The values keep pillar's full rendering while the room left holds at
    # least a cut label; only when it cannot does the value give way, down
    # to pillar's minimum, so a long label never costs a value its digits.
    inner_width <- attr(x$inner, "width")
    reserve <- .pillar_label_reserve(label_width)
    value_width <- if (width >= inner_width + reserve) {
        inner_width
    } else {
        max(attr(x$inner, "min_width"), width - reserve)
    }
    text <- format(format(x$inner, width = value_width))
    missing <- !is.na(x$codes)
    if (any(missing)) {
        spelled <- .stata_missing_text(x$codes[missing])
        pad <- pmax(0L, pillar::get_extent(text[missing]) - nchar(spelled))
        text[missing] <- paste0(strrep(" ", pad), spelled)
    }
    if (is.null(labels)) {
        return(pillar::new_ornament(text, width = width, align = "right"))
    }
    room <- pmax(0L, width - pillar::get_extent(text))
    labels <- .fit_pillar_labels(labels, room)
    styled <- nzchar(labels)
    labels[styled] <- pillar::style_subtle(labels[styled])
    text <- paste0(text, labels)
    pillar::new_ornament(text, width = width, align = "left")
}

# The least room kept for a label beside its value: the whole label when
# short, else enough for its opening and an ellipsis.
.pillar_label_reserve <- function(label_width) {
    min(label_width, 6L)
}

# A label wider than the room left is cut to fit, measured in terminal
# cells so a double-width glyph counts as two, and ends in an ellipsis.
# The labels are plain text here; the style is applied after fitting, so
# there is no escape sequence to measure or cut through.
.fit_pillar_labels <- function(labels, room) {
    fits <- pillar::get_extent(labels) <= room
    labels[!fits] <- vapply(which(!fits), function(i) {
        if (room[[i]] < 3L) return("")
        chars <- strsplit(labels[[i]], "", fixed = TRUE)[[1L]]
        widths <- cumsum(pillar::get_extent(chars))
        paste0(paste(chars[widths <= room[[i]] - 1L], collapse = ""), "\u2026")
    }, character(1L))
    labels
}

.pillar_value_labels <- function(x, show_labels = NULL) {
    # Only a table Stata could hold annotates; one it could not, such as
    # character codes or an `integer64`, has no codes to match.
    table <- .stata_value_label_table(attr(x, "labels", exact = TRUE))
    if (is.null(table) || length(table) == 0L) return(NULL)
    show <- if (is.null(show_labels)) {
        getOption(
            "dtatools.show_pillar_labels",
            getOption("haven.show_pillar_labels", TRUE)
        )
    } else {
        show_labels
    }
    if (!isTRUE(show)) return(NULL)
    # An observed value matches a code by value and a tagged missing by
    # its tag; system missing matches nothing, as in `tab()` and
    # `val_label()`.
    matched <- .match_value_label_codes(x, table)
    found <- !is.na(matched) & !is.na(names(table)[matched]) &
        nzchar(names(table)[matched])
    # Label text is user data and may hold a newline or tab; escaped, as
    # haven's shaft escaped it, so one cell stays one cell.
    labels <- encodeString(names(table)[matched[found]], quote = "")
    suffix <- character(length(x))
    suffix[found] <- paste0(" [", labels, "]")
    suffix
}

# A printed vector lists its value labels under the values, as haven does
# for `haven_labelled`, with the codes in Stata's spelling.
#' @exportS3Method vctrs::obj_print_footer
obj_print_footer.dta_numeric <- function(x, ...) {
    labels <- attr(x, "labels", exact = TRUE)
    if (is.null(labels) || length(labels) == 0L) return(invisible(x))
    cat("\nLabels:\n")
    table <- data.frame(
        value = format(.value_label_table(labels)),
        label = names(labels),
        stringsAsFactors = FALSE
    )
    print(table, row.names = FALSE)
    invisible(x)
}

#' @exportS3Method vctrs::vec_ptype_abbr
vec_ptype_abbr.dta_string <- function(x, ...) {
    attr(x, "stata.string.storage", exact = TRUE)
}

#' @exportS3Method vctrs::vec_ptype_abbr
vec_ptype_abbr.dta_temporal <- function(x, ...) {
    meaning <- if (inherits(x, "Date")) "date" else "dttm"
    paste(.declared_dta_storage(x), meaning, sep = "/")
}

# Metadata restoration puts its marker first, including after pillar slices
# rows. vctrs chooses the most specific class for type abbreviations, so let
# the underlying type supply the label. A metadata copy keeps compact strings
# unchanged while the display-only class attribute is removed.
#' @exportS3Method vctrs::vec_ptype_abbr
vec_ptype_abbr.dtatools_dta_metadata_vector <- function(x, ...) {
    value <- .metadata_copy(x)
    classes <- setdiff(class(value), .dta_metadata_vector_class)
    attr(value, "class") <- if (length(classes)) classes else NULL
    vctrs::vec_ptype_abbr(value, suffix_shape = FALSE)
}
