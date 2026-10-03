# One public read per fresh process. Load saved reference vectors after clocks.
args <- commandArgs(TRUE)
stopifnot(length(args) == 7L)
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
.libPaths(c(library_path, .libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(identical(normalizePath(find.package("dtatools")), file.path(library_path, "dtatools")))
fixtures <- normalizePath(args[[2L]], mustWork = TRUE)
id <- args[[3L]]
threads <- as.integer(args[[4L]])
mode <- args[[5L]]
phase <- args[[6L]]
stopifnot(threads %in% c(1L, 16L), mode %in% c("read", "full"),
          phase %in% c("qualify", "measure"))
manifest <- read.csv(file.path(fixtures, "fixtures.csv"), stringsAsFactors = FALSE)
fixture <- manifest[manifest$id == id, , drop = FALSE]
stopifnot(nrow(fixture) == 1L)
path <- file.path(fixtures, fixture$filename)
metadata <- function(frame) list(label = attr(frame, "label", exact = TRUE),
    names = names(frame), columns = lapply(frame, function(x)
        list(label = attr(x, "label", exact = TRUE),
             format = attr(x, "format.stata", exact = TRUE),
             storage = attr(x, "stata.storage", exact = TRUE),
             class = attr(x, "class", exact = TRUE), labels = attr(x, "labels", exact = TRUE))))
reader <- compiler::cmpfun(function() read_arrow(path, verify = TRUE,
    profile = fixture$profile, threads = threads, output = "tibble"))
consume <- compiler::cmpfun(function(frame) lapply(frame, function(x)
    list(total = sum(as.double(x), na.rm = TRUE), missing = is.na(x))))
hash <- function(value) unname(tools::sha256sum(bytes = serialize(value, NULL, version = 3L)))
bits <- function(x) writeBin(as.double(x), raw(), size = 8L, endian = "little")
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
if (mode == "full") consumed <- consume(value)
finished <- if (mode == "read") read_finished else now()
gc_after <- gc_clock()

# Observe retained state before complete validation can request data pointers.
compact_after <- vapply(value, dtatools:::.is_unmaterialized_numeric_altrep, logical(1))
owned_info <- lapply(value, function(x) .Call(dtatools:::C_dtatools_owned_numeric_info, x))
retained_after <- vapply(owned_info, function(x) x[["owned"]] == 1, logical(1))
chunks_after <- vapply(owned_info, function(x) x[["chunks"]], numeric(1))
actual_metadata <- metadata(value)
actual_types <- vapply(value, typeof, character(1))
expected <- readRDS(file.path(fixtures, paste0(id, ".rds")))
stopifnot(nrow(value) == fixture$n, ncol(value) == fixture$columns,
    identical(actual_metadata, expected$metadata), identical(actual_types, expected$types),
    all(compact_after == expected$retained), all(retained_after == expected$retained),
    all(chunks_after == if (expected$retained) expected$actual_batches else 0))
value_hashes <- character(length(value))
for (j in seq_along(value)) {
    observed <- bits(value[[j]])
    stopifnot(identical(observed, bits(expected$values[[j]])))
    value_hashes[[j]] <- unname(tools::sha256sum(bytes = observed))
}
expected_consumed <- consume(expected$values)
if (mode == "read") consumed <- consume(value)
stopifnot(identical(consumed, expected_consumed),
    all(vapply(consumed, function(x) sum(x$missing), numeric(1)) == fixture$expected_na_per_column))
output <- data.frame(id, threads, mode, phase, rows = fixture$n, columns = fixture$columns,
    profile = fixture$profile, route = fixture$route, retained = all(retained_after),
    compact_columns = sum(compact_after), retained_columns = sum(retained_after),
    chunks_per_column = chunks_after[[1L]],
    expected_na_per_column = fixture$expected_na_per_column,
    read_cpu_seconds = cpu(read_finished - started),
    read_wall_seconds = elapsed(read_finished - started),
    consume_cpu_seconds = cpu(finished - read_finished),
    consume_wall_seconds = elapsed(finished - read_finished),
    total_cpu_seconds = cpu(finished - started), total_wall_seconds = elapsed(finished - started),
    gc_cpu_seconds = sum((gc_after - gc_before)[1:2]),
    values_sha256 = hash(value_hashes), metadata_sha256 = hash(actual_metadata),
    types_sha256 = hash(actual_types), consumption_sha256 = hash(consumed),
    state_sha256 = hash(list(compact = compact_after, retained = retained_after, chunks = chunks_after)),
    stringsAsFactors = FALSE)
write.csv(output, args[[7L]], row.names = FALSE)
