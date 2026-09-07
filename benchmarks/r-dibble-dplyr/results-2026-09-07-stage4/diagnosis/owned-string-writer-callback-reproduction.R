# Bounded reproduction extracted from the writer regression test at 976cc40.
# This is a new independent replay; read-fixes-red.log is the original red run.
args <- commandArgs(TRUE)
stopifnot(length(args) == 2L)
source('benchmarks/r-dibble-dplyr/helpers.R')
validate_benchmark_install(args[[1L]], args[[2L]])
.libPaths(c(args[[1L]], .libPaths()))
suppressPackageStartupMessages(library(dtatools, lib.loc = args[[1L]]))
cat('source', args[[2L]], '\nDLL_md5', tools::md5sum(getLoadedDLLs()[['dtatools']][['path']]), '\n')
ns <- asNamespace('dtatools')
native <- function(name, ...) .Call(get(name, ns), ...)
original <- c('alpha', 'beta', 'alpha')
value <- native('C_dtatools_capture_column', original)
specification <- get('.prepare_arrow_write', ns)(tibble::tibble(x = value, y = c('a', 'b', 'c')), NULL, TRUE)
value <- specification[[3L]][[1L]]$values
stopifnot(!is.null(native('C_dtatools_owned_info', value)))
invisible(native('C_dtatools_metadata_copy', value))
calls <- 0L
callback <- function() {
    calls <<- calls + 1L
    native('C_dtatools_patch_vector', value, NULL, 'changed')
    gc()
}
specification[[3L]][[2L]]$name <- native('C_dtatools_callback_character', 'y', callback)
path <- tempfile(fileext = '.arrow')
native('C_dtatools_save_arrow', specification, path, 'uncompressed', 1L, TRUE)
restored <- read_arrow(path)
unlink(path)
cat('callback_count', calls, '\nobserved writer values:'); dput(as.character(restored$x))
stopifnot(identical(calls, 1L), identical(as.character(value), rep('changed', 3L)),
          identical(as.character(restored$y), c('a', 'b', 'c')))
validate_benchmark_install(args[[1L]], args[[2L]])
stopifnot(identical(as.character(restored$x), original))
cat('Writer snapshot preserved after actual callback write.\n')
