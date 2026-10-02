args <- commandArgs(TRUE)
.libPaths(c(args[[1L]], .libPaths()))
library(dtatools)
x <- read_dta('<reader-work>/fixtures/compact.dta',threads=1L)[[1L]]
y <- readRDS('<reader-work>/fixtures/compact.rds')[[1L]]
lazy <- get('.is_unmaterialized_numeric_altrep',asNamespace('dtatools'))
expected <- is.na(y)
stopifnot(lazy(x),identical(is.na(x),expected))
work <- compiler::cmpfun(function(x) {out <- NULL; for(i in 1:32) out <- is.na(x); out})
records <- list()
for (round in 1:4) for(kind in if(round%%2) c('plain','compact') else c('compact','plain')) {
 invisible(gc(full=TRUE)); t <- proc.time(); value <- work(if(kind=='plain')y else x); dt <- proc.time()-t
 stopifnot(identical(value,expected),lazy(x))
 records[[length(records)+1L]] <- data.frame(round=round,kind=kind,cpu=dt[['user.self']]+dt[['sys.self']],wall=dt[['elapsed']])
}
results <- do.call(rbind,records);write.csv(results,args[[2L]],row.names=FALSE)
ratio <- median(results$cpu[results$kind=='compact']/results$cpu[results$kind=='plain'])
cat(sprintf('Classed compact is.na / ordinary doubles CPU: %.2fx; parity target <= 1.25x\n',ratio))
if (ratio>1.25) {cat('RED\n');quit(status=42L)}
cat('GREEN\n')
