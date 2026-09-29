# Report-only regression comparison. Run once per explicit installed library:
# Rscript compare-numeric-lifetimes.R LIBRARY LABEL OUTPUT.csv
# Requires bench and the package dependencies. Setup and assertions are untimed.
args <- commandArgs(trailingOnly = TRUE)
.libPaths(c(args[[1L]], .libPaths()))
suppressPackageStartupMessages(library(dtatools))
stopifnot(normalizePath(find.package("dtatools")) == normalizePath(file.path(args[[1L]], "dtatools")))
ns <- asNamespace("dtatools")
cc <- function(name, ...) .Call(get(name, ns), ...)
n <- 100000L
values <- rep(c(1, 2, -0, 4), length.out = n)
owned <- cc("C_dtatools_capture_column", values)
attrs <- attributes(dta_double(double()))
data <- dibble(x = dta_double(rep(0, n)))
compact <- cc("C_dtatools_owned_numeric_freeze", dta_byte(rep(c(1, 2, 3, 4), length.out = n)), 1024)
rows <- seq.int(1L, n, by = 10L)
grouped <- dibble(x = compact, g = rep(1:10, length.out = n))
public <- dibble(x = dta_double(values))
cases <- list(
    fit_plain = function() cc("C_dtatools_replacement_fits", values, NULL, FALSE, 4L),
    replace_owned = function() cc("C_dtatools_patch_slot", data, 1L, NULL, owned, FALSE),
    generate_plain = function() cc("C_dtatools_generate_numeric", values, NULL, as.double(n), 4L, 0L, attrs),
    generate_owned = function() cc("C_dtatools_generate_numeric", owned, NULL, as.double(n), 4L, 0L, attrs),
    gather_retained = function() cc("C_dtatools_gather_numeric_columns", list(compact), NULL, rows, NULL)[[1L]],
    public_replace = function() set_dta_values(data, "x", values),
    public_gen = function() { result <- copy_data(public); gen(result, y = x + 1); result },
    public_grouped = function() { result <- copy_data(grouped); result[, y := x + 1, by = g]; result }
)
expected <- list(TRUE, values, values, values, as.double(compact)[rows], values, values + 1, as.double(compact) + 1)
extract <- list(identity, function(x) as.double(x$x), as.double, as.double, as.double,
    function(x) as.double(x$x), function(x) as.double(x$y), function(x) as.double(x$y))
observations <- list()
for (i in seq_along(cases)) {
    operation <- cases[[i]]
    stopifnot(identical(extract[[i]](operation()), expected[[i]]))
    invisible(gc())
    sample <- bench::mark(operation(), iterations = 100, check = FALSE, memory = TRUE, filter_gc = FALSE)
    stopifnot(identical(extract[[i]](operation()), expected[[i]]))
    observations[[i]] <- data.frame(label = args[[2L]], workload = names(cases)[[i]],
        iteration = seq_along(sample$time[[1L]]), seconds = as.numeric(sample$time[[1L]]),
        allocated_bytes = as.numeric(sample$mem_alloc), gc = rowSums(sample$gc[[1L]]))
}
write.csv(do.call(rbind, observations), args[[3L]], row.names = FALSE)
cat("Validated", length(cases), "workloads at", n, "rows\n")
cat("Package:", find.package("dtatools"), "\nDLL:", getLoadedDLLs()[["dtatools"]][["path"]], "\n")
print(sessionInfo())
