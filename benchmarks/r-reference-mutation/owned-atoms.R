#!/usr/bin/env Rscript
# Lower-level integer/factor mutation qualification, with exact source guards.
args <- commandArgs(TRUE)
if (length(args) != 3L) stop("Usage: owned-atoms.R LIBRARY SOURCE_SHA OUTPUT_DIRECTORY")
source("benchmarks/r-dibble-dplyr/helpers.R")
library_path <- normalizePath(args[[1L]], mustWork = TRUE)
validate_benchmark_install(library_path, args[[2L]])
.libPaths(c(library_path, .libPaths()))
suppressPackageStartupMessages(library(dtatools))
package_path <- normalizePath(file.path(library_path, "dtatools"))
stopifnot(identical(normalizePath(find.package("dtatools")), package_path),
    identical(normalizePath(getLoadedDLLs()[["dtatools"]][["path"]]),
        normalizePath(file.path(package_path, "libs", paste0("dtatools", .Platform$dynlib.ext)))),
    capabilities("profmem"), dir.exists(args[[3L]]))
output <- file.path(args[[3L]], "owned-native-atoms.csv")
identity <- file.path(args[[3L]], "owned-native-atoms-session.txt")
stopifnot(!file.exists(output), !file.exists(identity))
paths <- c("benchmarks/r-reference-mutation/owned-atoms.R", "benchmarks/r-dibble-dplyr/helpers.R")
checked_line <- function(command, arguments, pattern) {
    value <- suppressWarnings(system2(command, arguments, stdout = TRUE))
    status <- attr(value, "status")
    if ((!is.null(status) && status != 0L) || length(value) != 1L ||
        is.na(value) || !grepl(pattern, value)) stop("Invalid or failed identity command: ", command)
    unname(value)
}
git_hash <- function(arguments) checked_line("git", arguments, "^[0-9a-f]{40}$")
revision <- git_hash(c("rev-parse", "HEAD"))
sha256 <- function(path) substr(checked_line("shasum", c("-a", "256", shQuote(path)),
                                           "^[0-9a-f]{64}[[:space:]]+"), 1L, 64L)
check_runner <- function() {
    for (path in paths) {
        committed <- git_hash(c("rev-parse", shQuote(paste0(revision, ":", path))))
        current <- git_hash(c("hash-object", shQuote(path)))
        stopifnot(identical(committed, current))
    }
}
check_runner()
runner_hashes <- vapply(paths, sha256, character(1))
identity_connection <- file(identity, "wx")
writeLines(c(paste("source", args[[2L]]), paste("runner_revision", revision),
    paste("library", library_path), paste(paths, runner_hashes),
    capture.output(sessionInfo())), identity_connection)
