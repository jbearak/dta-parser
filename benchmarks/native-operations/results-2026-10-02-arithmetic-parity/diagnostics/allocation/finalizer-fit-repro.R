# Private diagnostic. Delay one forced GC through successive R allocations so
# the pending finalizer can run inside arithmetic's output allocation. This
# does not claim the exact phase until a malformed result proves stale fit.
# Usage: Rscript --vanilla finalizer-fit-repro.R LIBRARY [MAX_WAIT]
args <- commandArgs(TRUE)
stopifnot(length(args) %in% 1:2)
.libPaths(c(normalizePath(args[[1L]], mustWork=TRUE), .libPaths()))
suppressPackageStartupMessages(library(dtatools))
ns <- asNamespace('dtatools')
native <- function(name, ...) .Call(get(name, ns), ...)
prior_minimum <- native('C_dtatools_test_numeric_size_minimum', 0L)
invisible(dta_double(c(1, 2)) + 1)
maximum <- if (length(args) == 2) as.integer(args[[2L]]) else 240L
observations <- list()
run <- function(wait) {
  x <- dta_byte(rep(1, 128L))
  gc(); gc()
  fired <- 0L
  token <- new.env(parent=emptyenv())
  reg.finalizer(token, function(key) {
    fired <<- fired + 1L
    native('C_dtatools_patch_vector', x, 1L, 100)
  }, onexit=FALSE)
  native('C_dtatools_numeric_entry_stats', TRUE)
  previous <- gctorture2(1000000000L, wait=wait)
  token <- NULL
  result <- tryCatch(x * 2, finally=gctorture2(previous))
  entries <- native('C_dtatools_numeric_entry_stats', FALSE)[['scalar']]
  fired_during <- fired
  first <- as.double(result)[[1L]]
  storage <- dta_storage_type(result)
  gc(); gc()
  stopifnot(fired == 1L, as.double(x)[[1L]] == 100)
  # Before or after the operation may legitimately observe old or new bytes.
  # A stale preflight writes 200 into a byte result, producing -56 instead.
  malformed <- !(first %in% c(2, 200)) || (first == 200 && storage != 'int')
  data.frame(wait=wait, fired_during=fired_during, entries=entries,
             first=first, storage=storage, malformed=malformed)
}
for (wait in seq_len(maximum)) {
  observation <- run(wait)
  observations[[length(observations)+1L]] <- observation
  if (observation$malformed) {
    print(observation)
    break
  }
}
observations <- do.call(rbind, observations)
print(observations[observations$fired_during > 0L, ], row.names=FALSE)
write.csv(observations, file.path('<work>/allocation-probe',
  paste0('finalizer-fit-', Sys.getpid(), '.csv')), row.names=FALSE)
if (any(observations$malformed)) stop('stale arithmetic fit produced invalid value/storage')
cat('No malformed result in sampled GC positions; this is not an exact-window exclusion.\n')
