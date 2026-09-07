# Saved ordinary R values only; no package/helper/DLL loading or measured calls.
root <- "/private/tmp/dta-direct-stage5-validation/root-expression-performance"
expected <- list(empty = character(), nonmissing = c("a", ""),
                 missing_first = NA_character_, missing_last = c("a", NA_character_))
for (run in c("baseline-ec10-read-fixture-diagnostic-01", "candidate-a2d8b6a-read-fixture-diagnostic-01")) {
    records <- readRDS(file.path(root, run, "fixture-observations.rds"))
    # dget reads the retained plain-data representation, not a control driver.
    stopifnot(identical(records, dget(file.path(root, run, "fixture-observations.R"))), length(records) == 8L)
    keys <- character()
    for (record in records) {
        raw <- expected[[record$case]]
        stored <- raw
        stored[is.na(stored)] <- ""
        table <- identical(record$container, "table_column")
        values <- if (table) stored else raw
        attributes <- if (!table) NULL else list(stata.string.storage = if (anyNA(raw)) "str1" else "str12")
        visits <- if (anyNA(values)) match(NA_character_, values) else length(values)
        stopifnot(identical(record$original, raw), identical(record$actual, values),
                  identical(record$attributes, attributes), !record$is_object,
                  identical(record$actual_any_na, anyNA(values)),
                  identical(record$native_elt, anyNA(values)),
                  identical(record$native_pointer, anyNA(values)),
                  identical(record$native_visits, as.double(visits)),
                  identical(record$original_identical_predicate, !(table && anyNA(raw))))
        keys <- c(keys, paste(record$case, record$container))
    }
    stopifnot(length(unique(keys)) == 8L,
              setequal(keys, as.vector(outer(names(expected), c("ordinary", "table_column"), paste))))
    cat("PASS", run, "8 saved fixture/container records\n")
}
