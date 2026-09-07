args <- commandArgs(TRUE)
if (length(args) != 3L) stop("Expected library, full source revision, and new result path")
if (file.exists(args[[3L]])) stop("Result path already exists")
source("/private/tmp/dta-direct-stage4/benchmarks/r-dibble-dplyr/helpers.R")
validate_benchmark_install(args[[1L]], args[[2L]])
suppressPackageStartupMessages(library(dtatools, lib.loc = args[[1L]]))
stopifnot(identical(normalizePath(find.package("dtatools")),
                    normalizePath(file.path(args[[1L]], "dtatools"))))
stopifnot(identical(normalizePath(getLoadedDLLs()[["dtatools"]][["path"]]),
                    normalizePath(file.path(args[[1L]], "dtatools", "libs",
                                             paste0("dtatools", .Platform$dynlib.ext)))))
native <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
records <- lapply(c(1L, 100000L, 1000000L), function(rows) {
    raw <- rep("aa", rows)
    invisible(native("C_dtatools_native_copy_stats", TRUE))
    value <- dta_string(raw)
    construction <- native("C_dtatools_native_copy_stats", FALSE)
    before <- native("C_dtatools_owned_info", value)
    invisible(native("C_dtatools_native_copy_stats", TRUE))
    native("C_dtatools_owned_set_string", value, 1L, "zz")
    after <- native("C_dtatools_owned_info", value)
    writes <- native("C_dtatools_native_copy_stats", FALSE)
    list(rows = rows, before = before, after = after,
         construction_copies = construction, first_write_copies = writes,
         single_initial_capture = identical(unname(construction[["owned_capture"]]),
                                            rows * .Machine$sizeof.pointer),
         backing_stable = identical(before$backing, after$backing),
         no_first_write_capture = identical(unname(writes[["owned_capture"]]), 0),
         values_correct = identical(as.character(value), c("zz", rep("aa", rows - 1L))),
         source_unchanged = identical(raw, rep("aa", rows)))
})
validate_benchmark_install(args[[1L]], args[[2L]])
checks <- c("single_initial_capture", "backing_stable", "no_first_write_capture",
            "values_correct", "source_unchanged")
record <- list(source = args[[2L]],
               dll_md5 = unname(tools::md5sum(getLoadedDLLs()[["dtatools"]][["path"]])),
               cases = records,
               pass = all(vapply(records, function(x) all(unlist(x[checks])), logical(1))))
saveRDS(record, args[[3L]])
print(record)
if (!record$pass) stop("Fresh constructor copied backing again or failed source/value isolation",
                      call. = FALSE)
