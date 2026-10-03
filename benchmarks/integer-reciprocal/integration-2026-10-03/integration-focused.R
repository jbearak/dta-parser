args <- commandArgs(TRUE)
.libPaths(c(normalizePath(args[[1]]), .libPaths()))
library(dtatools)
library(testthat)
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace('dtatools'),'path')),
                   file.path(normalizePath(args[[1]]),'dtatools')))
results <- testthat::test_dir(args[[2]], package='dtatools', load_package='installed',
    filter='native-arithmetic-kernels|arithmetic-payload-lifetime',
    reporter='silent', stop_on_failure=FALSE)
frame <- as.data.frame(results)
write.csv(frame[c('file','test','passed','failed','error','skipped','warning')], args[[3]], row.names=FALSE)
print(colSums(frame[c('passed','failed','error','skipped','warning')]))
cat('Test blocks:', nrow(frame), '\n')
if (any(frame$failed | frame$error | frame$skipped)) {
    print(frame[frame$failed > 0 | frame$error | frame$skipped,]); quit(status=1)
}
