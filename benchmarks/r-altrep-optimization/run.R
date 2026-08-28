args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
    stop("usage: run.R OPERATION LABEL", call. = FALSE)
}

operation <- args[[1L]]
label <- args[[2L]]
library(dtaparser)

profile_allocations <- function(expression, threshold) {
    path <- tempfile()
    on.exit(unlink(path), add = TRUE)
    Rprofmem(path, threshold = threshold)
    value <- force(expression)
    Rprofmem(NULL)
    lines <- readLines(path, warn = FALSE)
    sizes <- suppressWarnings(as.numeric(sub(
        " .*", "", lines[grepl("^[0-9]", lines)]
    )))
    list(value = value, bytes = sum(sizes, na.rm = TRUE))
}

compact <- dtaparser:::.is_unmaterialized_numeric_altrep

result <- switch(operation,
    serialize = {
        x <- stata_byte(rep(c(-1, 0, 1, NA_real_), 2500000L))
        before <- compact(x)
        timing <- system.time(raw <- serialize(x, NULL, version = 3))
        restored <- unserialize(raw)
        data.frame(
            operation, label, serialized_bytes = length(raw),
            elapsed_s = unname(timing[["elapsed"]]),
            source_compact_before = before,
            source_compact_after = compact(x),
            result_compact = compact(restored)
        )
    },
    construct = {
        x <- as.double(rep(-100:100, length.out = 1000000L))
        measured <- profile_allocations(stata_int(x), 1024^2)
        data.frame(
            operation, label, allocation_bytes = measured$bytes,
            result_compact = compact(measured$value)
        )
    },
    recode = {
        x <- stata_int(rep(c(1, 2, 3, NA_real_), 2500000L))
        gc(reset = TRUE)
        timing <- system.time(y <- dtaparser::recode(x, `1` = 4))
        heap <- gc()
        data.frame(
            operation, label,
            max_vector_heap_mb = heap["Vcells", 7L],
            elapsed_s = unname(timing[["elapsed"]]),
            result_compact = compact(y)
        )
    },
    `compact-operations` = {
        x <- stata_int(rep(c(1, 2, 3, NA_real_), 250000L))
        selected <- profile_allocations(
            x[seq.int(1L, length(x), 2L)], 100 * 1024
        )
        x <- stata_int(rep(c(1, 2, 3, NA_real_), 250000L))
        copied <- profile_allocations(rlang::duplicate(x), 100 * 1024)
        data.frame(
            operation, label,
            subset_allocation_bytes = selected$bytes,
            duplicate_allocation_bytes = copied$bytes,
            subset_compact = compact(selected$value),
            duplicate_compact = compact(copied$value)
        )
    },
    character = {
        if (!requireNamespace("haven", quietly = TRUE)) {
            stop("the character operation requires haven", call. = FALSE)
        }
        path <- tempfile(fileext = ".dta")
        on.exit(unlink(path), add = TRUE)
        haven::write_dta(data.frame(value = sprintf(
            "category-%03d", rep(1:100, length.out = 1000000L)
        )), path, version = 15)
        x <- read_dta(path)$value
        initial_altrep <- dtaparser:::.is_altrep(x)
        measured <- profile_allocations(
            dtaparser:::.force_altrep_materialization(x), 100 * 1024
        )
        data.frame(
            operation, label, allocation_bytes = measured$bytes,
            source_altrep_before = initial_altrep
        )
    },
    stop("unknown operation: ", operation, call. = FALSE)
)

write.table(result, row.names = FALSE, quote = FALSE, sep = "\t")
