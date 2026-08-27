args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) stop("usage: qualify-worker.R INPUT_DTA OUTPUT_DTA")

benchmark_library <- Sys.getenv("DTAPARSER_BENCH_LIB")
if (!nzchar(benchmark_library)) stop("DTAPARSER_BENCH_LIB is required")
.libPaths(c(normalizePath(benchmark_library, winslash = "/", mustWork = TRUE), .libPaths()))
if (!requireNamespace("dtaparser", quietly = TRUE) ||
    !requireNamespace("haven", quietly = TRUE)) {
    stop("dtaparser and haven must be installed in the benchmark environment")
}

script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[[1L]]
script_dir <- dirname(normalizePath(sub("^--file=", "", script_argument), winslash = "/"))
source(file.path(script_dir, "common.R"), local = TRUE)

input <- normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
output <- args[[2L]]

label_table <- function(value) {
    labels <- attr(value, "labels", exact = TRUE)
    if (is.null(labels)) return(NULL)
    tags <- dtaparser::missing_tag(labels)
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
        if (!identical(
            unname(vapply(before, identity, character(1))),
            unname(vapply(after, identity, character(1)))
        )) return("character values")
        return(NULL)
    }
    if (!identical(
        dtaparser::missing_tag(before), dtaparser::missing_tag(after)
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
        "dtaparser_write_factor_warning",
        "dtaparser_write_character_missing_warning",
        "dtaparser_write_numeric_replacement_warning"
    ))
    unexpected <- setdiff(conversion_classes,
                          "dtaparser_write_numeric_replacement_warning")
    if (length(unexpected)) {
        stop("imported DTA source required an unexpected export conversion")
    }
    if (!("dtaparser_write_numeric_replacement_warning" %in% warning_classes)) {
        return(before)
    }

    specification <- suppressWarnings(dtaparser:::.prepare_dta_write(
        before, 19L, attr(before, "label", exact = TRUE), 2045L, TRUE
    ))
    expected <- before
    for (index in seq_along(before)) {
        column <- before[[index]]
        if (!is.numeric(column) || is.factor(column)) next
        prepared <- specification[[3L]][[index]][[7L]]
        source_codes <- dtaparser:::.tab_missing_codes(column)
        prepared_codes <- dtaparser:::.tab_missing_codes(prepared)
        replaced <- !is.na(prepared_codes) & prepared_codes == 0L &
            (is.na(source_codes) | source_codes != 0L)
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
    before <- dtaparser::read_dta(input)
    warning_classes <- character()
    withCallingHandlers(
        dtaparser::write_dta(before, output, version = 19L),
        warning = function(condition) {
            warning_classes <<- union(warning_classes, class(condition))
            invokeRestart("muffleWarning")
        }
    )
    if (!identical(roundtrip_release(output), 118L)) {
        stop("ordinary corpus output did not use DTA release 118")
    }
    after <- dtaparser::read_dta(output)
    expected <- expected_after_reported_conversions(before, warning_classes)
    difference <- dataset_difference(expected, after)
    if (!is.null(difference)) {
        stop("semantic round-trip mismatch: ", difference)
    }
    haven_result <- haven::read_dta(output)
    if (!identical(dim(haven_result), dim(before))) {
        stop("haven dimension mismatch")
    }
    status <- "r-pass"
    rows <- nrow(before)
    columns <- ncol(before)
    output_bytes <- file.info(output, extra_cols = FALSE)$size[[1L]]
    TRUE
}, error = function(condition) {
    message("qualification worker: ", conditionMessage(condition))
    FALSE
})

cat(sprintf(
    "DTAPARSER_ROUNDTRIP\t%s\t%s\t%s\t%s\n",
    status, rows, columns, output_bytes
))
if (!result) quit(status = 1L)
