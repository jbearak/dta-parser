args <- commandArgs(TRUE)
stopifnot(length(args) == 1L)
.libPaths(c(normalizePath(args[[1L]]), .libPaths()))
suppressPackageStartupMessages(library(dtatools))
native <- function(name, ...) .Call(get(name, asNamespace('dtatools')), ...)
stats <- function() native('C_dtatools_native_copy_stats', FALSE)
values <- c(-3, 0, 7, NA_real_, tagged_missing(letters))
constructors <- list(byte = dta_byte, int = dta_int, long = dta_long, float = dta_float)
widths <- c(byte = 1, int = 2, long = 4, float = 4)
observed <- list()
for (kind in names(constructors)) for (shared in c(FALSE, TRUE)) {
    expected <- rep(values, 100L)
    source <- constructors[[kind]](expected)
    alias <- if (shared) native('C_dtatools_metadata_copy', source) else NULL
    stopifnot(dtatools:::.is_unmaterialized_numeric_altrep(source))
    private_before <- native('C_dtatools_mutation_info', list(source), 1L)[['backing_private']]
    before <- stats()
    invisible(native('C_dtatools_force_altrep_materialization', source))
    added <- stats() - before
    stopifnot(identical(as.double(source), expected),
              !dtatools:::.is_unmaterialized_numeric_altrep(source))
    if (shared) stopifnot(dtatools:::.is_unmaterialized_numeric_altrep(alias),
                         identical(as.double(alias), expected))
    observed[[length(observed) + 1L]] <- data.frame(kind, shared, private_before,
        rows = length(source), redundant_compact_bytes = added[['compact_copy']],
        compact_payload_bytes = length(source) * widths[[kind]],
        expected_copy_bytes = 0)
    invisible(native('C_dtatools_mutate_first_numeric_altrep', source, 99))
    stopifnot(as.double(source)[1L] == 99)
    if (shared) stopifnot(identical(as.double(alias), expected))
}
result <- do.call(rbind, observed)
print(result, row.names = FALSE)
stopifnot(all(result$redundant_compact_bytes == result$expected_copy_bytes))
