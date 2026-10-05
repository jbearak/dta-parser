args <- commandArgs(TRUE)
stopifnot(length(args)==3L)
.libPaths(c(normalizePath(args[[1L]]),.libPaths()))
library(dtatools)
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace('dtatools'),'path')),file.path(normalizePath(args[[1L]]),'dtatools')))
filter <- '^(native-arithmetic-kernels|native-arithmetic-parity|compact-float-domain|arithmetic-payload-lifetime|compact-pair-domain|dense-float-reciprocal-kernel|compact-reciprocal-facts|integer-reciprocal-lookup|constructor-region-inputs|dta-numeric)$'
result <- testthat::test_dir(args[[2L]],filter=filter,package='dtatools',reporter='summary',stop_on_failure=TRUE)
table <- as.data.frame(result)
table <- table[, !vapply(table, is.list, logical(1)), drop=FALSE]
write.csv(table,args[[3L]],row.names=FALSE)
stopifnot(all(table$failed==0),all(!table$error),all(table$warning==0),all(!table$skipped))
cat(sum(table$nb),'assertions in',nrow(table),'blocks\n')
