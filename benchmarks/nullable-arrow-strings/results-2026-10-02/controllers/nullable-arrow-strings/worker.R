# One public read in one fresh R process. Do not load reference strings until
# every retained timing has ended: doing so would prewarm R's string cache.
args <- commandArgs(TRUE)
stopifnot(length(args) == 7L)
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
.libPaths(c(library_path, .libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(identical(normalizePath(find.package("dtatools")), file.path(library_path, "dtatools")))
fixtures <- normalizePath(args[[2L]], mustWork = TRUE)
fixture_id <- args[[3L]]
threads <- as.integer(args[[4L]])
mode <- args[[5L]]
phase <- args[[6L]]
stopifnot(threads %in% c(0L, 1L), mode %in% c("read", "scalar", "full"),
          phase %in% c("qualify", "measure"))
manifest <- read.csv(file.path(fixtures, "fixtures.csv"), stringsAsFactors = FALSE)
fixture <- manifest[manifest$id == fixture_id, , drop = FALSE]
stopifnot(nrow(fixture) == 1L)
path <- file.path(fixtures, paste0(fixture_id, ".arrow"))
reader <- compiler::cmpfun(function() read_arrow(path, verify = TRUE, threads = threads, output = "tibble"))
consume <- compiler::cmpfun(function(value) lapply(value, function(column) {
    if (is.character(column)) {
        # Keep the exact NA positions as well as byte lengths. sum(...,
        # na.rm=TRUE) by itself would hide NA-versus-empty regressions.
        list(bytes = nchar(column, type = "bytes", allowNA = TRUE, keepNA = TRUE),
             missing = is.na(column))
    } else {
        list(values = unname(as.double(column)), missing = is.na(column))
    }
}))
first <- compiler::cmpfun(function(value) lapply(value, function(column) column[[1L]]))
plain <- function(column) {
    if (is.character(column)) {
        value <- enc2utf8(column)
        attributes(value) <- NULL
        return(value)
    }
    unname(as.double(column))
}
metadata <- function(frame) list(label = attr(frame, "label", exact = TRUE),
    names = names(frame), columns = lapply(frame, function(column)
        list(label = attr(column, "label", exact = TRUE), format = attr(column, "format.stata", exact = TRUE))))
encoding <- function(frame) lapply(frame, function(column)
    if (is.character(column)) Encoding(column) else character())
hash <- function(value) unname(tools::sha256sum(bytes = serialize(value, NULL, version = 3L)))
cpu <- function(value) unname(value[["user.self"]] + value[["sys.self"]])
elapsed <- function(value) unname(value[["elapsed"]])
now <- if (phase == "measure") proc.time else function() c(user.self = 0, sys.self = 0, elapsed = 0)
gc_clock <- if (phase == "measure") gc.time else function() c(0, 0, 0, 0, 0)
if (phase == "measure") gc.time(TRUE)
invisible(gc(full = TRUE))
gc_before <- gc_clock()
started <- now()
value <- withCallingHandlers(reader(), warning = function(condition)
    stop("Unexpected reader warning: ", conditionMessage(condition)))
read_finished <- now()
if (mode == "scalar") observed <- first(value)
if (mode == "full") observed <- consume(value)
finished <- if (mode == "read") read_finished else now()
gc_after <- gc_clock()
# No extra read, reference construction, or first complete traversal intervenes
# before this separate second-traversal observation.
if (mode == "full") {
    second_gc_before <- gc_clock()
    second_started <- now()
    second <- consume(value)
    second_finished <- now()
    second_gc_after <- gc_clock()
    stopifnot(identical(observed, second))
} else {
    second_started <- second_finished <- now()
    second_gc_before <- second_gc_after <- gc_clock()
}
dictionary_after_workflow <- vapply(value, dtatools:::.is_unmaterialized_dictstring, logical(1))
# Public encoding flags must be captured before enc2utf8() normalization.
actual_encoding <- encoding(value)
actual_metadata <- metadata(value)
actual_values <- lapply(value, plain)
if (mode != "full") observed_full <- consume(value) else observed_full <- observed
expected <- readRDS(file.path(fixtures, paste0(fixture_id, ".rds")))
expected_values <- lapply(expected, plain)
expected_full <- consume(expected)
stopifnot(inherits(value, "tbl_df"), !inherits(value, "dibble"),
    nrow(value) == fixture$n, ncol(value) == fixture$columns,
    identical(actual_values, expected_values), identical(actual_metadata, metadata(expected)),
    identical(actual_encoding, encoding(expected)), identical(observed_full, expected_full),
    all(vapply(value, function(x) sum(is.na(x)), numeric(1)) == fixture$expected_na_per_column))
if (mode == "scalar") stopifnot(identical(observed, first(expected)))
if (fixture$cardinality != "numeric") {
    stopifnot(identical(lapply(actual_values, is.na), lapply(expected_values, is.na)),
        identical(lapply(actual_values, function(x) which(x == "")),
                  lapply(expected_values, function(x) which(x == ""))))
}
read_duration <- read_finished - started
consume_duration <- finished - read_finished
total_duration <- finished - started
second_duration <- second_finished - second_started
result <- data.frame(id = fixture_id, threads, mode, phase, rows = fixture$n,
    columns = fixture$columns, expected_na_per_column = fixture$expected_na_per_column,
    dictionary_columns_after_workflow = sum(dictionary_after_workflow),
    read_cpu_seconds = cpu(read_duration), read_wall_seconds = elapsed(read_duration),
    consume_cpu_seconds = cpu(consume_duration), consume_wall_seconds = elapsed(consume_duration),
    total_cpu_seconds = cpu(total_duration), total_wall_seconds = elapsed(total_duration),
    gc_cpu_seconds = sum((gc_after - gc_before)[1:2]),
    second_cpu_seconds = cpu(second_duration), second_wall_seconds = elapsed(second_duration),
    second_gc_cpu_seconds = sum((second_gc_after - second_gc_before)[1:2]),
    values_sha256 = hash(actual_values), metadata_sha256 = hash(actual_metadata),
    encoding_sha256 = hash(actual_encoding), consumption_sha256 = hash(observed_full),
    values_exact = TRUE, metadata_exact = TRUE, raw_encoding_exact = TRUE,
    consumption_exact = TRUE)
write.csv(result, args[[7L]], row.names = FALSE)
cat("Qualified", fixture_id, "threads", threads, mode, phase, "\n")
