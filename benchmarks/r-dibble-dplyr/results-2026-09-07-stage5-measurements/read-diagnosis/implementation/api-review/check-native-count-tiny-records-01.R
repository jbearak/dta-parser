# Saved tiny-check records only; no package/helper/DLL or native call is loaded.
root <- "/private/tmp/dta-direct-stage5-validation/root-expression-performance"
expected <- c(empty = 0L, nonmissing = 2L, all_missing = 0L, mixed = 3L)
for (run in c("baseline-ec10-read-count-tiny-01", "candidate-a2d8b6a-read-count-tiny-01")) {
    records <- readRDS(file.path(root, run, "tiny-checks.rds"))
    stopifnot(length(records) == 24L)
    keys <- character()
    for (row in records) {
        stopifnot(row$kind %in% c("logical", "factor", "ordered"), row$case %in% names(expected),
                  row$container %in% c("ordinary", "table_column"),
                  identical(row$expected, unname(expected[row$case])))
        attrs <- if (row$kind == "logical") list(label = "Tiny count control") else list(
            levels = c("a", "b", "unused"), class = if (row$kind == "ordered") c("ordered", "factor") else "factor",
            label = "Tiny count control")
        stopifnot(identical(row$attributes, attrs),
                  identical(row$type, if (row$kind == "logical") "logical" else "integer"))
        keys <- c(keys, paste(row$kind, row$case, row$container))
    }
    stopifnot(length(unique(keys)) == 24L)
    cat("PASS", run, "24 retained kind/case/container/count/type/attribute records\n")
}
