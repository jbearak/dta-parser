# Exact-window invariant probe. The private DLL inserts R_gc() immediately after
# integer preflight. Default Rscript defers finalizers through ordinary native
# allocations; this simulates the optional IMMEDIATE_FINALIZERS build instead.
.libPaths(c('<work>/finalizer-checkpoint/library', .libPaths()))
suppressPackageStartupMessages(library(dtatools))
ns <- asNamespace('dtatools')
native <- function(name, ...) .Call(get(name, ns), ...)
native('C_dtatools_test_numeric_size_minimum', 0L)
invisible(dta_double(c(1,2)) + 1)
x <- dta_byte(rep(1,128L))
stopifnot(native('C_dtatools_is_numeric_altrep', x))
gc(); gc()
fired <- 0L
token <- new.env(parent=emptyenv())
reg.finalizer(token, function(key) {
  fired <<- fired + 1L
  native('C_dtatools_patch_vector', x, 1L, 100)
}, onexit=FALSE)
token <- NULL
native('C_dtatools_numeric_entry_stats', TRUE)
result <- x * 2
entries <- native('C_dtatools_numeric_entry_stats', FALSE)[['scalar']]
record <- list(fired=fired, native_entries=entries, input_first=as.double(x)[[1L]],
               output_first=as.double(result)[[1L]], storage=dta_storage_type(result))
dput(record)
stopifnot(fired == 1L, entries == 1, record$input_first == 100)
stopifnot(record$output_first %in% c(2,200),
          record$output_first != 200 || record$storage == 'int')
