# Stage 4 uses deterministic ordinary values as the oracle. Do not serialize
# a measured owned handle to make an oracle: serialization may expose backing.
source("benchmarks/r-dibble-dplyr/owned-double-helpers.R")

atomic_kinds <- c("string", "declared_character", "logical", "factor", "ordered")
atomic_runner_paths <- file.path("benchmarks/r-dibble-dplyr", c(
    "helpers.R", "owned-double-helpers.R", "owned-atomic-helpers.R",
    "owned-atomic.R", "owned-atomic-memory.R"))

atomic_start <- function(library_path, source_sha, mode) {
    out <- owned_benchmark_start(library_path, source_sha, mode)
    if (mode == "candidate") stopifnot(
        exists("C_dtatools_owned_scan_stats", asNamespace("dtatools")))
    out
}

atomic_identity <- function(source_sha, library_path, mode) {
    c(paste("source_sha", source_sha), paste("library", library_path),
      paste("mode", mode), paste("runner_md5", atomic_runner_paths,
                                unname(tools::md5sum(atomic_runner_paths))),
      capture.output(sessionInfo()))
}

atomic_raw <- function(kind, rows, columns = 16L) {
    stopifnot(kind %in% atomic_kinds)
    result <- lapply(seq_len(columns), function(i) {
        value <- switch(kind,
            string = structure(rep(c(sprintf("a%04d", i), "", "\u00e9",
                                      sprintf("b%04d", i)), length.out = rows),
                               class = c("dta_string", "vctrs_vctr", "character"),
                               stata.string.storage = "str12"),
            declared_character = structure(rep(c(sprintf("a%04d", i), "", "\u00e9",
                                                  sprintf("b%04d", i)), length.out = rows),
                                           stata.string.storage = "str12"),
            logical = rep(c(TRUE, FALSE, NA, TRUE), length.out = rows),
            factor = factor(rep(c("b", "a", NA, "b"), length.out = rows),
                            levels = c("a", "b", "unused")),
            ordered = ordered(rep(c("b", "a", NA, "b"), length.out = rows),
                              levels = c("a", "b", "unused")))
        attr(value, "label") <- paste("Column", i)
        value
    })
    names(result) <- sprintf("c%02d", seq_len(columns))
    result
}

atomic_columns <- function(data) {
    c(owned_columns(data), list(types = vapply(seq_along(data), function(i) {
        typeof(.subset2(data, i))
    }, "")))
}

atomic_fixture <- function(kind, rows, columns = 16L) {
    raw <- atomic_raw(kind, rows, columns)
    result <- as_dibble(tibble::new_tibble(raw, nrow = rows))
    attr(result, "label") <- "Owned atomic benchmark"
    stopifnot(identical(atomic_columns(result), atomic_columns(raw)))
    result
}

atomic_frozen <- function(data, kind, rows = nrow(data), columns = ncol(data)) {
    serialize(list(columns = atomic_columns(atomic_raw(kind, rows, columns)),
                   metadata = owned_table_metadata(data),
                   column_attribute_names = lapply(seq_along(data), function(i) names(attributes(.subset2(data, i)))),
                   table_attribute_names = setdiff(names(attributes(data)), ".dtatools_ref_state")), NULL)
}

atomic_expected <- function(frozen, indices = NULL, names = NULL, rows = NULL) {
    out <- unserialize(frozen)$columns
    if (!is.null(indices)) {
        out <- list(names = out$names[indices], values = out$values[indices],
                    attributes = out$attributes[indices], types = out$types[indices])
    }
    if (!is.null(names)) out$names <- names
    if (!is.null(rows)) out$values <- lapply(out$values, `[`, rows)
    out
}

atomic_check <- function(data, frozen, expected = atomic_expected(frozen),
                         rows = length(expected$values[[1L]]), classes = NULL) {
    stopifnot(identical(atomic_columns(data), expected))
    owned_assert_table(data, frozen, expected$names, rows, classes)
    invisible(NULL)
}

atomic_preserved <- function(data, frozen) {
    atomic_check(data, frozen)
    original <- unserialize(frozen)
    stopifnot(identical(lapply(seq_along(data), function(i) names(attributes(.subset2(data, i)))),
                        original$column_attribute_names),
              identical(setdiff(names(attributes(data)), ".dtatools_ref_state"),
                        original$table_attribute_names))
    invisible(NULL)
}

