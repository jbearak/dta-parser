args <- commandArgs(TRUE)
if (length(args) != 1L || file.exists(args[[1L]])) stop('New result path required')
lib <- '/private/tmp/dta-direct-stage4-validation/candidate-e343b3b-library'
sha <- 'e343b3b56a8529e9ee0ac40f8bd88beebcd2be15'
source('/private/tmp/dta-direct-stage4/benchmarks/r-dibble-dplyr/helpers.R')
validate_benchmark_install(lib, sha)
suppressPackageStartupMessages(library(dtatools, lib.loc = lib))
stopifnot(identical(normalizePath(find.package('dtatools')), normalizePath(file.path(lib, 'dtatools'))))
native <- function(name, ...) .Call(get(name, asNamespace('dtatools')), ...)
records <- list()
for (rows in c(1L, 64L, 1000L)) for (collect in c(FALSE, TRUE)) for (constructor in c(TRUE, FALSE)) {
  raw <- rep('aa', rows)
  value <- if (constructor) dta_string(raw, 'str4') else native('C_dtatools_capture_column', raw)
  if (collect) gc()
  before <- native('C_dtatools_owned_info', value)
  invisible(native('C_dtatools_native_copy_stats', TRUE))
  native('C_dtatools_owned_set_string', value, 1L, 'zz')
  stats <- native('C_dtatools_native_copy_stats', FALSE)
  after <- native('C_dtatools_owned_info', value)
  stopifnot(identical(raw, rep('aa', rows)), identical(as.character(value), c('zz', rep('aa', rows-1L))))
  records[[length(records)+1L]] <- data.frame(rows, collect, constructor, shared_before=before$shared,
    copy=stats[['owned_capture']], backing_stable=identical(before$backing, after$backing))
}
validate_benchmark_install(lib, sha)
result <- do.call(rbind, records)
write.csv(result, args[[1L]], row.names=FALSE)
print(result)
stopifnot(all(result$backing_stable))
