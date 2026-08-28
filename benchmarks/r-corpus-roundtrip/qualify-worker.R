args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("usage: qualify-worker.R INPUT_DTA OUTPUT_DTA")

script_argument <- grep(
    "^--file=", commandArgs(trailingOnly = FALSE), value = TRUE
)[[1L]]
script_dir <- dirname(normalizePath(
    sub("^--file=", "", script_argument), winslash = "/"
))
source(file.path(script_dir, "common.R"), local = TRUE)
benchmark_activate_library(c("dtatools", "haven"))

input <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
output <- args[[2L]]

label_table <- function(value) {
    labels <- attr(value, "labels", exact = TRUE)
    if (is.null(labels)) return(NULL)
    tags <- dtatools::missing_tag(labels)
    keys <- ifelse(
        is.na(tags),
        paste0("number:", format(labels, scientific = FALSE, trim = TRUE)),
        paste0("missing:", tags)
    )
    order_index <- order(keys, method = "radix")
    data.frame(
        key = keys[order_index], text = names(labels)[order_index],
        stringsAsFactors = FALSE
    )
}

column_difference <- function(before, after) {
    metadata <- c("label", "format.stata", "stata.storage", "tzone")
    if (!identical(class(before), class(after))) return("class")
    for (attribute in metadata) {
        if (!identical(
            attr(before, attribute, exact = TRUE),
            attr(after, attribute, exact = TRUE)
        )) return(paste("attribute", attribute))
    }
    if (!identical(label_table(before), label_table(after))) return("value labels")
    if (is.character(before)) {
        if (!identical(as.vector(before), as.vector(after))) {
            return("character values")
        }
        return(NULL)
    }
    if (!identical(
        dtatools::missing_tag(before), dtatools::missing_tag(after)
    )) return("missing codes")
    if (!identical(as.double(before), as.double(after))) return("numeric values")
    NULL
}

dataset_difference <- function(before, after) {
    if (!identical(dim(before), dim(after))) return("dimensions")
    if (!identical(names(before), names(after))) return("variable names")
    if (!identical(
        attr(before, "label", exact = TRUE),
        attr(after, "label", exact = TRUE)
    )) return("dataset label")
    if (!identical(
        attr(before, "notes", exact = TRUE),
        attr(after, "notes", exact = TRUE)
    )) return("dataset notes")
    for (index in seq_along(before)) {
        difference <- column_difference(before[[index]], after[[index]])
        if (!is.null(difference)) {
            return(sprintf("column %s %s", index, difference))
        }
    }
    NULL
}

expected_after_reported_conversions <- function(before, warning_classes) {
    conversion_classes <- intersect(warning_classes, c(
        "dtatools_write_factor_warning",
        "dtatools_write_character_missing_warning",
        "dtatools_write_numeric_replacement_warning"
    ))
    unexpected <- setdiff(conversion_classes,
                          "dtatools_write_numeric_replacement_warning")
    if (length(unexpected)) {
        stop("imported DTA source required an unexpected export conversion")
    }
    if (!("dtatools_write_numeric_replacement_warning" %in% warning_classes)) {
        return(before)
    }

    expected <- before
    for (index in seq_along(before)) {
        column <- before[[index]]
        if (!is.numeric(column) || is.factor(column)) next
        kind <- dtatools:::.write_column_kind(column)
        plan <- suppressWarnings(
            dtatools:::.prepare_dta_write_numeric(
                column, names(before)[[index]], kind, TRUE
            )
        )
        replaced <- dtatools:::.dta_write_numeric_replacement_mask(
            plan
        )
        if (!any(replaced)) next
        values <- as.double(column)
        values[replaced] <- NA_real_
        attributes(values) <- attributes(column)
        expected[[index]] <- values
    }
    expected
}

status <- "worker-error"
rows <- columns <- output_bytes <- NA_real_
result <- tryCatch({
    before <- dtatools::read_dta(input)
    warning_classes <- character()
    withCallingHandlers(
        dtatools::write_dta(before, output, version = 19L),
        warning = function(condition) {
            warning_classes <<- union(warning_classes, class(condition))
            invokeRestart("muffleWarning")
        }
    )
    if (!identical(corpus_dta_release(output), 118L)) {
        stop("ordinary corpus output did not use DTA release 118")
    }
    after <- dtatools::read_dta(output)
    expected <- expected_after_reported_conversions(before, warning_classes)
    difference <- dataset_difference(expected, after)
    if (!is.null(difference)) {
        stop("semantic round-trip mismatch: ", difference)
    }
    rows <- nrow(before)
    columns <- ncol(before)
    rm(before, expected, after)
    gc()
    haven_result <- haven::read_dta(output)
    if (!identical(dim(haven_result), c(rows, columns))) {
        stop("haven dimension mismatch")
    }
    status <- "r-pass"
    output_bytes <- file.info(output, extra_cols = FALSE)$size[[1L]]
    TRUE
}, error = function(condition) {
    message("qualification worker: ", conditionMessage(condition))
    FALSE
})

cat(sprintf(
    "DTATOOLS_ROUNDTRIP\t%s\t%s\t%s\t%s\n",
    status, rows, columns, output_bytes
))
if (!result) quit(status = 1L)