atomic_state <- function(data, mode) {
    info <- owned_state(data)
    if (mode == "candidate") {
        stopifnot(all(vapply(seq_along(data), function(i) {
            x <- info[[i]]
            bytes <- nrow(data) * if (is.character(.subset2(data, i))) .Machine$sizeof.pointer else 4
            !is.null(x$backing) && !x$exposed && x$depth == 1L && x$bytes == bytes &&
                !is.null(owned_native("C_dtatools_owned_info", .subset2(data, i)))
        }, logical(1))))
    }
    info
}

atomic_backings <- function(info) vapply(info, function(x) {
    if (is.null(x$backing)) NA_character_ else x$backing
}, "")

atomic_unchanged_backings <- function(before, data, mode) {
    after <- atomic_state(data, mode)
    if (mode == "candidate") stopifnot(identical(atomic_backings(before), atomic_backings(after)))
    invisible(after)
}

atomic_scans <- function() {
    out <- owned_native("C_dtatools_owned_scan_stats", FALSE)
    if (is.null(out)) out <- c(NA_real_, NA_real_)
    stats::setNames(out, c("validation_scan_calls", "validation_scanned_values"))
}

atomic_profile <- function(operation) {
    before <- atomic_scans()
    out <- owned_profile(operation)
    out$metrics <- c(out$metrics, atomic_scans() - before)
    out
}

atomic_selector_gate <- function(metrics, kind, mode) {
    if (mode == "candidate") {
        stopifnot(metrics[["r_allocated_bytes"]] < 1000000,
                  metrics[["native_owned_capture_bytes"]] == 0,
                  metrics[["native_mutation_target_copy_bytes"]] == 0)
        if (kind %in% c("string", "declared_character")) stopifnot(
            metrics[["validation_scan_calls"]] == 0,
            metrics[["validation_scanned_values"]] == 0)
    }
}

atomic_pipeline_expected <- function(frozen, operation) {
    old_names <- unserialize(frozen)$columns$names
    if (operation == "rename") {
        atomic_expected(frozen, names = c("changed", old_names[-1L]))
    } else if (operation == "select") {
        atomic_expected(frozen)
    } else if (operation == "relocate") {
        atomic_expected(frozen, indices = c(2:16, 1L))
    } else {
        atomic_expected(frozen, indices = c(2:16, 2L), names = c(old_names[-1L], "c01"))
    }
}

# Independent expectations for the two file formats. DTA cannot preserve a
# logical or factor class. Arrow preserves those classes and factor levels.
atomic_io_expected <- function(kind, rows, columns, format) {
    raw <- atomic_raw(kind, rows, columns)
    for (i in seq_along(raw)) {
        if (kind %in% c("string", "declared_character")) {
            attributes(raw[[i]]) <- list(class = c("dta_string", "vctrs_vctr", "character"),
                stata.string.storage = "str12", label = paste("Column", i), format.stata = "%12s")
        } else if (format == "dta") {
            logical <- kind == "logical"
            value <- as.double(raw[[i]])
            attributes(value) <- list(
                class = if (logical) c("dta_numeric", "dta_byte", "vctrs_vctr", "double") else
                    c("dta_numeric", "dta_long", "haven_labelled", "vctrs_vctr", "double"),
                stata.storage = if (logical) "byte" else "long",
                label = paste("Column", i), format.stata = if (logical) "%8.0g" else "%12.0g")
            if (!logical) attr(value, "labels") <- c(a = 1, b = 2, unused = 3)
            raw[[i]] <- value
        }
    }
    atomic_columns(raw)
}

atomic_write_dta <- function(data, path, kind) {
    expected <- if (kind %in% c("factor", "ordered")) paste0(
        "Converted factor columns to labelled Stata long integers: ",
        paste(sprintf("`%s`", names(data)), collapse = ", "),
        ". Factor class and orderedness will not be restored on read.") else character()
    warnings <- character()
    withCallingHandlers(save_dta(data, path), warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        if (conditionMessage(w) %in% expected) invokeRestart("muffleWarning")
    })
    stopifnot(identical(warnings, expected))
    invisible(NULL)
}
