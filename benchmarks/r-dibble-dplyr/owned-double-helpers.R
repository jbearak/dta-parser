# Shared setup for the Stage 3 ownership measurements.
# Rprofmem and native counters overlap for R-backed payloads. Report them
# separately; adding them would count some allocations twice.
owned_benchmark_start <- function(library_path, source_sha, mode) {
    library_path <- normalizePath(library_path, mustWork = TRUE)
    source("benchmarks/r-dibble-dplyr/helpers.R", local = .GlobalEnv)
    validate_benchmark_install(library_path, source_sha)
    stopifnot(mode %in% c("baseline", "candidate"))
    .libPaths(c(library_path, .libPaths()))
    suppressPackageStartupMessages({
        library(dtatools, lib.loc = library_path)
        library(dplyr)
    })
    stopifnot(identical(normalizePath(find.package("dtatools")),
                        file.path(library_path, "dtatools")),
              identical(normalizePath(getLoadedDLLs()[["dtatools"]][["path"]]),
                        file.path(library_path, "dtatools", "libs",
                                  paste0("dtatools", .Platform$dynlib.ext))))
    if (mode == "candidate") {
        stopifnot(exists("C_dtatools_mutation_info", asNamespace("dtatools")),
                  exists("C_dtatools_owned_info", asNamespace("dtatools")),
                  exists("C_dtatools_native_copy_stats", asNamespace("dtatools")))
    }
    invisible(library_path)
}

owned_native <- function(name, ...) {
    symbol <- get0(name, envir = asNamespace("dtatools"), inherits = FALSE)
    if (is.null(symbol)) return(NULL)
    .Call(symbol, ...)
}

owned_stats <- function() {
    out <- owned_native("C_dtatools_native_copy_stats", FALSE)
    if (is.null(out)) out <- stats::setNames(rep(NA_real_, 6L), c(
        "owned_capture", "compact_copy", "staged_new", "old_journal",
        "native_scratch_allocated", "mutation_target_copy"))
    out
}

owned_fixture <- function(rows, columns = 16L) {
    values <- lapply(seq_len(columns), function(index) {
        out <- dta_double(rep(index + c(0, 0.5, 0.25, 1), length.out = rows))
        attr(out, "label") <- paste("Column", index)
        attr(out, "format.stata") <- "%10.0g"
        out
    })
    names(values) <- sprintf("c%02d", seq_len(columns))
    result <- dibble(!!!values)
    attr(result, "label") <- "Owned double benchmark"
    result
}

owned_columns <- function(data, sort_attributes = TRUE) {
    list(names = names(data), values = column_values(data),
         attributes = lapply(seq_along(data), function(i) {
             out <- attributes(.subset2(data, i))
             if (sort_attributes) out <- out[order(names(out), method = "radix")]
             out
         }))
}

owned_frozen <- function(data) {
    serialize(list(columns = owned_columns(data, sort_attributes = FALSE),
                   metadata = owned_table_metadata(data)), NULL)
}

owned_table_metadata <- function(data) {
    out <- attributes(data)
    out$.dtatools_ref_state <- NULL
    out$row.names <- .row_names_info(data, 0L)
    out[order(names(out), method = "radix")]
}

owned_assert_table <- function(data, frozen, names, rows, classes = NULL) {
    expected <- unserialize(frozen)$metadata
    expected$names <- names
    # These fixtures have automatic row names. Every measured operation keeps
    # that policy; compare the compact bookkeeping, not only displayed names.
    expected$row.names <- if (rows) c(NA_integer_, -as.integer(rows)) else integer()
    if (!is.null(classes)) expected$class <- classes
    stopifnot(identical(owned_table_metadata(data), expected))
    invisible(NULL)
}

owned_expected_columns <- function(frozen) {
    expected <- unserialize(frozen)$columns
    expected$attributes <- lapply(expected$attributes, function(x) x[order(names(x), method = "radix")])
    expected
}

owned_assert_roundtrip <- function(data, frozen) {
    expected <- owned_expected_columns(frozen)
    stopifnot(is_dibble(data), identical(owned_columns(data), expected))
    owned_assert_table(data, frozen, expected$names, length(expected$values[[1L]]))
}

owned_preserved <- function(data, frozen) {
    stopifnot(identical(owned_frozen(data), frozen))
    invisible(NULL)
}

owned_state <- function(data) {
    lapply(seq_along(data), function(i) {
        owned_native("C_dtatools_mutation_info", data, as.integer(i))
    })
}

owned_assert_state <- function(data, mode) {
    if (mode == "candidate") {
        info <- owned_state(data)
        stopifnot(length(info) == ncol(data), all(vapply(info, function(x) {
            !is.null(x$backing) && !x$exposed && x$depth == 1L &&
                x$bytes == nrow(data) * 8
        }, logical(1))))
        stopifnot(all(vapply(seq_along(data), function(i) {
            !is.null(owned_native("C_dtatools_owned_info", .subset2(data, i)))
        }, logical(1))))
    }
    invisible(NULL)
}

owned_pipeline <- function(data) {
    data <- dplyr::rename(data, changed = c01)
    data <- dplyr::select(data, dplyr::everything())
    data <- dplyr::relocate(data, changed, .after = dplyr::last_col())
    data <- dplyr::mutate(data, changed = c02)
    dplyr::rename(data, c01 = changed)
}

owned_profile <- function(operation) {
    path <- tempfile("owned-double-profile-")
    on.exit({ Rprofmem(NULL); unlink(path) }, add = TRUE)
    before <- owned_stats()
    Rprofmem(path)
    value <- operation()
    Rprofmem(NULL)
    native <- owned_stats() - before
    sizes <- suppressWarnings(as.numeric(sub(" .*", "", readLines(path, warn = FALSE))))
    sizes <- sizes[is.finite(sizes)]
    metrics <- c(r_allocated_bytes = sum(sizes),
                 r_largest_allocation_bytes = max(c(0, sizes)),
                 stats::setNames(native, paste0("native_", names(native), "_bytes")))
    list(value = value, metrics = metrics)
}

owned_runner_identity <- function(source_sha, library_path, mode) {
    paths <- c("helpers.R", "owned-double-helpers.R", "owned-double.R", "owned-double-memory.R")
    paths <- file.path("benchmarks/r-dibble-dplyr", paths)
    c(paste("source_sha", source_sha), paste("library", library_path),
      paste("mode", mode), paste("runner_md5", paths, unname(tools::md5sum(paths))),
      capture.output(sessionInfo()))
}