close(identity_connection)
native <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
info <- function(data) native("C_dtatools_mutation_info", data, 1L)
profile <- function(fun) {
    path <- tempfile()
    on.exit({ Rprofmem(NULL); unlink(path) })
    before <- native("C_dtatools_native_copy_stats", FALSE)
    Rprofmem(path)
    fun()
    Rprofmem(NULL)
    bytes <- suppressWarnings(as.numeric(sub(" .*", "", readLines(path, warn = FALSE))))
    bytes <- bytes[is.finite(bytes)]
    c(r_allocated_bytes = sum(bytes), r_largest_allocation_bytes = max(c(0, bytes)),
      native("C_dtatools_native_copy_stats", FALSE) - before)
}
records <- list()
for (rows in c(100000L, 1000000L)) for (kind in c("integer", "factor", "ordered")) {
    cat("Native atom case:", kind, rows, "rows\n")
    # Assigning factor attributes to a large existing vector can create R's
    # foreign metadata ALTREP. Construct actual ordinary factor storage here.
    values <- if (kind == "integer") rep(c(1L, 2L, NA_integer_), length.out = rows) else
        factor(rep(c("first", "second", NA_character_), length.out = rows),
               levels = c("first", "second", "unused"), ordered = kind == "ordered")
    stopifnot(typeof(values) == "integer", !native("C_dtatools_is_altrep", values))
    # Snapshot before native capture; an erroneous borrowed write must not
    # change both the source and its oracle through an ordinary R alias.
    original <- unserialize(serialize(values, NULL))
    column <- native("C_dtatools_capture_column", values)
    sibling <- native("C_dtatools_metadata_copy", column)
    column_info <- native("C_dtatools_owned_info", column)
    sibling_info <- native("C_dtatools_owned_info", sibling)
    stopifnot(!is.null(column_info), !is.null(sibling_info),
              identical(column_info$depth, 1L), identical(sibling_info$depth, 1L),
              identical(column_info$backing, sibling_info$backing))
    data <- structure(list(x = column), class = "data.frame", row.names = c(NA_integer_, -rows),
                      label = "native owned atom fixture", note = c("one", "two"))
    table_attributes <- function(x) {
        result <- attributes(x)
        result$row.names <- .row_names_info(x, 0L)
        result
    }
    original_table_attributes <- table_attributes(data)
    check <- function(expected) {
        stopifnot(identical(data$x, expected), identical(values, original),
            identical(attributes(data$x), attributes(original)),
            identical(names(data), "x"), identical(class(data), "data.frame"),
            identical(attr(data, "label"), "native owned atom fixture"),
            identical(attr(data, "note"), c("one", "two")),
            identical(table_attributes(data), original_table_attributes),
            identical(.row_names_info(data, 0L), c(NA_integer_, -rows)))
    }
    changed <- function(x, index, code) {
        if (kind == "integer") x[index] <- code else x[index] <- factor(
            levels(x)[code], levels = levels(x), ordered = is.ordered(x))
        x
    }
    rm(column)
    before <- info(data)
    first <- profile(function() native("C_dtatools_patch_slot", data, 1L, 1L, 2L, TRUE))
    shared_after <- info(data)
    stopifnot(!identical(shared_after$backing, before$backing),
              shared_after$backing_private, !shared_after$handle_shared,
              first[["mutation_target_copy"]] == rows * 4,
              first[["r_largest_allocation_bytes"]] <= rows * 4 + 1000)
    first_expected <- changed(original, 1L, 2L)
    check(first_expected)
    stopifnot(identical(sibling, original))
    # Release only the test oracle's R access before testing true privacy.
    invisible(gc())
    stopifnot(info(data)$backing_private, !info(data)$handle_shared)
    second <- profile(function() native("C_dtatools_patch_slot", data, 1L, 2L, 1L, FALSE))
    private_after <- info(data)
    stopifnot(identical(private_after$backing, shared_after$backing),
              second[["mutation_target_copy"]] == 0, second[["owned_capture"]] == 0,
              second[["r_allocated_bytes"]] < 100000, second[["r_largest_allocation_bytes"]] < 10000)
    expected <- changed(first_expected, 2L, 1L)
    check(expected)
    stopifnot(identical(data$x, expected), identical(sibling, original), identical(values, original),
              identical(attributes(data$x), attributes(original)),
              identical(.row_names_info(data, 0L), c(NA_integer_, -rows)))
    native("C_dtatools_patch_vector", sibling, 3L, 1L)
    sibling_expected <- changed(original, 3L, 1L)
    stopifnot(identical(sibling, sibling_expected),
              identical(data$x, expected), identical(values, original))
    full_alias <- data$x
    full <- profile(function() native("C_dtatools_patch_slot", data, 1L, NULL, 2L, TRUE))
    full_expected <- rep(2L, rows)
    attributes(full_expected) <- attributes(original)
    check(full_expected)
    stopifnot(full[["mutation_target_copy"]] == 0, full[["owned_capture"]] == 0,
              full[["old_journal"]] == 0, identical(sibling, sibling_expected),
              identical(full_alias, expected), identical(values, original),
              identical(attributes(data$x), attributes(original)), all(as.integer(data$x) == 2L))
    for (operation in c("first_shared", "subsequent_private", "full_replacement")) {
        metrics <- switch(operation, first_shared = first, subsequent_private = second, full_replacement = full)
        records[[length(records) + 1L]] <- cbind(data.frame(kind, rows, operation), as.data.frame(as.list(metrics)))
    }
}
output_connection <- file(output, "wx")
write.csv(do.call(rbind, records), output_connection, row.names = FALSE)
close(output_connection)
validate_benchmark_install(library_path, args[[2L]])
check_runner()
cat("Passed all 18 native integer/factor allocation and isolation cases.\n")
