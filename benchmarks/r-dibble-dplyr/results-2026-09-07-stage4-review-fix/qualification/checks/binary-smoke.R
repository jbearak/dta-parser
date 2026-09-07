args <- commandArgs(TRUE)
stopifnot(length(args) == 1L)
lib <- normalizePath(args[[1L]])
.libPaths(c(lib, .libPaths()))
suppressPackageStartupMessages(library(dtatools, lib.loc = lib))
package <- normalizePath(file.path(lib, "dtatools"))
dll <- normalizePath(file.path(package, "libs", paste0("dtatools", .Platform$dynlib.ext)))
stopifnot(identical(normalizePath(find.package("dtatools")), package),
          identical(normalizePath(getLoadedDLLs()[["dtatools"]][["path"]]), dll))
cat("Binary package:", package, "\nDLL:", dll, "\nDLL_md5:", tools::md5sum(dll), "\n")
native <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
for (value in list(c(1.5, 2.5, NA_real_), c(1L, 2L, NA_integer_),
                   c(TRUE, FALSE, NA), c("one", "two", NA_character_),
                   factor(c("one", "two", NA)), ordered(c("one", "two", NA)))) {
    oracle <- unserialize(serialize(value, NULL))
    x <- native("C_dtatools_capture_column", value)
    y <- native("C_dtatools_metadata_copy", x)
    stopifnot(identical(native("C_dtatools_owned_info", x)$backing,
                        native("C_dtatools_owned_info", y)$backing))
    replacement <- switch(typeof(value), double = 9.5, integer = 2L,
                          logical = FALSE, character = "changed")
    native("C_dtatools_patch_vector", x, 1L, replacement)
    stopifnot(identical(y, oracle), identical(value, oracle), !identical(x, oracle))
    first <- unserialize(serialize(x, NULL))
    native("C_dtatools_patch_vector", y, 3L, replacement)
    stopifnot(identical(x, first), identical(value, oracle), !identical(y, oracle))
}
cat("Six atomic storage families preserve source/result isolation.\n")

x <- dta_string(rep("aa", 64L), "str4")
before <- native("C_dtatools_owned_info", x)
stopifnot(!before$shared)
invisible(native("C_dtatools_native_copy_stats", TRUE))
native("C_dtatools_owned_set_string", x, 1L, "bb")
stopifnot(native("C_dtatools_native_copy_stats", FALSE)[["owned_capture"]] == 0,
          identical(before$backing, native("C_dtatools_owned_info", x)$backing),
          identical(as.character(x), c("bb", rep("aa", 63L))))
cat("Binary constructor retains first-private-write readiness.\n")
