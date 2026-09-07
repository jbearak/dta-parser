args <- commandArgs(TRUE)
if (length(args) != 1L || file.exists(args[[1L]])) stop("Expected new result path")
library_path <- "/private/tmp/dta-direct-stage4-validation/candidate-e343b3b-library"
expected <- "e343b3b56a8529e9ee0ac40f8bd88beebcd2be15"
source("/private/tmp/dta-direct-stage4/benchmarks/r-dibble-dplyr/helpers.R")
validate_benchmark_install(library_path, expected)
suppressPackageStartupMessages(library(dtatools, lib.loc = library_path))
native <- function(name, ...) .Call(get(name, asNamespace("dtatools")), ...)
measure <- function(make, count) {
    value <- make(count)
    before <- native("C_dtatools_owned_info", value)
    invisible(native("C_dtatools_native_copy_stats", TRUE))
    invisible(native("C_dtatools_owned_set_string", value, 1L, "zz"))
    after <- native("C_dtatools_owned_info", value)
    list(before = before, after = after,
         copied_bytes = unname(native("C_dtatools_native_copy_stats", FALSE)[["owned_capture"]]),
         backing_stable = identical(before$backing, after$backing),
         correct = identical(as.character(value)[[1L]], "zz"))
}
captured <- function(count) native("C_dtatools_capture_column", rep("aa", count))
constructed <- function(count) dta_string(rep("aa", count))
retained_input <- rep("aa", 100000L)
results <- list(
    one_element = measure(constructed, 1L),
    private_capture = measure(captured, 100000L),
    retained_caller = measure(function(count) dta_string(retained_input), 100000L)
)
raw <- native("C_dtatools_capture_string", rep("aa", 1L))
results$attribute_steps <- list(capture = native("C_dtatools_owned_info", raw))
with_storage <- native("C_dtatools_owned_string_attribute", raw, "stata.string.storage", "str2")
results$attribute_steps$storage <- native("C_dtatools_owned_info", with_storage)
with_class <- native("C_dtatools_owned_string_attribute", with_storage, "class", c("dta_string", "vctrs_vctr", "character"))
results$attribute_steps$class <- native("C_dtatools_owned_info", with_class)
results$attribute_steps$final_capture <- native("C_dtatools_owned_info", native("C_dtatools_capture_column", with_class))
results$retained_input_unchanged <- identical(retained_input, rep("aa", 100000L))
validate_benchmark_install(library_path, expected)
saveRDS(results, args[[1L]])
print(results)
stopifnot(results$one_element$copied_bytes == 8,
          results$private_capture$copied_bytes == 0,
          results$private_capture$backing_stable,
          results$retained_caller$copied_bytes == 800000,
          results$retained_input_unchanged,
          !results$attribute_steps$capture$shared,
          results$attribute_steps$storage$shared,
          results$attribute_steps$class$shared,
          results$attribute_steps$final_capture$shared)
cat("PASS: constructor-specific sticky sharing reproduced; generic private capture stays private.\n")
